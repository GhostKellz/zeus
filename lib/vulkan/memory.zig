const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const loader = @import("loader.zig");
const physical_device = @import("physical_device.zig");

const log = std.log.scoped(.memory);

pub const MemoryTypeFilter = struct {
    required_flags: types.VkMemoryPropertyFlags = 0,
    preferred_flags: types.VkMemoryPropertyFlags = 0,
    excluded_flags: types.VkMemoryPropertyFlags = 0,
};

pub const Allocation = struct {
    device: *device_mod.Device,
    memory: ?types.VkDeviceMemory,
    size: types.VkDeviceSize,
    type_index: u32,

    _mapped_ptr: ?*anyopaque = null,

    pub fn isMapped(self: Allocation) bool {
        return self._mapped_ptr != null;
    }

    pub fn destroy(self: *Allocation) void {
        if (self._mapped_ptr != null) {
            self.unmap();
        }

        if (self.memory) |mem| {
            const device_handle = self.device.handle orelse return;
            self.device.dispatch.free_memory(device_handle, mem, self.device.allocation_callbacks);
            self.memory = null;
        }
    }

    pub fn map(self: *Allocation, offset: types.VkDeviceSize, size: types.VkDeviceSize) errors.Error![*]u8 {
        if (self._mapped_ptr) |ptr| {
            const base = @as([*]u8, @ptrCast(ptr));
            const off: usize = @intCast(offset);
            return base + off;
        }

        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;
        var mapped: ?*anyopaque = null;
        try errors.ensureSuccess(self.device.dispatch.map_memory(device_handle, self.memory.?, offset, size, 0, &mapped));
        self._mapped_ptr = mapped;
        const base = @as([*]u8, @ptrCast(mapped.?));
        const off: usize = @intCast(offset);
        return base + off;
    }

    pub fn unmap(self: *Allocation) void {
        if (self._mapped_ptr != null) {
            const device_handle = self.device.handle orelse return;
            self.device.dispatch.unmap_memory(device_handle, self.memory.?);
            self._mapped_ptr = null;
        }
    }

    pub fn flush(self: *Allocation, ranges: []const types.VkMappedMemoryRange) errors.Error!void {
        if (ranges.len == 0) return;
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;
        try errors.ensureSuccess(self.device.dispatch.flush_mapped_memory_ranges(device_handle, @intCast(ranges.len), ranges.ptr));
    }

    pub fn invalidate(self: *Allocation, ranges: []const types.VkMappedMemoryRange) errors.Error!void {
        if (ranges.len == 0) return;
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;
        try errors.ensureSuccess(self.device.dispatch.invalidate_mapped_memory_ranges(device_handle, @intCast(ranges.len), ranges.ptr));
    }
};

pub fn findMemoryTypeIndex(props: types.VkPhysicalDeviceMemoryProperties, requirements: types.VkMemoryRequirements, filter: MemoryTypeFilter) !u32 {
    var best_index: ?u32 = null;
    var best_score: u32 = 0;
    const valid_bits = requirements.memoryTypeBits;

    for (props.memoryTypes[0..props.memoryTypeCount], 0..) |mem_type, index| {
        if ((valid_bits & (@as(u32, 1) << @intCast(index))) == 0) continue;
        if ((mem_type.propertyFlags & filter.excluded_flags) != 0) continue;
        if ((mem_type.propertyFlags & filter.required_flags) != filter.required_flags) continue;

        const preferred_mask = filter.preferred_flags & mem_type.propertyFlags;
        const score = @popCount(preferred_mask);
        if (best_index == null or score > best_score) {
            best_index = @intCast(index);
            best_score = score;
        }
    }

    if (best_index) |idx| return idx;
    return errors.Error.FeatureNotPresent;
}

pub fn allocate(device: *device_mod.Device, requirements: types.VkMemoryRequirements, type_index: u32) errors.Error!Allocation {
    const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;
    var info = types.VkMemoryAllocateInfo{
        .allocationSize = requirements.size,
        .memoryTypeIndex = type_index,
    };

    var memory: types.VkDeviceMemory = undefined;
    try errors.ensureSuccess(device.dispatch.allocate_memory(device_handle, &info, device.allocation_callbacks, &memory));

    return Allocation{
        .device = device,
        .memory = memory,
        .size = requirements.size,
        .type_index = type_index,
    };
}

