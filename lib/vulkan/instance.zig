const std = @import("std");
const types = @import("types.zig");
const loader = @import("loader.zig");
const vk_errors = @import("error.zig");
const device = @import("device.zig");

pub const Instance = struct {
    allocator: std.mem.Allocator,
    loader: *loader.Loader,
    dispatch: loader.InstanceDispatch,
    handle: ?types.VkInstance,
    allocation_callbacks: ?*const types.VkAllocationCallbacks,

    pub const ApplicationInfo = struct {
        application_name: ?[:0]const u8 = null,
        application_version: u32 = 0,
        engine_name: ?[:0]const u8 = null,
        engine_version: u32 = 0,
        api_version: u32 = types.makeApiVersion(1, 3, 0),
    };

    pub const CreateOptions = struct {
        application: ?ApplicationInfo = null,
        enabled_layers: []const [:0]const u8 = &.{},
        enabled_extensions: []const [:0]const u8 = &.{},
        allocation_callbacks: ?*const types.VkAllocationCallbacks = null,
    };

    pub fn create(loader_ref: *loader.Loader, allocator: std.mem.Allocator, options: CreateOptions) !Instance {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const arena_alloc = arena.allocator();

        var app_info_storage: types.VkApplicationInfo = undefined;
        var app_info_ptr: ?*const types.VkApplicationInfo = null;
        if (options.application) |app| {
            app_info_storage = types.VkApplicationInfo{
                .pApplicationName = app.application_name,
                .applicationVersion = app.application_version,
                .pEngineName = app.engine_name,
                .engineVersion = app.engine_version,
                .apiVersion = app.api_version,
            };
            app_info_ptr = &app_info_storage;
        }

        const layer_ptrs = try copyCStringPointers(arena_alloc, options.enabled_layers);
        const extension_ptrs = try copyCStringPointers(arena_alloc, options.enabled_extensions);

        var create_info = types.VkInstanceCreateInfo{
            .pApplicationInfo = app_info_ptr,
            .enabledLayerCount = @intCast(options.enabled_layers.len),
            .ppEnabledLayerNames = layer_ptrs,
            .enabledExtensionCount = @intCast(options.enabled_extensions.len),
            .ppEnabledExtensionNames = extension_ptrs,
        };

        var instance_handle: types.VkInstance = undefined;
        const global_dispatch = try loader_ref.global();
        try vk_errors.ensureSuccess(global_dispatch.create_instance(&create_info, options.allocation_callbacks, &instance_handle));

        const instance_dispatch = try loader_ref.instanceDispatch(instance_handle);

        return Instance{
            .allocator = allocator,
            .loader = loader_ref,
            .dispatch = instance_dispatch,
            .handle = instance_handle,
            .allocation_callbacks = options.allocation_callbacks,
        };
    }

    pub fn destroy(self: *Instance) void {
        if (self.handle) |instance_handle| {
            self.dispatch.destroy_instance(instance_handle, self.allocation_callbacks);
            self.handle = null;
        }
    }

    pub fn enumeratePhysicalDevices(self: *Instance, allocator: std.mem.Allocator) ![]types.VkPhysicalDevice {
        const instance_handle = self.handle orelse return vk_errors.Error.InstanceCreationFailed;
        var count: u32 = 0;
        try vk_errors.ensureSuccess(self.dispatch.enumerate_physical_devices(instance_handle, &count, null));
        if (count == 0) return vk_errors.Error.NoPhysicalDevices;
        const devices = try allocator.alloc(types.VkPhysicalDevice, count);
        errdefer allocator.free(devices);
        try vk_errors.ensureSuccess(self.dispatch.enumerate_physical_devices(instance_handle, &count, devices.ptr));
        return devices;
    }

    pub fn getQueueFamilyProperties(self: *Instance, physical_device: types.VkPhysicalDevice, allocator: std.mem.Allocator) ![]types.VkQueueFamilyProperties {
        var count: u32 = 0;
        self.dispatch.get_physical_device_queue_family_properties(physical_device, &count, null);
        if (count == 0) return allocator.alloc(types.VkQueueFamilyProperties, 0);
        const props = try allocator.alloc(types.VkQueueFamilyProperties, count);
        errdefer allocator.free(props);
        self.dispatch.get_physical_device_queue_family_properties(physical_device, &count, props.ptr);
        return props;
    }

    pub fn selectFirstGraphicsDevice(self: *Instance, allocator: std.mem.Allocator) !DeviceCandidate {
        const devices = try self.enumeratePhysicalDevices(allocator);
        defer allocator.free(devices);

        for (devices) |physical| {
            const families = try self.getQueueFamilyProperties(physical, allocator);
            defer allocator.free(families);

            if (findQueueFamilyIndex(families, types.VK_QUEUE_GRAPHICS_BIT)) |graphics_family| {
                return DeviceCandidate{
                    .physical_device = physical,
                    .graphics_queue_family = graphics_family,
                };
            }
        }

        return vk_errors.Error.QueueFamilyNotFound;
    }

    pub fn createDevice(self: *Instance, allocator: std.mem.Allocator, options: device.Device.Options) !device.Device {
        return device.Device.create(self.loader, &self.dispatch, allocator, options);
    }

    pub fn createDebugMessenger(self: *Instance, create_info: *const types.VkDebugUtilsMessengerCreateInfoEXT, allocator: ?*const types.VkAllocationCallbacks) !vk_errors.DebugMessenger {
        const instance_handle = self.handle orelse return vk_errors.Error.InstanceCreationFailed;
        const proc = self.loader.getInstanceProcAddr() orelse return vk_errors.Error.DebugMessengerUnavailable;
        const create_raw = proc(instance_handle, "vkCreateDebugUtilsMessengerEXT");
        const destroy_raw = proc(instance_handle, "vkDestroyDebugUtilsMessengerEXT");
        return vk_errors.DebugMessenger.init(instance_handle, create_raw, destroy_raw, create_info, allocator);
    }

    pub fn getPhysicalDeviceProperties(self: *Instance, physical_device: types.VkPhysicalDevice) types.VkPhysicalDeviceProperties {
        var props: types.VkPhysicalDeviceProperties = undefined;
        self.dispatch.get_physical_device_properties(physical_device, &props);
        return props;
    }

    pub fn getPhysicalDeviceFeatures(self: *Instance, physical_device: types.VkPhysicalDevice) types.VkPhysicalDeviceFeatures {
        var features: types.VkPhysicalDeviceFeatures = undefined;
        self.dispatch.get_physical_device_features(physical_device, &features);
        return features;
    }

    pub fn getPhysicalDeviceMemoryProperties(self: *Instance, physical_device: types.VkPhysicalDevice) types.VkPhysicalDeviceMemoryProperties {
        var props: types.VkPhysicalDeviceMemoryProperties = undefined;
        self.dispatch.get_physical_device_memory_properties(physical_device, &props);
        return props;
    }

    pub fn enumerateDeviceExtensionProperties(self: *Instance, physical_device: types.VkPhysicalDevice, allocator: std.mem.Allocator) ![]types.VkExtensionProperties {
        var count: u32 = 0;
        try vk_errors.ensureSuccess(self.dispatch.enumerate_device_extension_properties(physical_device, null, &count, null));
        if (count == 0) return allocator.alloc(types.VkExtensionProperties, 0);
        const props = try allocator.alloc(types.VkExtensionProperties, count);
        errdefer allocator.free(props);
        try vk_errors.ensureSuccess(self.dispatch.enumerate_device_extension_properties(physical_device, null, &count, props.ptr));
        return props;
    }

    pub fn getPhysicalDeviceSurfaceSupport(self: *Instance, physical_device: types.VkPhysicalDevice, queue_family_index: u32, surface: types.VkSurfaceKHR) !bool {
        var supported: types.VkBool32 = 0;
        try vk_errors.ensureSuccess(self.dispatch.get_physical_device_surface_support(physical_device, queue_family_index, surface, &supported));
        return supported != 0;
    }
};

