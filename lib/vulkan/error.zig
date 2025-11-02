const std = @import("std");
const types = @import("types.zig");

pub const BaseError = error{
    LibraryNotFound,
    MissingSymbol,
    LayerNotPresent,
    ExtensionNotPresent,
    NoPhysicalDevices,
    QueueFamilyNotFound,
    InstanceCreationFailed,
    DeviceCreationFailed,
    DebugMessengerUnavailable,
    SuitableDeviceNotFound,
};

pub const VkError = error{
    NotReady,
    Timeout,
    EventSet,
    EventReset,
    Incomplete,
    OutOfHostMemory,
    OutOfDeviceMemory,
    InitializationFailed,
    DeviceLost,
    MemoryMapFailed,
    FeatureNotPresent,
    IncompatibleDriver,
    TooManyObjects,
    FormatNotSupported,
    FragmentedPool,
    OutOfDate,
    SurfaceLost,
    Unknown,
};

pub const Error = std.meta.errorSetUnion(BaseError, VkError);

pub fn ensureSuccess(result: types.VkResult) Error!void {
    switch (result) {
        .SUCCESS => return,
        .NOT_READY => return VkError.NotReady,
        .TIMEOUT => return VkError.Timeout,
        .EVENT_SET => return VkError.EventSet,
        .EVENT_RESET => return VkError.EventReset,
        .INCOMPLETE => return VkError.Incomplete,
        .ERROR_OUT_OF_HOST_MEMORY => return VkError.OutOfHostMemory,
        .ERROR_OUT_OF_DEVICE_MEMORY => return VkError.OutOfDeviceMemory,
        .ERROR_INITIALIZATION_FAILED => return VkError.InitializationFailed,
        .ERROR_DEVICE_LOST => return VkError.DeviceLost,
        .ERROR_MEMORY_MAP_FAILED => return VkError.MemoryMapFailed,
        .ERROR_LAYER_NOT_PRESENT => return BaseError.LayerNotPresent,
        .ERROR_EXTENSION_NOT_PRESENT => return BaseError.ExtensionNotPresent,
        .ERROR_FEATURE_NOT_PRESENT => return VkError.FeatureNotPresent,
        .ERROR_INCOMPATIBLE_DRIVER => return VkError.IncompatibleDriver,
        .ERROR_TOO_MANY_OBJECTS => return VkError.TooManyObjects,
        .ERROR_FORMAT_NOT_SUPPORTED => return VkError.FormatNotSupported,
        .ERROR_FRAGMENTED_POOL => return VkError.FragmentedPool,
        .ERROR_OUT_OF_DATE_KHR => return VkError.OutOfDate,
        .ERROR_SURFACE_LOST_KHR => return VkError.SurfaceLost,
        else => return VkError.Unknown,
    }
}

pub fn vkResultToString(result: types.VkResult) []const u8 {
    return switch (result) {
        .SUCCESS => "SUCCESS",
        .NOT_READY => "NOT_READY",
        .TIMEOUT => "TIMEOUT",
        .EVENT_SET => "EVENT_SET",
        .EVENT_RESET => "EVENT_RESET",
        .INCOMPLETE => "INCOMPLETE",
        .ERROR_OUT_OF_HOST_MEMORY => "ERROR_OUT_OF_HOST_MEMORY",
        .ERROR_OUT_OF_DEVICE_MEMORY => "ERROR_OUT_OF_DEVICE_MEMORY",
        .ERROR_INITIALIZATION_FAILED => "ERROR_INITIALIZATION_FAILED",
        .ERROR_DEVICE_LOST => "ERROR_DEVICE_LOST",
        .ERROR_MEMORY_MAP_FAILED => "ERROR_MEMORY_MAP_FAILED",
        .ERROR_LAYER_NOT_PRESENT => "ERROR_LAYER_NOT_PRESENT",
        .ERROR_EXTENSION_NOT_PRESENT => "ERROR_EXTENSION_NOT_PRESENT",
        .ERROR_FEATURE_NOT_PRESENT => "ERROR_FEATURE_NOT_PRESENT",
        .ERROR_INCOMPATIBLE_DRIVER => "ERROR_INCOMPATIBLE_DRIVER",
        .ERROR_TOO_MANY_OBJECTS => "ERROR_TOO_MANY_OBJECTS",
        .ERROR_FORMAT_NOT_SUPPORTED => "ERROR_FORMAT_NOT_SUPPORTED",
        .ERROR_FRAGMENTED_POOL => "ERROR_FRAGMENTED_POOL",
        .ERROR_OUT_OF_DATE_KHR => "ERROR_OUT_OF_DATE_KHR",
        .ERROR_SURFACE_LOST_KHR => "ERROR_SURFACE_LOST_KHR",
        else => "ERROR_UNKNOWN",
    };
}

