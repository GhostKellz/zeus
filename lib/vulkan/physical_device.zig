const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const instance_mod = @import("instance.zig");

pub const QueueNeeds = struct {
    require_graphics: bool = true,
    require_present: bool = false,
    require_transfer: bool = false,
    require_compute: bool = false,
    prefer_dedicated_transfer: bool = true,
    prefer_dedicated_compute: bool = false,
};

pub const Requirements = struct {
    required_extensions: []const [:0]const u8 = &.{},
    optional_extensions: []const [:0]const u8 = &.{},
    required_features: ?types.VkPhysicalDeviceFeatures = null,
    prefer_discrete_gpu: bool = true,
    surface: ?types.VkSurfaceKHR = null,
    queues: QueueNeeds = .{},
};

pub const QueueFamilies = struct {
    graphics: u32,
    present: ?u32 = null,
    transfer: ?u32 = null,
    compute: ?u32 = null,

    pub fn unique(self: QueueFamilies, buffer: []u32) []u32 {
        std.debug.assert(buffer.len >= 4);
        var count: usize = 0;
        buffer[count] = self.graphics;
        count += 1;

        if (self.present) |idx| {
            if (!contains(buffer[0..count], idx)) {
                buffer[count] = idx;
                count += 1;
            }
        }

        if (self.transfer) |idx| {
            if (!contains(buffer[0..count], idx)) {
                buffer[count] = idx;
                count += 1;
            }
        }

        if (self.compute) |idx| {
            if (!contains(buffer[0..count], idx)) {
                buffer[count] = idx;
                count += 1;
            }
        }

        return buffer[0..count];
    }
};

pub const Selection = struct {
    physical_device: types.VkPhysicalDevice,
    properties: types.VkPhysicalDeviceProperties,
    features: types.VkPhysicalDeviceFeatures,
    memory_properties: types.VkPhysicalDeviceMemoryProperties,
    queues: QueueFamilies,
    enabled_optional_extensions: [][:0]const u8,
    score: u32,

    pub fn deinit(self: Selection, allocator: std.mem.Allocator) void {
        if (self.enabled_optional_extensions.len != 0) {
            allocator.free(self.enabled_optional_extensions);
        }
    }

    pub fn hasReBAR(self: *const Selection) bool {
        return detectReBAR(self.memory_properties);
    }
};

pub fn selectBest(instance: *instance_mod.Instance, allocator: std.mem.Allocator, requirements: Requirements) !Selection {
    if (requirements.queues.require_present) {
        std.debug.assert(requirements.surface != null);
    }

    const physical_devices = try instance.enumeratePhysicalDevices(allocator);
    defer allocator.free(physical_devices);

    var best: ?Selection = null;
    errdefer if (best) |selection| selection.deinit(allocator);

    for (physical_devices) |physical| {
        const candidate = try evaluateDevice(instance, allocator, physical, requirements);
        if (candidate) |selection| {
            if (best == null or selection.score > best.?.score) {
                if (best) |prev| prev.deinit(allocator);
                best = selection;
            } else {
                selection.deinit(allocator);
            }
        }
    }

    if (best) |result| {
        return result;
    }

    return errors.Error.SuitableDeviceNotFound;
}

fn evaluateDevice(instance: *instance_mod.Instance, allocator: std.mem.Allocator, physical: types.VkPhysicalDevice, requirements: Requirements) !?Selection {
    const extension_props = try instance.enumerateDeviceExtensionProperties(physical, allocator);
    defer allocator.free(extension_props);

    if (!extensionsPresent(extension_props, requirements.required_extensions)) {
        return null;
    }

    var optional_exts = std.ArrayList([:0]const u8).init(allocator);
    defer optional_exts.deinit();
    try collectOptionalExtensions(&optional_exts, extension_props, requirements.optional_extensions);

    const queue_props = try instance.getQueueFamilyProperties(physical, allocator);
    defer allocator.free(queue_props);

    const queue_families = try resolveQueueFamilies(instance, physical, queue_props, requirements);
    if (queue_families == null) return null;

    const features = instance.getPhysicalDeviceFeatures(physical);
    const memory_properties = instance.getPhysicalDeviceMemoryProperties(physical);
    if (requirements.required_features) |needed| {
        if (!supportsFeatures(features, needed)) return null;
    }

    const properties = instance.getPhysicalDeviceProperties(physical);
    const score = scoreDevice(properties, queue_families.?, optional_exts.items, requirements);

    const optional_slice = try optional_exts.toOwnedSlice();

    return Selection{
        .physical_device = physical,
        .properties = properties,
        .features = features,
        .queues = queue_families.?,
        .memory_properties = memory_properties,
        .enabled_optional_extensions = optional_slice,
        .score = score,
    };
}