pub const DeviceCandidate = struct {
    physical_device: types.VkPhysicalDevice,
    graphics_queue_family: u32,
};

pub fn findQueueFamilyIndex(families: []const types.VkQueueFamilyProperties, required_flags: types.VkQueueFlags) ?u32 {
    for (families, 0..) |family, index| {
        if ((family.queueFlags & required_flags) == required_flags and family.queueCount > 0) {
            return @intCast(index);
        }
    }
    return null;
}

fn copyCStringPointers(allocator: std.mem.Allocator, values: []const [:0]const u8) !?[*]const [*:0]const u8 {
    if (values.len == 0) return null;
    const buffer = try allocator.alloc([*:0]const u8, values.len);
    for (values, 0..) |value, idx| {
        buffer[idx] = value.ptr;
    }
    return @as([*]const [*:0]const u8, @ptrCast(buffer.ptr));
}

test "findQueueFamilyIndex identifies matching family" {
    const families = [_]types.VkQueueFamilyProperties{
        .{ .queueFlags = 0, .queueCount = 1, .timestampValidBits = 0, .minImageTransferGranularity = .{ .width = 1, .height = 1, .depth = 1 } },
        .{ .queueFlags = types.VK_QUEUE_GRAPHICS_BIT | types.VK_QUEUE_TRANSFER_BIT, .queueCount = 2, .timestampValidBits = 0, .minImageTransferGranularity = .{ .width = 1, .height = 1, .depth = 1 } },
    };
    const idx = findQueueFamilyIndex(&families, types.VK_QUEUE_GRAPHICS_BIT) orelse unreachable;
    try std.testing.expectEqual(@as(u32, 1), idx);
}
