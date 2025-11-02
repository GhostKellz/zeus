//! Descriptor pool allocator with automatic growth and recycling

const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const descriptor_mod = @import("descriptor.zig");

const log = std.log.scoped(.descriptor_allocator);

/// Descriptor pool sizes for common use cases
pub const DescriptorPoolSizes = struct {
    uniform_buffer: u32 = 0,
    storage_buffer: u32 = 0,
    sampled_image: u32 = 0,
    storage_image: u32 = 0,
    sampler: u32 = 0,
    combined_image_sampler: u32 = 0,
    input_attachment: u32 = 0,

    pub fn toVulkan(self: DescriptorPoolSizes, allocator: std.mem.Allocator) ![]types.VkDescriptorPoolSize {
        var sizes = std.ArrayList(types.VkDescriptorPoolSize).init(allocator);

        if (self.uniform_buffer > 0) try sizes.append(.{ .type = .UNIFORM_BUFFER, .descriptorCount = self.uniform_buffer });
        if (self.storage_buffer > 0) try sizes.append(.{ .type = .STORAGE_BUFFER, .descriptorCount = self.storage_buffer });
        if (self.sampled_image > 0) try sizes.append(.{ .type = .SAMPLED_IMAGE, .descriptorCount = self.sampled_image });
        if (self.storage_image > 0) try sizes.append(.{ .type = .STORAGE_IMAGE, .descriptorCount = self.storage_image });
        if (self.sampler > 0) try sizes.append(.{ .type = .SAMPLER, .descriptorCount = self.sampler });
        if (self.combined_image_sampler > 0) try sizes.append(.{ .type = .COMBINED_IMAGE_SAMPLER, .descriptorCount = self.combined_image_sampler });
        if (self.input_attachment > 0) try sizes.append(.{ .type = .INPUT_ATTACHMENT, .descriptorCount = self.input_attachment });

        return sizes.toOwnedSlice();
    }

    pub fn scale(self: DescriptorPoolSizes, factor: u32) DescriptorPoolSizes {
        return .{
            .uniform_buffer = self.uniform_buffer * factor,
            .storage_buffer = self.storage_buffer * factor,
            .sampled_image = self.sampled_image * factor,
            .storage_image = self.storage_image * factor,
            .sampler = self.sampler * factor,
            .combined_image_sampler = self.combined_image_sampler * factor,
            .input_attachment = self.input_attachment * factor,
        };
    }
};

/// Single descriptor pool with metadata
pub const ManagedDescriptorPool = struct {
    pool: types.VkDescriptorPool,
    max_sets: u32,
    allocated_sets: u32,

    pub fn canAllocate(self: *ManagedDescriptorPool, count: u32) bool {
        return (self.allocated_sets + count) <= self.max_sets;
    }

    pub fn allocate(self: *ManagedDescriptorPool, count: u32) void {
        self.allocated_sets += count;
    }

    pub fn reset(self: *ManagedDescriptorPool) void {
        self.allocated_sets = 0;
    }
};

