//! VMA-style Vulkan memory allocator with sub-allocation, pooling, and ReBAR awareness
//! Optimized for NVIDIA RTX 40 series GPUs on Linux

const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const memory_mod = @import("memory.zig");
const physical_device = @import("physical_device.zig");

const log = std.log.scoped(.allocator);

/// Default block size for memory pools (256MB)
pub const DEFAULT_BLOCK_SIZE: types.VkDeviceSize = 256 * 1024 * 1024;

/// Minimum allocation size threshold for dedicated allocations (16MB)
pub const DEDICATED_ALLOCATION_THRESHOLD: types.VkDeviceSize = 16 * 1024 * 1024;

/// Allocation strategy
pub const AllocationStrategy = enum {
    /// Best fit - minimize fragmentation
    best_fit,
    /// First fit - fastest allocation
    first_fit,
    /// Worst fit - for large allocations
    worst_fit,
};

/// Memory usage hints
pub const MemoryUsage = enum {
    /// Device-local memory, not accessible by CPU
    gpu_only,
    /// CPU-to-GPU transfer (staging buffers)
    cpu_to_gpu,
    /// GPU-to-CPU transfer (readback)
    gpu_to_cpu,
    /// CPU frequently writes, GPU reads (uniform buffers, dynamic data)
    cpu_only,
    /// ReBAR: device-local + host-visible (requires ReBAR/SAM)
    gpu_lazily_allocated,
    /// Custom - user provides exact memory type
    custom,
};

/// Allocation flags
pub const AllocationFlags = packed struct(u32) {
    /// Prefer dedicated allocation (own VkDeviceMemory)
    dedicated: bool = false,
    /// Map memory on allocation
    mapped: bool = false,
    /// Can be defragmented
    can_defragment: bool = true,
    /// Create in upper address range (for debugging)
    upper_address: bool = false,
    /// Never alias with other allocations
    never_alias: bool = false,
    _padding: u27 = 0,
};

/// Sub-allocation within a memory block
pub const SubAllocation = struct {
    offset: types.VkDeviceSize,
    size: types.VkDeviceSize,
    is_free: bool,
    next: ?*SubAllocation,
    prev: ?*SubAllocation,
};

/// Memory block (large VkDeviceMemory that gets sub-allocated)
pub const MemoryBlock = struct {
    memory: types.VkDeviceMemory,
    size: types.VkDeviceSize,
    type_index: u32,
    mapped_ptr: ?*anyopaque,
    allocations: std.ArrayList(SubAllocation),
    free_list: ?*SubAllocation,
    allocated_bytes: types.VkDeviceSize,
    allocation_count: usize,

    pub fn init(allocator: std.mem.Allocator, memory: types.VkDeviceMemory, size: types.VkDeviceSize, type_index: u32) !*MemoryBlock {
        var block = try allocator.create(MemoryBlock);
        block.* = .{
            .memory = memory,
            .size = size,
            .type_index = type_index,
            .mapped_ptr = null,
            .allocations = std.ArrayList(SubAllocation).init(allocator),
            .free_list = null,
            .allocated_bytes = 0,
            .allocation_count = 0,
        };

        // Create initial free sub-allocation spanning entire block
        const initial = try block.allocations.addOne();
        initial.* = .{
            .offset = 0,
            .size = size,
            .is_free = true,
            .next = null,
            .prev = null,
        };
        block.free_list = initial;

        return block;
    }

    pub fn deinit(self: *MemoryBlock, allocator: std.mem.Allocator, device: *device_mod.Device) void {
        if (self.mapped_ptr != null) {
            const device_handle = device.handle orelse return;
            device.dispatch.unmap_memory(device_handle, self.memory);
        }
        const device_handle = device.handle orelse return;
        device.dispatch.free_memory(device_handle, self.memory, device.allocation_callbacks);
        self.allocations.deinit();
        allocator.destroy(self);
    }

    /// Allocate a sub-allocation from this block
    pub fn allocate(self: *MemoryBlock, size: types.VkDeviceSize, alignment: types.VkDeviceSize, strategy: AllocationStrategy) ?SubAllocationHandle {
        var best_fit: ?*SubAllocation = null;
        var best_fit_size: types.VkDeviceSize = std.math.maxInt(types.VkDeviceSize);

        var current = self.free_list;
        while (current) |chunk| : (current = chunk.next) {
            if (!chunk.is_free) continue;

            // Calculate aligned offset
            const aligned_offset = std.mem.alignForward(types.VkDeviceSize, chunk.offset, alignment);
            const padding = aligned_offset - chunk.offset;

            if (padding >= chunk.size) continue;
            const usable_size = chunk.size - padding;
            if (usable_size < size) continue;

            switch (strategy) {
                .best_fit => {
                    if (usable_size < best_fit_size) {
                        best_fit = chunk;
                        best_fit_size = usable_size;
                    }
                },
                .first_fit => {
                    best_fit = chunk;
                    break;
                },
                .worst_fit => {
                    if (usable_size > best_fit_size or best_fit == null) {
                        best_fit = chunk;
                        best_fit_size = usable_size;
                    }
                },
            }
        }

        if (best_fit) |chunk| {
            const aligned_offset = std.mem.alignForward(types.VkDeviceSize, chunk.offset, alignment);

            // Mark chunk as allocated
            chunk.offset = aligned_offset;
            chunk.size = size;
            chunk.is_free = false;

            self.allocated_bytes += size;
            self.allocation_count += 1;

            return SubAllocationHandle{
                .block = self,
                .offset = aligned_offset,
                .size = size,
            };
        }

        return null;
    }

    /// Free a sub-allocation and coalesce with neighbors
    pub fn free(self: *MemoryBlock, offset: types.VkDeviceSize) void {
        for (self.allocations.items) |*chunk| {
            if (chunk.offset == offset and !chunk.is_free) {
                chunk.is_free = true;
                self.allocated_bytes -= chunk.size;
                self.allocation_count -= 1;

                // TODO: Coalesce with adjacent free chunks
                return;
            }
        }
    }
};

