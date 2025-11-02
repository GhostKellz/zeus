const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const loader = @import("loader.zig");

pub const DescriptorPoolCreateInfo = struct {
    max_sets: u32,
    pool_sizes: []const types.VkDescriptorPoolSize,
    flags: types.VkDescriptorPoolCreateFlags = 0,
};

pub fn createDescriptorPool(device: *device_mod.Device, info: DescriptorPoolCreateInfo) errors.Error!types.VkDescriptorPool {
    const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;

    var create_info = types.VkDescriptorPoolCreateInfo{
        .flags = info.flags,
        .maxSets = info.max_sets,
        .poolSizeCount = @intCast(info.pool_sizes.len),
        .pPoolSizes = if (info.pool_sizes.len == 0) null else @as([*]const types.VkDescriptorPoolSize, @ptrCast(info.pool_sizes.ptr)),
    };

    var pool: types.VkDescriptorPool = undefined;
    try errors.ensureSuccess(device.dispatch.create_descriptor_pool(device_handle, &create_info, device.allocation_callbacks, &pool));
    return pool;
}

pub fn destroyDescriptorPool(device: *device_mod.Device, pool: types.VkDescriptorPool) void {
    const device_handle = device.handle orelse return;
    device.dispatch.destroy_descriptor_pool(device_handle, pool, device.allocation_callbacks);
}

pub fn createDescriptorSetLayout(device: *device_mod.Device, bindings: []const types.VkDescriptorSetLayoutBinding) errors.Error!types.VkDescriptorSetLayout {
    const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;

    var create_info = types.VkDescriptorSetLayoutCreateInfo{
        .bindingCount = @intCast(bindings.len),
        .pBindings = if (bindings.len == 0) null else @as([*]const types.VkDescriptorSetLayoutBinding, @ptrCast(bindings.ptr)),
    };

    var layout: types.VkDescriptorSetLayout = undefined;
    try errors.ensureSuccess(device.dispatch.create_descriptor_set_layout(device_handle, &create_info, device.allocation_callbacks, &layout));
    return layout;
}

pub fn destroyDescriptorSetLayout(device: *device_mod.Device, layout: types.VkDescriptorSetLayout) void {
    const device_handle = device.handle orelse return;
    device.dispatch.destroy_descriptor_set_layout(device_handle, layout, device.allocation_callbacks);
}

pub fn freeDescriptorSets(device: *device_mod.Device, pool: types.VkDescriptorPool, sets: []const types.VkDescriptorSet) errors.Error!void {
    if (sets.len == 0) return;
    const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;
    try errors.ensureSuccess(device.dispatch.free_descriptor_sets(device_handle, pool, @intCast(sets.len), @as([*]const types.VkDescriptorSet, @ptrCast(sets.ptr))));
}

pub const DescriptorSetAllocation = struct {
    allocator: std.mem.Allocator,
    sets: []types.VkDescriptorSet,

    pub fn len(self: *const DescriptorSetAllocation) usize {
        return self.sets.len;
    }

    pub fn slice(self: *const DescriptorSetAllocation) []const types.VkDescriptorSet {
        return self.sets;
    }

    pub fn free(self: *DescriptorSetAllocation, device: *device_mod.Device, pool: types.VkDescriptorPool) errors.Error!void {
        if (self.sets.len == 0) return;
        try freeDescriptorSets(device, pool, self.sets);
        self.allocator.free(self.sets);
        self.sets = &.{};
    }

    pub fn deinit(self: *DescriptorSetAllocation) void {
        if (self.sets.len == 0) return;
        self.allocator.free(self.sets);
        self.sets = &.{};
    }
};

pub fn allocateDescriptorSets(device: *device_mod.Device, pool: types.VkDescriptorPool, layouts: []const types.VkDescriptorSetLayout) errors.Error!DescriptorSetAllocation {
    const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;
    const allocator = device.allocator;

    const sets = try allocator.alloc(types.VkDescriptorSet, layouts.len);
    errdefer allocator.free(sets);

    var alloc_info = types.VkDescriptorSetAllocateInfo{
        .descriptorPool = pool,
        .descriptorSetCount = @intCast(layouts.len),
        .pSetLayouts = if (layouts.len == 0) null else @as([*]const types.VkDescriptorSetLayout, @ptrCast(layouts.ptr)),
    };

    try errors.ensureSuccess(device.dispatch.allocate_descriptor_sets(device_handle, &alloc_info, sets.ptr));

    return DescriptorSetAllocation{ .allocator = allocator, .sets = sets };
}

