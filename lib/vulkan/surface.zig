const std = @import("std");
const types = @import("types.zig");
const loader = @import("loader.zig");
const errors = @import("error.zig");
const instance_mod = @import("instance.zig");

pub const Surface = struct {
    instance_handle: types.VkInstance,
    dispatch: *const loader.InstanceDispatch,
    handle: ?types.VkSurfaceKHR,
    allocation_callbacks: ?*const types.VkAllocationCallbacks,

    pub fn wrap(instance: *instance_mod.Instance, surface_handle: types.VkSurfaceKHR, allocation_callbacks: ?*const types.VkAllocationCallbacks) Surface {
        return Surface{
            .instance_handle = instance.handle orelse unreachable,
            .dispatch = &instance.dispatch,
            .handle = surface_handle,
            .allocation_callbacks = allocation_callbacks,
        };
    }

    pub fn isValid(self: Surface) bool {
        return self.handle != null;
    }

    pub fn deinit(self: *Surface) void {
        if (self.handle) |surface_handle| {
            self.dispatch.destroy_surface(self.instance_handle, surface_handle, self.allocation_callbacks);
            self.handle = null;
        }
    }

    pub fn supportsPresent(self: Surface, physical_device: types.VkPhysicalDevice, queue_family_index: u32) !bool {
        const surface_handle = self.handle orelse return errors.Error.InstanceCreationFailed;
        var supported: types.VkBool32 = 0;
        try errors.ensureSuccess(self.dispatch.get_physical_device_surface_support(physical_device, queue_family_index, surface_handle, &supported));
        return supported != 0;
    }

    pub fn capabilities(self: Surface, physical_device: types.VkPhysicalDevice) !types.VkSurfaceCapabilitiesKHR {
        const surface_handle = self.handle orelse return errors.Error.InstanceCreationFailed;
        var caps: types.VkSurfaceCapabilitiesKHR = undefined;
        try errors.ensureSuccess(self.dispatch.get_physical_device_surface_capabilities(physical_device, surface_handle, &caps));
        return caps;
    }

    pub fn formats(self: Surface, allocator: std.mem.Allocator, physical_device: types.VkPhysicalDevice) ![]types.VkSurfaceFormatKHR {
        const surface_handle = self.handle orelse return errors.Error.InstanceCreationFailed;
        var count: u32 = 0;
        try errors.ensureSuccess(self.dispatch.get_physical_device_surface_formats(physical_device, surface_handle, &count, null));
        if (count == 0) return allocator.alloc(types.VkSurfaceFormatKHR, 0);
        const buffer = try allocator.alloc(types.VkSurfaceFormatKHR, count);
        errdefer allocator.free(buffer);
        try errors.ensureSuccess(self.dispatch.get_physical_device_surface_formats(physical_device, surface_handle, &count, buffer.ptr));
        return buffer;
    }

    pub fn presentModes(self: Surface, allocator: std.mem.Allocator, physical_device: types.VkPhysicalDevice) ![]types.VkPresentModeKHR {
        const surface_handle = self.handle orelse return errors.Error.InstanceCreationFailed;
        var count: u32 = 0;
        try errors.ensureSuccess(self.dispatch.get_physical_device_surface_present_modes(physical_device, surface_handle, &count, null));
        if (count == 0) return allocator.alloc(types.VkPresentModeKHR, 0);
        const buffer = try allocator.alloc(types.VkPresentModeKHR, count);
        errdefer allocator.free(buffer);
        try errors.ensureSuccess(self.dispatch.get_physical_device_surface_present_modes(physical_device, surface_handle, &count, buffer.ptr));
        return buffer;
    }

    pub fn handleOrNull(self: Surface) ?types.VkSurfaceKHR {
        return self.handle;
    }
};

pub fn selectSwapExtent(capabilities: types.VkSurfaceCapabilitiesKHR, desired: types.VkExtent2D) types.VkExtent2D {
    if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
        return capabilities.currentExtent;
    }

    return .{
        .width = std.math.clamp(desired.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
        .height = std.math.clamp(desired.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
    };
}

pub fn chooseSurfaceFormat(formats: []const types.VkSurfaceFormatKHR) types.VkSurfaceFormatKHR {
    for (formats) |format| {
        if (format.format == .B8G8R8A8_SRGB and format.colorSpace == .SRGB_NONLINEAR) {
            return format;
        }
    }
    return if (formats.len > 0) formats[0] else types.VkSurfaceFormatKHR{
        .format = .B8G8R8A8_SRGB,
        .colorSpace = .SRGB_NONLINEAR,
    };
}

pub fn choosePresentMode(modes: []const types.VkPresentModeKHR, prefer_mailbox: bool) types.VkPresentModeKHR {
    if (prefer_mailbox) {
        for (modes) |mode| {
            if (mode == .MAILBOX) return mode;
        }
    }

    for (modes) |mode| {
        if (mode == .FIFO) return mode;
    }

    if (modes.len > 0) return modes[0];
    return .FIFO;
}

pub fn clampImageCount(capabilities: types.VkSurfaceCapabilitiesKHR, desired: u32) u32 {
    var image_count = desired;
    if (image_count < capabilities.minImageCount) {
        image_count = capabilities.minImageCount;
    }
    if (capabilities.maxImageCount != 0 and image_count > capabilities.maxImageCount) {
        image_count = capabilities.maxImageCount;
    }
    return image_count;
}

test "clampImageCount respects surface limits" {
    const caps = types.VkSurfaceCapabilitiesKHR{
        .minImageCount = 2,
        .maxImageCount = 4,
        .currentExtent = .{ .width = 0, .height = 0 },
        .minImageExtent = .{ .width = 0, .height = 0 },
        .maxImageExtent = .{ .width = 0, .height = 0 },
        .maxImageArrayLayers = 1,
        .supportedTransforms = 0,
        .currentTransform = .IDENTITY,
        .supportedCompositeAlpha = 0,
        .supportedUsageFlags = 0,
    };

    try std.testing.expectEqual(@as(u32, 2), clampImageCount(caps, 1));
    try std.testing.expectEqual(@as(u32, 3), clampImageCount(caps, 3));
    try std.testing.expectEqual(@as(u32, 4), clampImageCount(caps, 10));
}