/// Handle to a sub-allocation
pub const SubAllocationHandle = struct {
    block: *MemoryBlock,
    offset: types.VkDeviceSize,
    size: types.VkDeviceSize,

    pub fn getMemory(self: SubAllocationHandle) types.VkDeviceMemory {
        return self.block.memory;
    }

    pub fn getMappedPtr(self: SubAllocationHandle) ?[*]u8 {
        if (self.block.mapped_ptr) |base| {
            const ptr = @as([*]u8, @ptrCast(base));
            return ptr + @as(usize, @intCast(self.offset));
        }
        return null;
    }
};

/// Memory pool for a specific memory type
pub const MemoryPool = struct {
    allocator: std.mem.Allocator,
    device: *device_mod.Device,
    type_index: u32,
    block_size: types.VkDeviceSize,
    blocks: std.ArrayList(*MemoryBlock),
    strategy: AllocationStrategy,

    pub fn init(allocator: std.mem.Allocator, device: *device_mod.Device, type_index: u32, block_size: types.VkDeviceSize) MemoryPool {
        return .{
            .allocator = allocator,
            .device = device,
            .type_index = type_index,
            .block_size = block_size,
            .blocks = std.ArrayList(*MemoryBlock).init(allocator),
            .strategy = .best_fit,
        };
    }

    pub fn deinit(self: *MemoryPool) void {
        for (self.blocks.items) |block| {
            block.deinit(self.allocator, self.device);
        }
        self.blocks.deinit();
    }

    /// Allocate from this pool
    pub fn allocate(self: *MemoryPool, size: types.VkDeviceSize, alignment: types.VkDeviceSize) !SubAllocationHandle {
        // Try existing blocks first
        for (self.blocks.items) |block| {
            if (block.allocate(size, alignment, self.strategy)) |handle| {
                return handle;
            }
        }

        // Need a new block
        const block_size = @max(self.block_size, size);
        const memory = try self.createBlock(block_size);
        const block = try MemoryBlock.init(self.allocator, memory, block_size, self.type_index);
        try self.blocks.append(block);

        return block.allocate(size, alignment, self.strategy) orelse errors.Error.OutOfMemory;
    }

    fn createBlock(self: *MemoryPool, size: types.VkDeviceSize) !types.VkDeviceMemory {
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;
        const info = types.VkMemoryAllocateInfo{
            .allocationSize = size,
            .memoryTypeIndex = self.type_index,
        };

        var memory: types.VkDeviceMemory = undefined;
        try errors.ensureSuccess(self.device.dispatch.allocate_memory(device_handle, &info, self.device.allocation_callbacks, &memory));

        log.debug("Created memory block: type={}, size={} bytes", .{ self.type_index, size });
        return memory;
    }

    /// Get total allocated bytes across all blocks
    pub fn getTotalAllocated(self: *MemoryPool) types.VkDeviceSize {
        var total: types.VkDeviceSize = 0;
        for (self.blocks.items) |block| {
            total += block.allocated_bytes;
        }
        return total;
    }

    /// Get fragmentation ratio (0.0 = no fragmentation, 1.0 = highly fragmented)
    pub fn getFragmentation(self: *MemoryPool) f32 {
        var total_size: types.VkDeviceSize = 0;
        var total_allocated: types.VkDeviceSize = 0;

        for (self.blocks.items) |block| {
            total_size += block.size;
            total_allocated += block.allocated_bytes;
        }

        if (total_size == 0) return 0.0;

        const utilization = @as(f32, @floatFromInt(total_allocated)) / @as(f32, @floatFromInt(total_size));
        return 1.0 - utilization;
    }
};