pub fn updateDescriptorSets(device: *device_mod.Device, writes: []const types.VkWriteDescriptorSet, copies: []const types.VkCopyDescriptorSet) void {
    const device_handle = device.handle orelse return;
    const write_ptr = if (writes.len == 0) null else @as([*]const types.VkWriteDescriptorSet, @ptrCast(writes.ptr));
    const copy_ptr = if (copies.len == 0) null else @as([*]const types.VkCopyDescriptorSet, @ptrCast(copies.ptr));
    device.dispatch.update_descriptor_sets(device_handle, @intCast(writes.len), write_ptr, @intCast(copies.len), copy_ptr);
}

pub const CacheStats = struct {
    hits: usize,
    misses: usize,
    hit_rate: f32,
};

pub const DescriptorCache = struct {
    allocator: std.mem.Allocator,
    sets: std.AutoHashMap(u64, types.VkDescriptorSet),
    cache_hits: usize = 0,
    cache_misses: usize = 0,

    pub fn init(allocator: std.mem.Allocator) DescriptorCache {
        return .{
            .allocator = allocator,
            .sets = std.AutoHashMap(u64, types.VkDescriptorSet).init(allocator),
        };
    }

    pub fn deinit(self: *DescriptorCache) void {
        self.sets.deinit();
        self.cache_hits = 0;
        self.cache_misses = 0;
    }

    pub fn clear(self: *DescriptorCache) void {
        self.sets.clearRetainingCapacity();
        self.cache_hits = 0;
        self.cache_misses = 0;
    }

    fn hashDescriptorState(
        layout: types.VkDescriptorSetLayout,
        buffer: ?types.VkBuffer,
        buffer_range: types.VkDeviceSize,
        image_view: ?types.VkImageView,
        sampler: ?types.VkSampler,
        image_layout: types.VkImageLayout,
    ) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&layout));
        hasher.update(std.mem.asBytes(&buffer_range));
        if (buffer) |buf| hasher.update(std.mem.asBytes(&buf));
        if (image_view) |view| hasher.update(std.mem.asBytes(&view));
        if (sampler) |samp| hasher.update(std.mem.asBytes(&samp));
        hasher.update(std.mem.asBytes(&image_layout));
        return hasher.final();
    }

    pub fn getOrCreate(
        self: *DescriptorCache,
        device: *device_mod.Device,
        pool: types.VkDescriptorPool,
        layout: types.VkDescriptorSetLayout,
        buffer: ?types.VkBuffer,
        buffer_range: types.VkDeviceSize,
        image_view: ?types.VkImageView,
        sampler: ?types.VkSampler,
        image_layout: types.VkImageLayout,
    ) errors.Error!types.VkDescriptorSet {
        const key = hashDescriptorState(layout, buffer, buffer_range, image_view, sampler, image_layout);
        if (self.sets.get(key)) |cached| {
            self.cache_hits += 1;
            return cached;
        }

        self.cache_misses += 1;

        var allocation = try allocateDescriptorSets(device, pool, &.{layout});
        defer allocation.deinit();
        const descriptor_set = allocation.sets[0];

        var writes: [2]types.VkWriteDescriptorSet = undefined;
        var write_count: usize = 0;
        const buffer_binding: u32 = 0;
        const sampler_binding: u32 = if (buffer != null) 1 else 0;

        var buffer_info: types.VkDescriptorBufferInfo = undefined;
        if (buffer) |buf| {
            buffer_info = types.VkDescriptorBufferInfo{
                .buffer = buf,
                .offset = 0,
                .range = buffer_range,
            };
            writes[write_count] = types.VkWriteDescriptorSet{
                .dstSet = descriptor_set,
                .dstBinding = buffer_binding,
                .descriptorType = .UNIFORM_BUFFER,
                .descriptorCount = 1,
                .pBufferInfo = &buffer_info,
            };
            write_count += 1;
        }

        var image_info: types.VkDescriptorImageInfo = undefined;
        if ((image_view != null) != (sampler != null)) {
            return errors.Error.FeatureNotPresent;
        }

        if (image_view != null and sampler != null) {
            image_info = types.VkDescriptorImageInfo{
                .sampler = sampler orelse @as(types.VkSampler, @ptrFromInt(@as(usize, 0))),
                .imageView = image_view orelse @as(types.VkImageView, @ptrFromInt(@as(usize, 0))),
                .imageLayout = image_layout,
            };
            writes[write_count] = types.VkWriteDescriptorSet{
                .dstSet = descriptor_set,
                .dstBinding = sampler_binding,
                .descriptorType = .COMBINED_IMAGE_SAMPLER,
                .descriptorCount = 1,
                .pImageInfo = &image_info,
            };
            write_count += 1;
        }

        if (write_count > 0) {
            updateDescriptorSets(device, writes[0..write_count], &.{});
        }

        try self.sets.put(key, descriptor_set);
        return descriptor_set;
    }

    pub fn getStats(self: *DescriptorCache) CacheStats {
        const total = self.cache_hits + self.cache_misses;
        const rate = if (total == 0)
            0.0
        else
            @as(f32, @floatFromInt(self.cache_hits)) / @as(f32, @floatFromInt(total));
        return CacheStats{
            .hits = self.cache_hits,
            .misses = self.cache_misses,
            .hit_rate = rate,
        };
    }
};

