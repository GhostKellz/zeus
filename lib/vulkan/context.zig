/// High-level Vulkan context that manages the entire lifecycle
/// Simplifies setup with builder pattern and automatic cleanup
const std = @import("std");
const types = @import("types.zig");
const loader_mod = @import("loader.zig");
const instance_mod = @import("instance.zig");
const device_mod = @import("device.zig");
const physical_device_mod = @import("physical_device.zig");

/// Unified Vulkan context with automatic resource management
pub const Context = struct {
    allocator: std.mem.Allocator,
    loader: loader_mod.Loader,
    instance: types.VkInstance,
    instance_dispatch: loader_mod.InstanceDispatch,
    physical_device: types.VkPhysicalDevice,
    device: types.VkDevice,
    device_dispatch: loader_mod.DeviceDispatch,

    // Queue handles
    graphics_queue: types.VkQueue,
    compute_queue: ?types.VkQueue = null,
    transfer_queue: ?types.VkQueue = null,

    // Queue family indices
    graphics_family: u32,
    compute_family: ?u32 = null,
    transfer_family: ?u32 = null,

    /// Builder pattern for Context creation
    pub const Builder = struct {
        allocator: std.mem.Allocator,
        app_name: [:0]const u8 = "Zeus Application",
        app_version: u32 = types.makeApiVersion(1, 0, 0),
        engine_name: [:0]const u8 = "Zeus",
        engine_version: u32 = types.makeApiVersion(0, 1, 0),
        api_version: u32 = types.makeApiVersion(1, 3, 0),

        enable_validation: bool = false,
        required_extensions: []const [*:0]const u8 = &.{},
        required_device_extensions: []const [*:0]const u8 = &.{},

        prefer_discrete_gpu: bool = true,
        require_compute_queue: bool = false,
        require_transfer_queue: bool = false,

        pub fn init(allocator: std.mem.Allocator) Builder {
            return Builder{
                .allocator = allocator,
            };
        }

        pub fn setAppName(self: Builder, name: [:0]const u8) Builder {
            var result = self;
            result.app_name = name;
            return result;
        }

        pub fn setAppVersion(self: Builder, major: u32, minor: u32, patch: u32) Builder {
            var result = self;
            result.app_version = types.makeApiVersion(major, minor, patch);
            return result;
        }

        pub fn setApiVersion(self: Builder, major: u32, minor: u32, patch: u32) Builder {
            var result = self;
            result.api_version = types.makeApiVersion(major, minor, patch);
            return result;
        }

        pub fn enableValidation(self: Builder) Builder {
            var result = self;
            result.enable_validation = true;
            return result;
        }

        pub fn requireComputeQueue(self: Builder) Builder {
            var result = self;
            result.require_compute_queue = true;
            return result;
        }

        pub fn requireTransferQueue(self: Builder) Builder {
            var result = self;
            result.require_transfer_queue = true;
            return result;
        }

        pub fn addInstanceExtensions(self: Builder, extensions: []const [*:0]const u8) Builder {
            var result = self;
            result.required_extensions = extensions;
            return result;
        }

        pub fn addDeviceExtensions(self: Builder, extensions: []const [*:0]const u8) Builder {
            var result = self;
            result.required_device_extensions = extensions;
            return result;
        }

        /// Build the Context with all specified options
        pub fn build(self: Builder) !Context {
            var ctx: Context = undefined;
            ctx.allocator = self.allocator;

            // Step 1: Initialize loader
            ctx.loader = try loader_mod.Loader.init(self.allocator, .{});
            errdefer ctx.loader.deinit();

            const global = try ctx.loader.global();

            // Step 2: Create instance
            const app_info = types.VkApplicationInfo{
                .pApplicationName = self.app_name.ptr,
                .applicationVersion = self.app_version,
                .pEngineName = self.engine_name.ptr,
                .engineVersion = self.engine_version,
                .apiVersion = self.api_version,
            };

            // Add validation layers if requested
            var layers = try std.ArrayList([*:0]const u8).initCapacity(self.allocator, if (self.enable_validation) 1 else 0);
            defer layers.deinit(self.allocator);
            if (self.enable_validation) {
                try layers.append(self.allocator, "VK_LAYER_KHRONOS_validation");
            }

            const instance_create_info = types.VkInstanceCreateInfo{
                .pApplicationInfo = &app_info,
                .enabledLayerCount = @intCast(layers.items.len),
                .ppEnabledLayerNames = if (layers.items.len > 0) layers.items.ptr else null,
                .enabledExtensionCount = @intCast(self.required_extensions.len),
                .ppEnabledExtensionNames = if (self.required_extensions.len > 0) self.required_extensions.ptr else null,
            };

            const result = global.create_instance(&instance_create_info, null, &ctx.instance);
            if (result != .SUCCESS) return error.InstanceCreationFailed;

            // Step 3: Get instance dispatch
            ctx.instance_dispatch = try ctx.loader.instanceDispatch(ctx.instance);
            errdefer ctx.instance_dispatch.destroy_instance(ctx.instance, null);

            // Step 4: Select physical device
            var device_count: u32 = 0;
            _ = ctx.instance_dispatch.enumerate_physical_devices(ctx.instance, &device_count, null);
            if (device_count == 0) return error.NoVulkanDevices;

            const devices = try self.allocator.alloc(types.VkPhysicalDevice, device_count);
            defer self.allocator.free(devices);
            _ = ctx.instance_dispatch.enumerate_physical_devices(ctx.instance, &device_count, devices.ptr);

            // Simple selection: prefer discrete GPU if requested
            ctx.physical_device = devices[0];
            if (self.prefer_discrete_gpu and device_count > 1) {
                for (devices) |dev| {
                    var props: types.VkPhysicalDeviceProperties = undefined;
                    ctx.instance_dispatch.get_physical_device_properties(dev, &props);
                    if (props.deviceType == .DISCRETE_GPU) {
                        ctx.physical_device = dev;
                        break;
                    }
                }
            }

            // Step 5: Find queue families
            var queue_family_count: u32 = 0;
            ctx.instance_dispatch.get_physical_device_queue_family_properties(ctx.physical_device, &queue_family_count, null);

            const queue_families = try self.allocator.alloc(types.VkQueueFamilyProperties, queue_family_count);
            defer self.allocator.free(queue_families);
            ctx.instance_dispatch.get_physical_device_queue_family_properties(ctx.physical_device, &queue_family_count, queue_families.ptr);

            // Find graphics queue (required)
            var graphics_found = false;
            for (queue_families, 0..) |family, i| {
                if (family.queueFlags & types.VK_QUEUE_GRAPHICS_BIT != 0) {
                    ctx.graphics_family = @intCast(i);
                    graphics_found = true;
                    break;
                }
            }
            if (!graphics_found) return error.NoGraphicsQueue;

            // Find compute queue if requested
            if (self.require_compute_queue) {
                for (queue_families, 0..) |family, i| {
                    if (family.queueFlags & types.VK_QUEUE_COMPUTE_BIT != 0) {
                        ctx.compute_family = @intCast(i);
                        break;
                    }
                }
                if (ctx.compute_family == null) return error.NoComputeQueue;
            }

            // Find transfer queue if requested
            if (self.require_transfer_queue) {
                for (queue_families, 0..) |family, i| {
                    if (family.queueFlags & types.VK_QUEUE_TRANSFER_BIT != 0) {
                        ctx.transfer_family = @intCast(i);
                        break;
                    }
                }
                if (ctx.transfer_family == null) return error.NoTransferQueue;
            }

            // Step 6: Create logical device
            const queue_priority = [_]f32{1.0};
            var queue_create_infos = try std.ArrayList(types.VkDeviceQueueCreateInfo).initCapacity(self.allocator, 3);
            defer queue_create_infos.deinit(self.allocator);

            // Graphics queue
            try queue_create_infos.append(self.allocator, types.VkDeviceQueueCreateInfo{
                .sType = .DEVICE_QUEUE_CREATE_INFO,
                .queueFamilyIndex = ctx.graphics_family,
                .queueCount = 1,
                .pQueuePriorities = &queue_priority,
                .pNext = null,
                .flags = 0,
            });

            // Compute queue (if different from graphics)
            if (ctx.compute_family) |cf| {
                if (cf != ctx.graphics_family) {
                    try queue_create_infos.append(self.allocator, types.VkDeviceQueueCreateInfo{
                        .sType = .DEVICE_QUEUE_CREATE_INFO,
                        .queueFamilyIndex = cf,
                        .queueCount = 1,
                        .pQueuePriorities = &queue_priority,
                        .pNext = null,
                        .flags = 0,
                    });
                }
            }

            // Transfer queue (if different from graphics and compute)
            if (ctx.transfer_family) |tf| {
                if (tf != ctx.graphics_family and (ctx.compute_family == null or tf != ctx.compute_family.?)) {
                    try queue_create_infos.append(self.allocator, types.VkDeviceQueueCreateInfo{
                        .sType = .DEVICE_QUEUE_CREATE_INFO,
                        .queueFamilyIndex = tf,
                        .queueCount = 1,
                        .pQueuePriorities = &queue_priority,
                        .pNext = null,
                        .flags = 0,
                    });
                }
            }

            var device_features = std.mem.zeroes(types.VkPhysicalDeviceFeatures);

            const device_create_info = types.VkDeviceCreateInfo{
                .sType = .DEVICE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .queueCreateInfoCount = @intCast(queue_create_infos.items.len),
                .pQueueCreateInfos = queue_create_infos.items.ptr,
                .enabledLayerCount = 0,
                .ppEnabledLayerNames = null,
                .enabledExtensionCount = @intCast(self.required_device_extensions.len),
                .ppEnabledExtensionNames = if (self.required_device_extensions.len > 0)
                    self.required_device_extensions.ptr
                else
                    null,
                .pEnabledFeatures = &device_features,
            };

            const dev_result = ctx.instance_dispatch.create_device(ctx.physical_device, &device_create_info, null, &ctx.device);
            if (dev_result != .SUCCESS) return error.DeviceCreationFailed;

            // Step 7: Get device dispatch
            const dev_proc_addr = ctx.instance_dispatch.get_device_proc_addr(ctx.device, "vkGetDeviceProcAddr");
            const device_proc = @as(types.PFN_vkGetDeviceProcAddr, @ptrCast(dev_proc_addr orelse return error.MissingProcAddr));
            ctx.device_dispatch = try loader_mod.DeviceDispatch.load(ctx.device, device_proc);

            // Step 8: Get queue handles
            ctx.device_dispatch.get_device_queue(ctx.device, ctx.graphics_family, 0, &ctx.graphics_queue);

            if (ctx.compute_family) |cf| {
                var queue: types.VkQueue = undefined;
                ctx.device_dispatch.get_device_queue(ctx.device, cf, 0, &queue);
                ctx.compute_queue = queue;
            }

            if (ctx.transfer_family) |tf| {
                var queue: types.VkQueue = undefined;
                ctx.device_dispatch.get_device_queue(ctx.device, tf, 0, &queue);
                ctx.transfer_queue = queue;
            }

            return ctx;
        }
    };

    /// Create a Context with default settings
    pub fn init(allocator: std.mem.Allocator) !Context {
        return Builder.init(allocator).build();
    }

    /// Create a Context using the builder pattern
    pub fn builder(allocator: std.mem.Allocator) Builder {
        return Builder.init(allocator);
    }

    /// Cleanup all Vulkan resources (call with defer)
    pub fn deinit(self: *Context) void {
        self.device_dispatch.destroy_device(self.device, null);
        self.instance_dispatch.destroy_instance(self.instance, null);
        self.loader.deinit();
    }

    /// Wait for all device operations to complete
    pub fn waitIdle(self: *Context) !void {
        // Wait on all active queues
        _ = self.device_dispatch.queue_wait_idle(self.graphics_queue);
        if (self.compute_queue) |q| {
            _ = self.device_dispatch.queue_wait_idle(q);
        }
        if (self.transfer_queue) |q| {
            _ = self.device_dispatch.queue_wait_idle(q);
        }
    }

    /// Wait for graphics queue to complete
    pub fn waitGraphicsIdle(self: *Context) !void {
        const result = self.device_dispatch.queue_wait_idle(self.graphics_queue);
        if (result != .SUCCESS) return error.QueueWaitIdleFailed;
    }
};