/// Main allocator managing all memory pools
pub const Allocator = struct {
    allocator: std.mem.Allocator,
    device: *device_mod.Device,
    memory_properties: types.VkPhysicalDeviceMemoryProperties,
    pools: std.ArrayList(MemoryPool),
    has_rebar: bool,

    // Telemetry
    total_allocations: usize,
    total_allocated_bytes: types.VkDeviceSize,
    peak_allocated_bytes: types.VkDeviceSize,

    pub fn init(allocator: std.mem.Allocator, device: *device_mod.Device, memory_properties: types.VkPhysicalDeviceMemoryProperties) !*Allocator {
        var self = try allocator.create(Allocator);
        self.* = .{
            .allocator = allocator,
            .device = device,
            .memory_properties = memory_properties,
            .pools = std.ArrayList(MemoryPool).init(allocator),
            .has_rebar = physical_device.detectReBAR(memory_properties),
            .total_allocations = 0,
            .total_allocated_bytes = 0,
            .peak_allocated_bytes = 0,
        };

        // Create pools for each memory type
        for (0..memory_properties.memoryTypeCount) |i| {
            const pool = MemoryPool.init(allocator, device, @intCast(i), DEFAULT_BLOCK_SIZE);
            try self.pools.append(pool);
        }

        if (self.has_rebar) {
            log.info("ReBAR detected - enabling host-visible device-local allocations", .{});
        }

        return self;
    }

    pub fn deinit(self: *Allocator) void {
        for (self.pools.items) |*pool| {
            pool.deinit();
        }
        self.pools.deinit();
        self.allocator.destroy(self);
    }

    /// Allocate memory based on usage hint
    pub fn allocateMemory(
        self: *Allocator,
        requirements: types.VkMemoryRequirements,
        usage: MemoryUsage,
        flags: AllocationFlags,
    ) !AllocationHandle {
        const type_index = try self.findMemoryType(requirements, usage);
        const alignment = @max(requirements.alignment, 1);

        // Use dedicated allocation for large allocations
        if (flags.dedicated or requirements.size >= DEDICATED_ALLOCATION_THRESHOLD) {
            return self.allocateDedicated(requirements.size, type_index);
        }

        // Sub-allocate from pool
        const handle = try self.pools.items[type_index].allocate(requirements.size, alignment);

        self.total_allocations += 1;
        self.total_allocated_bytes += requirements.size;
        self.peak_allocated_bytes = @max(self.peak_allocated_bytes, self.total_allocated_bytes);

        return AllocationHandle{
            .allocator = self,
            .sub_allocation = handle,
            .is_dedicated = false,
            .size = requirements.size,
        };
    }

    fn allocateDedicated(self: *Allocator, size: types.VkDeviceSize, type_index: u32) !AllocationHandle {
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;
        const info = types.VkMemoryAllocateInfo{
            .allocationSize = size,
            .memoryTypeIndex = type_index,
        };

        var memory: types.VkDeviceMemory = undefined;
        try errors.ensureSuccess(self.device.dispatch.allocate_memory(device_handle, &info, self.device.allocation_callbacks, &memory));

        log.debug("Dedicated allocation: type={}, size={} bytes", .{ type_index, size });

        self.total_allocations += 1;
        self.total_allocated_bytes += size;
        self.peak_allocated_bytes = @max(self.peak_allocated_bytes, self.total_allocated_bytes);

        return AllocationHandle{
            .allocator = self,
            .dedicated_memory = memory,
            .is_dedicated = true,
            .size = size,
        };
    }

    fn findMemoryType(self: *Allocator, requirements: types.VkMemoryRequirements, usage: MemoryUsage) !u32 {
        const filter = self.usageToFilter(usage);
        return memory_mod.findMemoryTypeIndex(self.memory_properties, requirements, filter);
    }

    fn usageToFilter(self: *Allocator, usage: MemoryUsage) memory_mod.MemoryTypeFilter {
        return switch (usage) {
            .gpu_only => .{
                .required_flags = types.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                .excluded_flags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT,
            },
            .cpu_to_gpu => if (self.has_rebar) .{
                .required_flags = types.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT | types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT,
                .preferred_flags = types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            } else .{
                .required_flags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT,
                .preferred_flags = types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            },
            .gpu_to_cpu => .{
                .required_flags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT,
                .preferred_flags = types.VK_MEMORY_PROPERTY_HOST_CACHED_BIT | types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            },
            .cpu_only => .{
                .required_flags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            },
            .gpu_lazily_allocated => .{
                .preferred_flags = types.VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT,
            },
            .custom => .{},
        };
    }

    /// Get memory statistics
    pub fn getStats(self: *Allocator) AllocatorStats {
        var total_pool_bytes: types.VkDeviceSize = 0;
        var total_fragmentation: f32 = 0.0;
        var pool_count: usize = 0;

        for (self.pools.items) |*pool| {
            if (pool.blocks.items.len > 0) {
                total_pool_bytes += pool.getTotalAllocated();
                total_fragmentation += pool.getFragmentation();
                pool_count += 1;
            }
        }

        return .{
            .total_allocations = self.total_allocations,
            .total_allocated_bytes = self.total_allocated_bytes,
            .peak_allocated_bytes = self.peak_allocated_bytes,
            .pool_allocated_bytes = total_pool_bytes,
            .average_fragmentation = if (pool_count > 0) total_fragmentation / @as(f32, @floatFromInt(pool_count)) else 0.0,
        };
    }
};