// Tests ---------------------------------------------------------------------

const fake_pool = @as(types.VkDescriptorPool, @ptrFromInt(@as(usize, 0x1111)));
const fake_layout = @as(types.VkDescriptorSetLayout, @ptrFromInt(@as(usize, 0x2222)));
const fake_set_handles = [_]types.VkDescriptorSet{
    @as(types.VkDescriptorSet, @ptrFromInt(@as(usize, 0xAAAA))),
    @as(types.VkDescriptorSet, @ptrFromInt(@as(usize, 0xBBBB))),
};

const Capture = struct {
    pub var pool_info: ?types.VkDescriptorPoolCreateInfo = null;
    pub var layout_info: ?types.VkDescriptorSetLayoutCreateInfo = null;
    pub var allocate_info: ?types.VkDescriptorSetAllocateInfo = null;
    pub var last_writes: ?[]const types.VkWriteDescriptorSet = null;
    pub var last_copies: ?[]const types.VkCopyDescriptorSet = null;
    pub var destroy_pool_calls: usize = 0;
    pub var destroy_layout_calls: usize = 0;
    pub var free_calls: usize = 0;
    pub var update_calls: usize = 0;

    pub fn reset() void {
        pool_info = null;
        layout_info = null;
        allocate_info = null;
        last_writes = null;
        last_copies = null;
        destroy_pool_calls = 0;
        destroy_layout_calls = 0;
        free_calls = 0;
        update_calls = 0;
    }

    pub fn stubCreatePool(_: types.VkDevice, info: *const types.VkDescriptorPoolCreateInfo, _: ?*const types.VkAllocationCallbacks, pool: *types.VkDescriptorPool) callconv(.c) types.VkResult {
        pool_info = info.*;
        pool.* = fake_pool;
        return .SUCCESS;
    }

    pub fn stubDestroyPool(_: types.VkDevice, _: types.VkDescriptorPool, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {
        destroy_pool_calls += 1;
    }

    pub fn stubCreateLayout(_: types.VkDevice, info: *const types.VkDescriptorSetLayoutCreateInfo, _: ?*const types.VkAllocationCallbacks, layout: *types.VkDescriptorSetLayout) callconv(.c) types.VkResult {
        layout_info = info.*;
        layout.* = fake_layout;
        return .SUCCESS;
    }

    pub fn stubDestroyLayout(_: types.VkDevice, _: types.VkDescriptorSetLayout, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {
        destroy_layout_calls += 1;
    }

    pub fn stubAllocate(_: types.VkDevice, info: *const types.VkDescriptorSetAllocateInfo, sets: [*]types.VkDescriptorSet) callconv(.c) types.VkResult {
        allocate_info = info.*;
        for (fake_set_handles, 0..) |handle, idx| {
            if (idx >= info.descriptorSetCount) break;
            sets[idx] = handle;
        }
        return .SUCCESS;
    }

    pub fn stubFree(_: types.VkDevice, _: types.VkDescriptorPool, count: u32, _: [*]const types.VkDescriptorSet) callconv(.c) types.VkResult {
        free_calls += 1;
        std.debug.assert(count > 0);
        return .SUCCESS;
    }

    pub fn stubUpdate(_: types.VkDevice, write_count: u32, writes: ?[*]const types.VkWriteDescriptorSet, copy_count: u32, copies: ?[*]const types.VkCopyDescriptorSet) callconv(.c) void {
        update_calls += 1;
        if (write_count > 0 and writes) |ptr| {
            last_writes = ptr[0..write_count];
        } else {
            last_writes = &.{};
        }
        if (copy_count > 0 and copies) |ptr| {
            last_copies = ptr[0..copy_count];
        } else {
            last_copies = &.{};
        }
    }
};

fn makeDevice() device_mod.Device {
    var device = device_mod.Device{
        .allocator = std.testing.allocator,
        .loader = undefined,
        .dispatch = undefined,
        .handle = @as(types.VkDevice, @ptrFromInt(@as(usize, 0xDEADBEEF))),
        .allocation_callbacks = null,
    };

    device.dispatch.create_descriptor_pool = Capture.stubCreatePool;
    device.dispatch.destroy_descriptor_pool = Capture.stubDestroyPool;
    device.dispatch.create_descriptor_set_layout = Capture.stubCreateLayout;
    device.dispatch.destroy_descriptor_set_layout = Capture.stubDestroyLayout;
    device.dispatch.allocate_descriptor_sets = Capture.stubAllocate;
    device.dispatch.free_descriptor_sets = Capture.stubFree;
    device.dispatch.update_descriptor_sets = Capture.stubUpdate;

    return device;
}

test "createDescriptorPool records parameters" {
    Capture.reset();
    var device = makeDevice();
    const pool = try createDescriptorPool(&device, .{
        .max_sets = 8,
        .pool_sizes = &.{
            types.VkDescriptorPoolSize{ .descriptorType = .UNIFORM_BUFFER, .descriptorCount = 8 },
            types.VkDescriptorPoolSize{ .descriptorType = .COMBINED_IMAGE_SAMPLER, .descriptorCount = 8 },
        },
        .flags = types.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
    });
    try std.testing.expectEqual(fake_pool, pool);
    const info = Capture.pool_info orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(u32, 8), info.maxSets);
    try std.testing.expectEqual(types.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT, info.flags);
    try std.testing.expectEqual(@as(u32, 2), info.poolSizeCount);
}

test "createDescriptorSetLayout stores handle" {
    Capture.reset();
    var device = makeDevice();
    const bindings = [_]types.VkDescriptorSetLayoutBinding{
        .{ .binding = 0, .descriptorType = .UNIFORM_BUFFER, .descriptorCount = 1, .stageFlags = types.VK_SHADER_STAGE_VERTEX_BIT },
        .{ .binding = 1, .descriptorType = .COMBINED_IMAGE_SAMPLER, .descriptorCount = 1, .stageFlags = types.VK_SHADER_STAGE_FRAGMENT_BIT },
    };
    const layout = try createDescriptorSetLayout(&device, bindings[0..]);
    try std.testing.expectEqual(fake_layout, layout);
    const info = Capture.layout_info orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(u32, 2), info.bindingCount);
    try std.testing.expect(info.pBindings != null);
}