pub fn detectReBAR(props: types.VkPhysicalDeviceMemoryProperties) bool {
    const threshold: types.VkDeviceSize = 256 * 1024 * 1024;
    for (props.memoryHeaps[0..props.memoryHeapCount], 0..) |heap, heap_index| {
        if ((heap.flags & types.VK_MEMORY_HEAP_DEVICE_LOCAL_BIT) == 0) continue;
        if (heap.size <= threshold) continue;
        for (props.memoryTypes[0..props.memoryTypeCount]) |mem_type| {
            if (mem_type.heapIndex != heap_index) continue;
            const required = types.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT | types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT;
            if ((mem_type.propertyFlags & required) == required) {
                return true;
            }
        }
    }
    return false;
}

fn resolveQueueFamilies(instance: *instance_mod.Instance, physical: types.VkPhysicalDevice, families: []const types.VkQueueFamilyProperties, requirements: Requirements) !?QueueFamilies {
    const needs = requirements.queues;
    var graphics_index: ?u32 = null;
    var present_index: ?u32 = null;
    var transfer_index: ?u32 = null;
    var transfer_score: i32 = -1;
    var compute_index: ?u32 = null;
    var compute_score: i32 = -1;
    var fallback_index: ?u32 = null;

    const surface = requirements.surface;
    const wants_present = needs.require_present or surface != null;

    for (families, 0..) |family, idx_usize| {
        if (family.queueCount == 0) continue;
        const idx: u32 = @intCast(idx_usize);
        if (fallback_index == null) fallback_index = idx;
        const has_graphics = (family.queueFlags & types.VK_QUEUE_GRAPHICS_BIT) != 0;
        const has_compute = (family.queueFlags & types.VK_QUEUE_COMPUTE_BIT) != 0;
        const has_transfer = (family.queueFlags & types.VK_QUEUE_TRANSFER_BIT) != 0;

        if (needs.require_graphics and has_graphics and graphics_index == null) {
            graphics_index = idx;
        }

        if (wants_present and surface) |surface_handle| {
            if (present_index == null) {
                if (try instance.getPhysicalDeviceSurfaceSupport(physical, idx, surface_handle)) {
                    present_index = idx;
                }
            }
        }

        if (needs.require_transfer and has_transfer) {
            const dedicated = (family.queueFlags & (types.VK_QUEUE_GRAPHICS_BIT | types.VK_QUEUE_COMPUTE_BIT)) == 0;
            var score: i32 = 0;
            if (dedicated) {
                score = if (needs.prefer_dedicated_transfer) 3 else 2;
            } else if (!has_graphics) {
                score = 1;
            }
            if (score > transfer_score) {
                transfer_score = score;
                transfer_index = idx;
            }
        }

        if (needs.require_compute and has_compute) {
            const dedicated = !has_graphics;
            var score: i32 = 0;
            if (dedicated) {
                score = if (needs.prefer_dedicated_compute) 2 else 1;
            }
            if (score > compute_score) {
                compute_score = score;
                compute_index = idx;
            }
        }
    }

    if (needs.require_graphics and graphics_index == null) return null;
    if (needs.require_present and present_index == null) return null;
    if (needs.require_transfer and transfer_index == null) return null;
    if (needs.require_compute and compute_index == null) return null;

    const resolved_graphics: u32 = graphics_index orelse fallback_index orelse return null;

    return QueueFamilies{
        .graphics = resolved_graphics,
        .present = present_index,
        .transfer = transfer_index,
        .compute = compute_index,
    };
}

fn scoreDevice(props: types.VkPhysicalDeviceProperties, queues: QueueFamilies, optional_exts: []const [:0]const u8, requirements: Requirements) u32 {
    var score: u32 = 0;
    score += switch (props.deviceType) {
        .DISCRETE_GPU => 1000,
        .INTEGRATED_GPU => if (requirements.prefer_discrete_gpu) 500 else 800,
        .VIRTUAL_GPU => 300,
        .CPU => 100,
        else => 200,
    };

    score += optional_exts.len * 10;

    if (queues.transfer) |transfer_idx| {
        if (transfer_idx != queues.graphics) {
            score += 100;
        }
    }

    if (queues.compute) |compute_idx| {
        if (compute_idx != queues.graphics) {
            score += 60;
        }
    }

    score +%= props.limits.maxImageDimension2D;
    return score;
}