pub fn allocateWithSize(device: *device_mod.Device, size: types.VkDeviceSize, type_index: u32) errors.Error!Allocation {
    const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;
    var info = types.VkMemoryAllocateInfo{
        .allocationSize = size,
        .memoryTypeIndex = type_index,
    };
    var memory: types.VkDeviceMemory = undefined;
    try errors.ensureSuccess(device.dispatch.allocate_memory(device_handle, &info, device.allocation_callbacks, &memory));
    return Allocation{
        .device = device,
        .memory = memory,
        .size = size,
        .type_index = type_index,
    };
}

pub fn logReBARUsage(memory_props: types.VkPhysicalDeviceMemoryProperties, type_index: u32, size: types.VkDeviceSize) void {
    if (type_index >= memory_props.memoryTypeCount) return;

    const flags = memory_props.memoryTypes[type_index].propertyFlags;
    const rebar_available = physical_device.detectReBAR(memory_props);
    const host_visible_device_local = types.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT | types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT;
    const using_rebar_path = (flags & host_visible_device_local) == host_visible_device_local;

    if (using_rebar_path) {
        if (rebar_available) {
            log.debug("Using ReBAR-optimized memory (DEVICE_LOCAL | HOST_VISIBLE) size={d}", .{size});
        } else {
            log.debug("Host-visible device-local memory selected without detected ReBAR; size={d}", .{size});
        }
    } else if (rebar_available) {
        log.debug("ReBAR available but falling back to staging-friendly memory flags=0x{x}", .{flags});
    } else {
        log.debug("ReBAR unavailable; using staging-friendly memory flags=0x{x}", .{flags});
    }
}

fn makeMemoryProperties() types.VkPhysicalDeviceMemoryProperties {
    var props: types.VkPhysicalDeviceMemoryProperties = std.mem.zeroes(types.VkPhysicalDeviceMemoryProperties);
    props.memoryTypeCount = 3;
    props.memoryTypes[0] = .{ .propertyFlags = types.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, .heapIndex = 0 };
    props.memoryTypes[1] = .{ .propertyFlags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, .heapIndex = 0 };
    props.memoryTypes[2] = .{ .propertyFlags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | types.VK_MEMORY_PROPERTY_HOST_CACHED_BIT, .heapIndex = 1 };
    props.memoryHeapCount = 2;
    props.memoryHeaps[0] = .{ .size = 1024 * 1024 * 1024, .flags = types.VK_MEMORY_HEAP_DEVICE_LOCAL_BIT };
    props.memoryHeaps[1] = .{ .size = 256 * 1024 * 1024, .flags = 0 };
    return props;
}

fn fakeRequirements(size: types.VkDeviceSize, bits: u32) types.VkMemoryRequirements {
    return types.VkMemoryRequirements{
        .size = size,
        .alignment = 256,
        .memoryTypeBits = bits,
    };
}

fn makeFakeDevice() device_mod.Device {
    var device = device_mod.Device{
        .allocator = std.testing.allocator,
        .loader = undefined,
        .dispatch = std.mem.zeroes(loader.DeviceDispatch),
        .handle = @as(types.VkDevice, @ptrFromInt(@as(usize, 0x100))),
        .allocation_callbacks = null,
    };
    device.dispatch.allocate_memory = stubAllocateMemory;
    device.dispatch.free_memory = stubFreeMemory;
    device.dispatch.map_memory = stubMapMemory;
    device.dispatch.unmap_memory = stubUnmapMemory;
    device.dispatch.flush_mapped_memory_ranges = stubFlush;
    device.dispatch.invalidate_mapped_memory_ranges = stubInvalidate;
    return device;
}

var last_alloc_info: ?types.VkMemoryAllocateInfo = null;
var freed_memory: ?types.VkDeviceMemory = null;
var map_calls: usize = 0;
var unmap_calls: usize = 0;
var flush_calls: usize = 0;
var invalidate_calls: usize = 0;