test "allocateDescriptorSets captures layouts and frees" {
    Capture.reset();
    var device = makeDevice();
    const pool = fake_pool;
    const layouts = [_]types.VkDescriptorSetLayout{ fake_layout, fake_layout };

    var allocation = try allocateDescriptorSets(&device, pool, layouts[0..]);
    defer allocation.deinit();
    try std.testing.expectEqual(@as(usize, 2), allocation.len());
    try std.testing.expectEqual(fake_set_handles[0], allocation.sets[0]);
    try std.testing.expectEqual(fake_set_handles[1], allocation.sets[1]);
    const info = Capture.allocate_info orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(u32, 2), info.descriptorSetCount);

    try allocation.free(&device, pool);
    try std.testing.expectEqual(@as(usize, 1), Capture.free_calls);
}

test "updateDescriptorSets forwards counts" {
    Capture.reset();
    var device = makeDevice();

    var buffer_info = types.VkDescriptorBufferInfo{
        .buffer = @as(types.VkBuffer, @ptrFromInt(@as(usize, 0x3333))),
        .offset = 0,
        .range = 64,
    };
    var image_info = types.VkDescriptorImageInfo{
        .sampler = @as(types.VkSampler, @ptrFromInt(@as(usize, 0x4444))),
        .imageView = @as(types.VkImageView, @ptrFromInt(@as(usize, 0x5555))),
        .imageLayout = .SHADER_READ_ONLY_OPTIMAL,
    };

    const writes = [_]types.VkWriteDescriptorSet{
        .{
            .dstBinding = 0,
            .descriptorType = .UNIFORM_BUFFER,
            .descriptorCount = 1,
            .pBufferInfo = &buffer_info,
        },
        .{
            .dstBinding = 1,
            .descriptorType = .COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
            .pImageInfo = &image_info,
        },
    };

    updateDescriptorSets(&device, writes[0..], &.{});
    try std.testing.expectEqual(@as(usize, 1), Capture.update_calls);
    const captured_writes = Capture.last_writes orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 2), captured_writes.len);
}