pub const DebugMessenger = struct {
    instance: types.VkInstance,
    handle: ?types.VkDebugUtilsMessengerEXT,
    destroy_fn: DestroyFn,
    allocator: ?*const types.VkAllocationCallbacks,

    const DestroyFn = *const fn (types.VkInstance, types.VkDebugUtilsMessengerEXT, ?*const types.VkAllocationCallbacks) callconv(.c) void;

    pub fn init(instance: types.VkInstance, create_raw: types.PFN_vkVoidFunction, destroy_raw: types.PFN_vkVoidFunction, create_info: *const types.VkDebugUtilsMessengerCreateInfoEXT, allocator: ?*const types.VkAllocationCallbacks) Error!DebugMessenger {
        const create_fn = convertCreate(create_raw) orelse return BaseError.DebugMessengerUnavailable;
        const destroy_fn_ptr = convertDestroy(destroy_raw) orelse return BaseError.DebugMessengerUnavailable;
        var messenger_handle: types.VkDebugUtilsMessengerEXT = undefined;
        try ensureSuccess(create_fn(instance, create_info, allocator, &messenger_handle));
        return DebugMessenger{
            .instance = instance,
            .handle = messenger_handle,
            .destroy_fn = destroy_fn_ptr,
            .allocator = allocator,
        };
    }

    pub fn isActive(self: DebugMessenger) bool {
        return self.handle != null;
    }

    pub fn deinit(self: *DebugMessenger) void {
        if (self.handle) |handle| {
            self.destroy_fn(self.instance, handle, self.allocator);
            self.handle = null;
        }
    }
};

pub fn defaultDebugCreateInfo(callback: types.PFN_vkDebugUtilsMessengerCallbackEXT) types.VkDebugUtilsMessengerCreateInfoEXT {
    return types.VkDebugUtilsMessengerCreateInfoEXT{
        .messageSeverity = defaultSeverityMask(),
        .messageType = defaultMessageTypeMask(),
        .pfnUserCallback = callback,
    };
}

fn defaultSeverityMask() types.VkDebugUtilsMessageSeverityFlagsEXT {
    return @as(types.VkDebugUtilsMessageSeverityFlagsEXT, @intFromEnum(types.VkDebugUtilsMessageSeverityFlagBitsEXT.WARNING) |
        @intFromEnum(types.VkDebugUtilsMessageSeverityFlagBitsEXT.ERROR));
}

fn defaultMessageTypeMask() types.VkDebugUtilsMessageTypeFlagsEXT {
    return @as(types.VkDebugUtilsMessageTypeFlagsEXT, @intFromEnum(types.VkDebugUtilsMessageTypeFlagBitsEXT.GENERAL) |
        @intFromEnum(types.VkDebugUtilsMessageTypeFlagBitsEXT.VALIDATION) |
        @intFromEnum(types.VkDebugUtilsMessageTypeFlagBitsEXT.PERFORMANCE));
}

fn convertCreate(raw: types.PFN_vkVoidFunction) ?types.PFN_vkCreateDebugUtilsMessengerEXT {
    if (raw) |ptr| {
        return @as(types.PFN_vkCreateDebugUtilsMessengerEXT, @ptrCast(ptr));
    }
    return null;
}

fn convertDestroy(raw: types.PFN_vkVoidFunction) ?DebugMessenger.DestroyFn {
    if (raw) |ptr| {
        return @as(DebugMessenger.DestroyFn, @ptrCast(ptr));
    }
    return null;
}

pub fn castSubmitProc(raw: types.PFN_vkVoidFunction) ?types.PFN_vkSubmitDebugUtilsMessageEXT {
    if (raw) |ptr| {
        return @as(types.PFN_vkSubmitDebugUtilsMessageEXT, @ptrCast(ptr));
    }
    return null;
}

test "vkResultToString returns readable values" {
    try std.testing.expectEqualStrings("SUCCESS", vkResultToString(.SUCCESS));
    try std.testing.expectEqualStrings("ERROR_UNKNOWN", vkResultToString(@enumFromInt(@as(i32, -999999))));
}