fn resetCapture() void {
    last_alloc_info = null;
    freed_memory = null;
    map_calls = 0;
    unmap_calls = 0;
    flush_calls = 0;
    invalidate_calls = 0;
}

fn stubAllocateMemory(_: types.VkDevice, info: *const types.VkMemoryAllocateInfo, _: ?*const types.VkAllocationCallbacks, memory: *types.VkDeviceMemory) callconv(.C) types.VkResult {
    last_alloc_info = info.*;
    memory.* = @as(types.VkDeviceMemory, @ptrFromInt(@as(usize, 0x500)));
    return .SUCCESS;
}

fn stubFreeMemory(_: types.VkDevice, memory: types.VkDeviceMemory, _: ?*const types.VkAllocationCallbacks) callconv(.C) void {
    freed_memory = memory;
}

fn stubMapMemory(_: types.VkDevice, _: types.VkDeviceMemory, _: types.VkDeviceSize, _: types.VkDeviceSize, _: types.VkMemoryMapFlags, data: *?*anyopaque) callconv(.C) types.VkResult {
    map_calls += 1;
    data.* = @as(*anyopaque, @ptrFromInt(@as(usize, 0xA00)));
    return .SUCCESS;
}

fn stubUnmapMemory(_: types.VkDevice, _: types.VkDeviceMemory) callconv(.C) void {
    unmap_calls += 1;
}

fn stubFlush(_: types.VkDevice, _: u32, _: [*]const types.VkMappedMemoryRange) callconv(.C) types.VkResult {
    flush_calls += 1;
    return .SUCCESS;
}

fn stubInvalidate(_: types.VkDevice, _: u32, _: [*]const types.VkMappedMemoryRange) callconv(.C) types.VkResult {
    invalidate_calls += 1;
    return .SUCCESS;
}

test "findMemoryTypeIndex respects required and preferred flags" {
    const props = makeMemoryProperties();
    const reqs = fakeRequirements(4096, 0b111);
    const index = try findMemoryTypeIndex(props, reqs, .{
        .required_flags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT,
        .preferred_flags = types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
    });
    try std.testing.expectEqual(@as(u32, 1), index);
}

test "findMemoryTypeIndex fails when not found" {
    const props = makeMemoryProperties();
    const reqs = fakeRequirements(4096, 0b001);
    const result = findMemoryTypeIndex(props, reqs, .{
        .required_flags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT,
    });
    try std.testing.expectError(errors.Error.FeatureNotPresent, result);
}

test "allocate records size and type" {
    resetCapture();
    var device = makeFakeDevice();
    const reqs = fakeRequirements(8192, 0b010);
    var allocation = try allocate(&device, reqs, 1);
    try std.testing.expectEqual(@as(types.VkDeviceSize, 8192), allocation.size);
    try std.testing.expectEqual(@as(u32, 1), allocation.type_index);
    const info = last_alloc_info orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(reqs.size, info.allocationSize);
    allocation.destroy();
    try std.testing.expectEqual(@as(types.VkDeviceMemory, @ptrFromInt(@as(usize, 0x500))), freed_memory.?);
}

test "mapping maintains pointer until unmapped" {
    resetCapture();
    var device = makeFakeDevice();
    var allocation = try allocateWithSize(&device, 4096, 1);
    const ptr = try allocation.map(0, 4096);
    try std.testing.expectEqual(@as([*]u8, @ptrFromInt(@as(usize, 0xA00))), ptr);
    const ptr2 = try allocation.map(16, 4096);
    try std.testing.expectEqual(ptr + 16, ptr2);
    try std.testing.expectEqual(@as(usize, 1), map_calls);
    allocation.unmap();
    try std.testing.expectEqual(@as(usize, 1), unmap_calls);
}

test "flush and invalidate proxy to device" {
    resetCapture();
    var device = makeFakeDevice();
    var allocation = try allocateWithSize(&device, 4096, 1);
    const range = types.VkMappedMemoryRange{ .memory = allocation.memory.?, .offset = 0, .size = 4096 };
    try allocation.flush(&.{range});
    try allocation.invalidate(&.{range});
    try std.testing.expectEqual(@as(usize, 1), flush_calls);
    try std.testing.expectEqual(@as(usize, 1), invalidate_calls);
    allocation.destroy();
}