fn extensionsPresent(available: []const types.VkExtensionProperties, required: []const [:0]const u8) bool {
    for (required) |name| {
        if (!hasExtension(available, name)) return false;
    }
    return true;
}

fn collectOptionalExtensions(list: *std.ArrayList([:0]const u8), available: []const types.VkExtensionProperties, optional: []const [:0]const u8) !void {
    for (optional) |name| {
        if (hasExtension(available, name)) {
            try list.append(name);
        }
    }
}

fn hasExtension(available: []const types.VkExtensionProperties, name: [:0]const u8) bool {
    const needle = std.mem.span(name);
    for (available) |prop| {
        const prop_name = std.mem.sliceTo(&prop.extensionName, 0);
        if (std.mem.eql(u8, needle, prop_name)) return true;
    }
    return false;
}

fn supportsFeatures(device_features: types.VkPhysicalDeviceFeatures, required: types.VkPhysicalDeviceFeatures) bool {
    inline for (std.meta.fields(types.VkPhysicalDeviceFeatures)) |field| {
        const required_value = @field(required, field.name);
        if (required_value != 0) {
            const available = @field(device_features, field.name);
            if (available == 0) return false;
        }
    }
    return true;
}

fn contains(haystack: []const u32, value: u32) bool {
    for (haystack) |item| {
        if (item == value) return true;
    }
    return false;
}

test "supportsFeatures validates required bits" {
    var available: types.VkPhysicalDeviceFeatures = .{};
    available.robustBufferAccess = 1;
    available.fillModeNonSolid = 1;

    var required: types.VkPhysicalDeviceFeatures = .{};
    required.fillModeNonSolid = 1;

    try std.testing.expect(supportsFeatures(available, required));
    required.robustBufferAccess = 1;
    try std.testing.expect(supportsFeatures(available, required));
    required.shaderInt64 = 1;
    try std.testing.expect(!supportsFeatures(available, required));
}

test "detectReBAR identifies large host-visible device local heap" {
    var props: types.VkPhysicalDeviceMemoryProperties = std.mem.zeroes(types.VkPhysicalDeviceMemoryProperties);
    props.memoryHeapCount = 2;
    props.memoryHeaps[0] = .{
        .size = 12 * 1024 * 1024 * 1024,
        .flags = types.VK_MEMORY_HEAP_DEVICE_LOCAL_BIT,
    };
    props.memoryHeaps[1] = .{
        .size = 512 * 1024 * 1024,
        .flags = 0,
    };
    props.memoryTypeCount = 2;
    props.memoryTypes[0] = .{
        .propertyFlags = types.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        .heapIndex = 0,
    };
    props.memoryTypes[1] = .{
        .propertyFlags = types.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT | types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT,
        .heapIndex = 0,
    };

    try std.testing.expect(detectReBAR(props));

    var selection = Selection{
        .physical_device = @as(types.VkPhysicalDevice, @ptrCast(@as(usize, 0x1))),
        .properties = std.mem.zeroes(types.VkPhysicalDeviceProperties),
        .features = std.mem.zeroes(types.VkPhysicalDeviceFeatures),
        .memory_properties = props,
        .queues = .{ .graphics = 0 },
        .enabled_optional_extensions = &.{},
        .score = 0,
    };

    try std.testing.expect(selection.hasReBAR());
}

test "detectReBAR returns false for small or non host-visible heaps" {
    var props: types.VkPhysicalDeviceMemoryProperties = std.mem.zeroes(types.VkPhysicalDeviceMemoryProperties);
    props.memoryHeapCount = 1;
    props.memoryHeaps[0] = .{
        .size = 128 * 1024 * 1024,
        .flags = types.VK_MEMORY_HEAP_DEVICE_LOCAL_BIT,
    };
    props.memoryTypeCount = 2;
    props.memoryTypes[0] = .{
        .propertyFlags = types.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        .heapIndex = 0,
    };
    props.memoryTypes[1] = .{
        .propertyFlags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT,
        .heapIndex = 0,
    };

    try std.testing.expect(!detectReBAR(props));
}