/// Descriptor pool allocator with automatic growth
pub const DescriptorAllocator = struct {
    allocator: std.mem.Allocator,
    device: *device_mod.Device,
    pool_sizes: DescriptorPoolSizes,
    sets_per_pool: u32,
    pools: std.ArrayList(*ManagedDescriptorPool),
    current_pool_index: usize,

    pub fn init(
        allocator: std.mem.Allocator,
        device: *device_mod.Device,
        pool_sizes: DescriptorPoolSizes,
        sets_per_pool: u32,
    ) !*DescriptorAllocator {
        var self = try allocator.create(DescriptorAllocator);
        self.* = .{
            .allocator = allocator,
            .device = device,
            .pool_sizes = pool_sizes,
            .sets_per_pool = sets_per_pool,
            .pools = std.ArrayList(*ManagedDescriptorPool).init(allocator),
            .current_pool_index = 0,
        };

        // Create initial pool
        _ = try self.createPool();

        return self;
    }

    pub fn deinit(self: *DescriptorAllocator) void {
        for (self.pools.items) |pool| {
            descriptor_mod.destroyDescriptorPool(self.device, pool.pool);
            self.allocator.destroy(pool);
        }
        self.pools.deinit();
        self.allocator.destroy(self);
    }

    fn createPool(self: *DescriptorAllocator) !*ManagedDescriptorPool {
        const sizes = try self.pool_sizes.toVulkan(self.allocator);
        defer self.allocator.free(sizes);

        const pool = try descriptor_mod.createDescriptorPool(self.device, .{
            .max_sets = self.sets_per_pool,
            .pool_sizes = sizes,
            .flags = 0,
        });

        const managed = try self.allocator.create(ManagedDescriptorPool);
        managed.* = .{
            .pool = pool,
            .max_sets = self.sets_per_pool,
            .allocated_sets = 0,
        };

        try self.pools.append(managed);
        log.debug("Created new descriptor pool (total pools: {})", .{self.pools.items.len});

        return managed;
    }

    fn getCurrentPool(self: *DescriptorAllocator) !*ManagedDescriptorPool {
        if (self.current_pool_index >= self.pools.items.len) {
            self.current_pool_index = 0;
        }

        return self.pools.items[self.current_pool_index];
    }

    /// Allocate descriptor sets (auto-grows if needed)
    pub fn allocate(
        self: *DescriptorAllocator,
        layouts: []const types.VkDescriptorSetLayout,
    ) !descriptor_mod.DescriptorSetAllocation {
        const count: u32 = @intCast(layouts.len);

        // Try current pool
        var pool = try self.getCurrentPool();
        if (!pool.canAllocate(count)) {
            // Try other pools
            var found = false;
            for (self.pools.items, 0..) |p, i| {
                if (p.canAllocate(count)) {
                    pool = p;
                    self.current_pool_index = i;
                    found = true;
                    break;
                }
            }

            // Need new pool
            if (!found) {
                pool = try self.createPool();
                self.current_pool_index = self.pools.items.len - 1;
            }
        }

        // Allocate from pool
        const sets = try descriptor_mod.allocateDescriptorSets(self.device, pool.pool, layouts);
        pool.allocate(count);

        return sets;
    }

    /// Reset all pools
    pub fn resetPools(self: *DescriptorAllocator) !void {
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;

        for (self.pools.items) |pool| {
            try errors.ensureSuccess(self.device.dispatch.reset_descriptor_pool(device_handle, pool.pool, 0));
            pool.reset();
        }

        self.current_pool_index = 0;
        log.debug("Reset all descriptor pools", .{});
    }
};

/// Descriptor set layout builder (fluent API)
pub const DescriptorSetLayoutBuilder = struct {
    allocator: std.mem.Allocator,
    bindings: std.ArrayList(types.VkDescriptorSetLayoutBinding),

    pub fn init(allocator: std.mem.Allocator) DescriptorSetLayoutBuilder {
        return .{
            .allocator = allocator,
            .bindings = std.ArrayList(types.VkDescriptorSetLayoutBinding).init(allocator),
        };
    }

    pub fn deinit(self: *DescriptorSetLayoutBuilder) void {
        self.bindings.deinit();
    }

    /// Add uniform buffer binding
    pub fn addUniformBuffer(
        self: *DescriptorSetLayoutBuilder,
        binding: u32,
        stage_flags: types.VkShaderStageFlags,
    ) !*DescriptorSetLayoutBuilder {
        try self.bindings.append(.{
            .binding = binding,
            .descriptorType = .UNIFORM_BUFFER,
            .descriptorCount = 1,
            .stageFlags = stage_flags,
            .pImmutableSamplers = null,
        });
        return self;
    }

    /// Add storage buffer binding
    pub fn addStorageBuffer(
        self: *DescriptorSetLayoutBuilder,
        binding: u32,
        stage_flags: types.VkShaderStageFlags,
    ) !*DescriptorSetLayoutBuilder {
        try self.bindings.append(.{
            .binding = binding,
            .descriptorType = .STORAGE_BUFFER,
            .descriptorCount = 1,
            .stageFlags = stage_flags,
            .pImmutableSamplers = null,
        });
        return self;
    }

    /// Add combined image sampler binding
    pub fn addCombinedImageSampler(
        self: *DescriptorSetLayoutBuilder,
        binding: u32,
        stage_flags: types.VkShaderStageFlags,
        count: u32,
    ) !*DescriptorSetLayoutBuilder {
        try self.bindings.append(.{
            .binding = binding,
            .descriptorType = .COMBINED_IMAGE_SAMPLER,
            .descriptorCount = count,
            .stageFlags = stage_flags,
            .pImmutableSamplers = null,
        });
        return self;
    }

    /// Add storage image binding
    pub fn addStorageImage(
        self: *DescriptorSetLayoutBuilder,
        binding: u32,
        stage_flags: types.VkShaderStageFlags,
    ) !*DescriptorSetLayoutBuilder {
        try self.bindings.append(.{
            .binding = binding,
            .descriptorType = .STORAGE_IMAGE,
            .descriptorCount = 1,
            .stageFlags = stage_flags,
            .pImmutableSamplers = null,
        });
        return self;
    }

    /// Build the descriptor set layout
    pub fn build(self: *DescriptorSetLayoutBuilder, device: *device_mod.Device) !types.VkDescriptorSetLayout {
        return descriptor_mod.createDescriptorSetLayout(device, self.bindings.items);
    }
};