test "DescriptorCache caches descriptor sets and tracks hits" {
    Capture.reset();
    var device = makeDevice();

    var cache = DescriptorCache.init(std.testing.allocator);
    defer cache.deinit();

    const pool = fake_pool;
    const layout = fake_layout;
    const buffer = @as(types.VkBuffer, @ptrFromInt(@as(usize, 0x1234)));
    const image_view = @as(types.VkImageView, @ptrFromInt(@as(usize, 0x5678)));
    const sampler = @as(types.VkSampler, @ptrFromInt(@as(usize, 0x9ABC)));

    const first = try cache.getOrCreate(&device, pool, layout, buffer, 128, image_view, sampler, types.VkImageLayout.SHADER_READ_ONLY_OPTIMAL);
    const second = try cache.getOrCreate(&device, pool, layout, buffer, 128, image_view, sampler, types.VkImageLayout.SHADER_READ_ONLY_OPTIMAL);

    try std.testing.expectEqual(first, second);
    try std.testing.expectEqual(@as(usize, 1), Capture.update_calls);

    const stats = cache.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.misses);
    try std.testing.expectEqual(@as(usize, 1), stats.hits);
    try std.testing.expectApproxEqAbs(0.5, stats.hit_rate, 0.01);
}

test "DescriptorCache clear resets state" {
    Capture.reset();
    var device = makeDevice();

    var cache = DescriptorCache.init(std.testing.allocator);
    defer cache.deinit();

    const pool = fake_pool;
    const layout = fake_layout;
    const buffer = @as(types.VkBuffer, @ptrFromInt(@as(usize, 0x4242)));
    const image_view = @as(types.VkImageView, @ptrFromInt(@as(usize, 0x4343)));
    const sampler = @as(types.VkSampler, @ptrFromInt(@as(usize, 0x4444)));

    _ = try cache.getOrCreate(&device, pool, layout, buffer, 256, image_view, sampler, types.VkImageLayout.SHADER_READ_ONLY_OPTIMAL);
    cache.clear();

    const stats = cache.getStats();
    try std.testing.expectEqual(@as(usize, 0), stats.hits);
    try std.testing.expectEqual(@as(usize, 0), stats.misses);

    // After clear we should reallocate and update descriptors again.
    Capture.reset();
    _ = try cache.getOrCreate(&device, pool, layout, buffer, 256, image_view, sampler, types.VkImageLayout.SHADER_READ_ONLY_OPTIMAL);
    try std.testing.expectEqual(@as(usize, 1), Capture.update_calls);
}

test "DescriptorCache hit rate converges after warmup" {
    Capture.reset();
    var device = makeDevice();

    var cache = DescriptorCache.init(std.testing.allocator);
    defer cache.deinit();

    const pool = fake_pool;
    const layout = fake_layout;
    const buffer = @as(types.VkBuffer, @ptrFromInt(@as(usize, 0x5151)));
    const image_view = @as(types.VkImageView, @ptrFromInt(@as(usize, 0x6161)));
    const sampler = @as(types.VkSampler, @ptrFromInt(@as(usize, 0x7171)));

    const iterations: usize = 100;
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        _ = try cache.getOrCreate(&device, pool, layout, buffer, 128, image_view, sampler, types.VkImageLayout.SHADER_READ_ONLY_OPTIMAL);
    }

    const stats = cache.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.misses);
    try std.testing.expectEqual(@as(usize, iterations - 1), stats.hits);
    try std.testing.expectApproxEqAbs(@as(f32, 0.99), stats.hit_rate, 0.01);
    try std.testing.expectEqual(@as(usize, 1), Capture.update_calls);
}
