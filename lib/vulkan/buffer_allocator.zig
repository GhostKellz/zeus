//! Buffer allocator with automatic memory binding and ReBAR optimization

const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const buffer_mod = @import("buffer.zig");
const allocator_mod = @import("allocator.zig");

const log = std.log.scoped(.buffer_allocator);

/// Buffer allocation options
pub const BufferAllocOptions = struct {
    size: types.VkDeviceSize,
    usage: types.VkBufferUsageFlags,
    memory_usage: allocator_mod.MemoryUsage,
    flags: allocator_mod.AllocationFlags = .{},
    name: ?[:0]const u8 = null,
};

/// Managed buffer with automatic memory management
pub const AllocatedBuffer = struct {
    device: *device_mod.Device,
    allocator: *allocator_mod.Allocator,
    buffer: types.VkBuffer,
    allocation: allocator_mod.AllocationHandle,
    size: types.VkDeviceSize,
    usage: types.VkBufferUsageFlags,
    memory_usage: allocator_mod.MemoryUsage,

    pub fn deinit(self: *AllocatedBuffer) void {
        buffer_mod.destroyBuffer(self.device, self.buffer);
        self.allocation.free();
    }

    /// Map buffer memory for CPU access
    pub fn map(self: *AllocatedBuffer) !?[*]u8 {
        return self.allocation.map();
    }

    /// Unmap buffer memory
    pub fn unmap(self: *AllocatedBuffer) void {
        if (self.allocation.is_dedicated) {
            const device_handle = self.device.handle orelse return;
            self.device.dispatch.unmap_memory(device_handle, self.allocation.dedicated_memory);
        }
    }

    /// Write data to buffer (auto-maps if needed)
    pub fn write(self: *AllocatedBuffer, data: []const u8, offset: types.VkDeviceSize) !void {
        if (offset + data.len > self.size) {
            return errors.Error.OutOfMemory;
        }

        const mapped = try self.map() orelse return errors.Error.FeatureNotPresent;
        @memcpy(mapped[@intCast(offset)..][0..data.len], data);

        // Flush if not coherent
        if (self.memory_usage != .cpu_to_gpu and self.memory_usage != .cpu_only) {
            const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;
            const range = types.VkMappedMemoryRange{
                .memory = self.allocation.getMemory(),
                .offset = self.allocation.getOffset() + offset,
                .size = @intCast(data.len),
            };
            try errors.ensureSuccess(self.device.dispatch.flush_mapped_memory_ranges(device_handle, 1, @ptrCast(&range)));
        }
    }

    /// Read data from buffer (auto-maps if needed)
    pub fn read(self: *AllocatedBuffer, dest: []u8, offset: types.VkDeviceSize) !void {
        if (offset + dest.len > self.size) {
            return errors.Error.OutOfMemory;
        }

        const mapped = try self.map() orelse return errors.Error.FeatureNotPresent;

        // Invalidate if not coherent
        if (self.memory_usage == .gpu_to_cpu) {
            const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;
            const range = types.VkMappedMemoryRange{
                .memory = self.allocation.getMemory(),
                .offset = self.allocation.getOffset() + offset,
                .size = @intCast(dest.len),
            };
            try errors.ensureSuccess(self.device.dispatch.invalidate_mapped_memory_ranges(device_handle, 1, @ptrCast(&range)));
        }

        @memcpy(dest, mapped[@intCast(offset)..][0..dest.len]);
    }

    /// Get VkDeviceMemory for binding
    pub fn getMemory(self: *AllocatedBuffer) types.VkDeviceMemory {
        return self.allocation.getMemory();
    }

    /// Get memory offset for binding
    pub fn getOffset(self: *AllocatedBuffer) types.VkDeviceSize {
        return self.allocation.getOffset();
    }
};

/// Buffer allocator managing staging and device-local buffers
pub const BufferAllocator = struct {
    device: *device_mod.Device,
    allocator: *allocator_mod.Allocator,

    pub fn init(device: *device_mod.Device, allocator: *allocator_mod.Allocator) BufferAllocator {
        return .{
            .device = device,
            .allocator = allocator,
        };
    }

    /// Create buffer with automatic memory allocation and binding
    pub fn createBuffer(self: *BufferAllocator, options: BufferAllocOptions) !AllocatedBuffer {
        // Create buffer
        const buffer = try buffer_mod.createBuffer(self.device, options.size, options.usage);
        errdefer buffer_mod.destroyBuffer(self.device, buffer);

        // Get memory requirements
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;
        var requirements: types.VkMemoryRequirements = undefined;
        self.device.dispatch.get_buffer_memory_requirements(device_handle, buffer, &requirements);

        // Allocate memory
        const allocation = try self.allocator.allocateMemory(requirements, options.memory_usage, options.flags);
        errdefer allocation.free();

        // Bind buffer to memory
        try errors.ensureSuccess(self.device.dispatch.bind_buffer_memory(
            device_handle,
            buffer,
            allocation.getMemory(),
            allocation.getOffset(),
        ));

        log.debug("Created buffer: size={} bytes, usage=0x{x}, memory_usage={s}", .{
            options.size,
            options.usage,
            @tagName(options.memory_usage),
        });

        return AllocatedBuffer{
            .device = self.device,
            .allocator = self.allocator,
            .buffer = buffer,
            .allocation = allocation,
            .size = options.size,
            .usage = options.usage,
            .memory_usage = options.memory_usage,
        };
    }

    /// Create staging buffer optimized for CPU-to-GPU transfers
    pub fn createStagingBuffer(self: *BufferAllocator, size: types.VkDeviceSize) !AllocatedBuffer {
        return self.createBuffer(.{
            .size = size,
            .usage = types.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            .memory_usage = .cpu_to_gpu,
            .flags = .{ .mapped = true },
        });
    }

    /// Create device-local buffer (GPU only, fastest)
    pub fn createDeviceBuffer(self: *BufferAllocator, size: types.VkDeviceSize, usage: types.VkBufferUsageFlags) !AllocatedBuffer {
        return self.createBuffer(.{
            .size = size,
            .usage = usage | types.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
            .memory_usage = .gpu_only,
        });
    }

    /// Create uniform buffer (frequently updated from CPU)
    pub fn createUniformBuffer(self: *BufferAllocator, size: types.VkDeviceSize) !AllocatedBuffer {
        return self.createBuffer(.{
            .size = size,
            .usage = types.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            .memory_usage = .cpu_to_gpu,
            .flags = .{ .mapped = true },
        });
    }

    /// Create vertex buffer (device-local, with transfer dst)
    pub fn createVertexBuffer(self: *BufferAllocator, size: types.VkDeviceSize) !AllocatedBuffer {
        return self.createDeviceBuffer(size, types.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
    }

    /// Create index buffer (device-local, with transfer dst)
    pub fn createIndexBuffer(self: *BufferAllocator, size: types.VkDeviceSize) !AllocatedBuffer {
        return self.createDeviceBuffer(size, types.VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
    }

    /// Create storage buffer (compute shader read/write)
    pub fn createStorageBuffer(self: *BufferAllocator, size: types.VkDeviceSize) !AllocatedBuffer {
        return self.createDeviceBuffer(size, types.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
    }

    /// Create readback buffer for GPU-to-CPU transfers
    pub fn createReadbackBuffer(self: *BufferAllocator, size: types.VkDeviceSize) !AllocatedBuffer {
        return self.createBuffer(.{
            .size = size,
            .usage = types.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
            .memory_usage = .gpu_to_cpu,
            .flags = .{ .mapped = true },
        });
    }
};