/// Handle to an allocation
pub const AllocationHandle = struct {
    allocator: *Allocator,
    sub_allocation: SubAllocationHandle = undefined,
    dedicated_memory: types.VkDeviceMemory = undefined,
    is_dedicated: bool,
    size: types.VkDeviceSize,

    pub fn getMemory(self: AllocationHandle) types.VkDeviceMemory {
        if (self.is_dedicated) {
            return self.dedicated_memory;
        }
        return self.sub_allocation.getMemory();
    }

    pub fn getOffset(self: AllocationHandle) types.VkDeviceSize {
        if (self.is_dedicated) {
            return 0;
        }
        return self.sub_allocation.offset;
    }

    pub fn map(self: AllocationHandle) !?[*]u8 {
        if (self.is_dedicated) {
            const device_handle = self.allocator.device.handle orelse return errors.Error.DeviceCreationFailed;
            var mapped: ?*anyopaque = null;
            try errors.ensureSuccess(self.allocator.device.dispatch.map_memory(device_handle, self.dedicated_memory, 0, self.size, 0, &mapped));
            return @ptrCast(mapped);
        }
        return self.sub_allocation.getMappedPtr();
    }

    pub fn free(self: AllocationHandle) void {
        if (self.is_dedicated) {
            const device_handle = self.allocator.device.handle orelse return;
            self.allocator.device.dispatch.free_memory(device_handle, self.dedicated_memory, self.allocator.device.allocation_callbacks);
        } else {
            self.sub_allocation.block.free(self.sub_allocation.offset);
        }

        self.allocator.total_allocated_bytes -= self.size;
    }
};

/// Allocator statistics
pub const AllocatorStats = struct {
    total_allocations: usize,
    total_allocated_bytes: types.VkDeviceSize,
    peak_allocated_bytes: types.VkDeviceSize,
    pool_allocated_bytes: types.VkDeviceSize,
    average_fragmentation: f32,
};
