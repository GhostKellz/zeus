const std = @import("std");
const types = @import("types.zig");
const loader = @import("loader.zig");
const vk_errors = @import("error.zig");
const queue_guard = @import("queue_guard.zig");

pub const Device = struct {
    allocator: std.mem.Allocator,
    loader: *loader.Loader,
    dispatch: loader.DeviceDispatch,
    handle: ?types.VkDevice,
    allocation_callbacks: ?*const types.VkAllocationCallbacks,
    default_queue_family: ?u32 = null,
    default_queue: ?types.VkQueue = null,

    pub const QueueRequest = struct {
        family_index: u32,
        priorities: []const f32,
    };

    pub const Options = struct {
        physical_device: types.VkPhysicalDevice,
        queues: []const QueueRequest,
        enabled_extensions: []const [:0]const u8 = &.{},
        enabled_features: ?types.VkPhysicalDeviceFeatures = null,
        allocation_callbacks: ?*const types.VkAllocationCallbacks = null,
    };

    pub fn create(loader_ref: *loader.Loader, instance_dispatch: *const loader.InstanceDispatch, allocator: std.mem.Allocator, options: Options) !Device {
        std.debug.assert(options.queues.len > 0);

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const arena_alloc = arena.allocator();

        const queue_infos = try buildQueueCreateInfos(arena_alloc, options.queues);

        // Validate queue create infos in Debug mode
        queue_guard.assertQueuePrioritiesValid(queue_infos);

        const extension_ptrs = try copyCStringPointers(arena_alloc, options.enabled_extensions);

        var features_storage: types.VkPhysicalDeviceFeatures = undefined;
        var features_ptr: ?*const types.VkPhysicalDeviceFeatures = null;
        if (options.enabled_features) |features| {
            features_storage = features;
            features_ptr = &features_storage;
        }

        var create_info = types.VkDeviceCreateInfo{
            .queueCreateInfoCount = @intCast(queue_infos.len),
            .pQueueCreateInfos = queue_infos.ptr,
            .enabledExtensionCount = @intCast(options.enabled_extensions.len),
            .ppEnabledExtensionNames = extension_ptrs,
            .pEnabledFeatures = features_ptr,
        };

        var device_handle: types.VkDevice = undefined;
        try vk_errors.ensureSuccess(instance_dispatch.create_device(options.physical_device, &create_info, options.allocation_callbacks, &device_handle));

        const device_dispatch = try loader_ref.deviceDispatch(device_handle);

        var device = Device{
            .allocator = allocator,
            .loader = loader_ref,
            .dispatch = device_dispatch,
            .handle = device_handle,
            .allocation_callbacks = options.allocation_callbacks,
        };

        // Cache the first queue requested as the default queue for quick access.
        const primary_request = options.queues[0];
        var queue_handle: types.VkQueue = undefined;
        device_dispatch.get_device_queue(device_handle, primary_request.family_index, 0, &queue_handle);
        device.default_queue_family = primary_request.family_index;
        device.default_queue = queue_handle;

        return device;
    }

    pub fn destroy(self: *Device) void {
        if (self.handle) |device_handle| {
            self.dispatch.destroy_device(device_handle, self.allocation_callbacks);
            self.handle = null;
            self.default_queue = null;
        }
    }

    pub fn getQueue(self: *Device, family_index: u32, queue_index: u32) ?types.VkQueue {
        const device_handle = self.handle orelse return null;
        var queue_handle: types.VkQueue = undefined;
        self.dispatch.get_device_queue(device_handle, family_index, queue_index, &queue_handle);
        return queue_handle;
    }

    pub fn waitQueueIdle(self: *Device, queue: types.VkQueue) !void {
        try vk_errors.ensureSuccess(self.dispatch.queue_wait_idle(queue));
    }

    pub fn waitIdle(self: *Device) !void {
        if (self.default_queue) |queue_handle| {
            try vk_errors.ensureSuccess(self.dispatch.queue_wait_idle(queue_handle));
        }
    }
};

fn buildQueueCreateInfos(allocator: std.mem.Allocator, queues: []const Device.QueueRequest) ![]types.VkDeviceQueueCreateInfo {
    const infos = try allocator.alloc(types.VkDeviceQueueCreateInfo, queues.len);
    for (queues, infos) |request, *info| {
        const priorities = try allocator.alloc(f32, request.priorities.len);
        std.mem.copyForwards(f32, priorities, request.priorities);
        info.* = types.VkDeviceQueueCreateInfo{
            .queueFamilyIndex = request.family_index,
            .queueCount = @intCast(request.priorities.len),
            .pQueuePriorities = priorities.ptr,
        };
    }
    return infos;
}

fn copyCStringPointers(allocator: std.mem.Allocator, values: []const [:0]const u8) !?[*]const [*:0]const u8 {
    if (values.len == 0) return null;
    const buffer = try allocator.alloc([*:0]const u8, values.len);
    for (values, 0..) |value, idx| {
        buffer[idx] = value.ptr;
    }
    return @as([*]const [*:0]const u8, @ptrCast(buffer.ptr));
}
