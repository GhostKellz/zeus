const std = @import("std");
const types = @import("types.zig");
const vk_errors = @import("error.zig");

/// Platform-agnostic Vulkan loader responsible for dynamically loading the Vulkan
/// shared library and resolving function pointers for global, instance, and
/// device level dispatch tables. The design avoids any build-time code
/// generation so the bindings stay pure Zig.
pub const Loader = struct {
    allocator: std.mem.Allocator,
    lib: ?std.DynLib = null,
    get_instance_proc: ?types.PFN_vkGetInstanceProcAddr = null,
    get_device_proc: ?types.PFN_vkGetDeviceProcAddr = null,
    global_dispatch: ?GlobalDispatch = null,

    pub const Options = struct {
        search_paths: []const [:0]const u8 = defaultSearchPaths(),
    };

    pub fn init(allocator: std.mem.Allocator, options: Options) !Loader {
        var loader = Loader{
            .allocator = allocator,
        };
        errdefer loader.deinit();
        try loader.openLibrary(options.search_paths);
        try loader.populateGetProcAddrs();
        return loader;
    }

    pub fn deinit(self: *Loader) void {
        self.global_dispatch = null;
        self.get_instance_proc = null;
        self.get_device_proc = null;
        if (self.lib) |*lib| {
            lib.close();
            self.lib = null;
        }
    }

    pub fn defaultSearchPaths() []const [:0]const u8 {
        return switch (std.Target.current.os.tag) {
            .windows => &.{"vulkan-1.dll"},
            .macos => &.{ "libvulkan.dylib", "libMoltenVK.dylib" },
            else => &.{ "libvulkan.so.1", "libvulkan.so" },
        };
    }

    fn openLibrary(self: *Loader, search_paths: []const [:0]const u8) !void {
        for (search_paths) |candidate| {
            switch (std.DynLib.open(candidate)) {
                .success => |lib| {
                    self.lib = lib;
                    return;
                },
                .failure => {
                    continue;
                },
            }
        }
        return vk_errors.Error.LibraryNotFound;
    }

    fn populateGetProcAddrs(self: *Loader) !void {
        const lib = self.lib orelse return vk_errors.Error.LibraryNotFound;
        self.get_instance_proc = try lookupProc(types.PFN_vkGetInstanceProcAddr, lib, "vkGetInstanceProcAddr");
        self.get_device_proc = try lookupProc(types.PFN_vkGetDeviceProcAddr, lib, "vkGetDeviceProcAddr");
    }

    fn lookupProc(comptime T: type, lib: std.DynLib, name: [:0]const u8) !T {
        const symbol = lib.lookup(T, name) catch return vk_errors.Error.MissingSymbol;
        if (symbol) |ptr| return ptr;
        return vk_errors.Error.MissingSymbol;
    }

    pub fn global(self: *Loader) !*const GlobalDispatch {
        if (self.global_dispatch) |dispatch| return &dispatch;
        const dispatch = try GlobalDispatch.load(self);
        self.global_dispatch = dispatch;
        return &(self.global_dispatch.?);
    }

    pub fn instanceDispatch(self: *Loader, instance: types.VkInstance) !InstanceDispatch {
        const proc = self.get_instance_proc orelse return vk_errors.Error.MissingSymbol;
        return InstanceDispatch.load(instance, proc);
    }

    pub fn deviceDispatch(self: *Loader, device: types.VkDevice) !DeviceDispatch {
        const proc = self.get_device_proc orelse return vk_errors.Error.MissingSymbol;
        return DeviceDispatch.load(device, proc);
    }

    pub fn getInstanceProcAddr(self: *Loader) ?types.PFN_vkGetInstanceProcAddr {
        return self.get_instance_proc;
    }
};

pub const GlobalDispatch = struct {
    create_instance: types.PFN_vkCreateInstance,
    enumerate_instance_extension_properties: types.PFN_vkEnumerateInstanceExtensionProperties,
    enumerate_instance_layer_properties: types.PFN_vkEnumerateInstanceLayerProperties,

    fn load(loader: *Loader) !GlobalDispatch {
        const proc = loader.get_instance_proc orelse return vk_errors.Error.MissingSymbol;
        return GlobalDispatch{
            .create_instance = try loadGlobalProc(types.PFN_vkCreateInstance, proc, "vkCreateInstance"),
            .enumerate_instance_extension_properties = try loadGlobalProc(types.PFN_vkEnumerateInstanceExtensionProperties, proc, "vkEnumerateInstanceExtensionProperties"),
            .enumerate_instance_layer_properties = try loadGlobalProc(types.PFN_vkEnumerateInstanceLayerProperties, proc, "vkEnumerateInstanceLayerProperties"),
        };
    }
};

pub const InstanceDispatch = struct {
    destroy_instance: types.PFN_vkDestroyInstance,
    enumerate_physical_devices: types.PFN_vkEnumeratePhysicalDevices,
    get_physical_device_queue_family_properties: types.PFN_vkGetPhysicalDeviceQueueFamilyProperties,
    get_physical_device_features: types.PFN_vkGetPhysicalDeviceFeatures,
    get_physical_device_properties: types.PFN_vkGetPhysicalDeviceProperties,
    get_physical_device_memory_properties: types.PFN_vkGetPhysicalDeviceMemoryProperties,
    enumerate_device_extension_properties: types.PFN_vkEnumerateDeviceExtensionProperties,
    create_device: types.PFN_vkCreateDevice,
    get_device_proc_addr: types.PFN_vkGetDeviceProcAddr,
    destroy_surface: types.PFN_vkDestroySurfaceKHR,
    get_physical_device_surface_support: types.PFN_vkGetPhysicalDeviceSurfaceSupportKHR,
    get_physical_device_surface_capabilities: types.PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR,
    get_physical_device_surface_formats: types.PFN_vkGetPhysicalDeviceSurfaceFormatsKHR,
    get_physical_device_surface_present_modes: types.PFN_vkGetPhysicalDeviceSurfacePresentModesKHR,

    fn load(instance: types.VkInstance, proc: types.PFN_vkGetInstanceProcAddr) !InstanceDispatch {
        return InstanceDispatch{
            .destroy_instance = try loadInstanceProc(types.PFN_vkDestroyInstance, proc, instance, "vkDestroyInstance"),
            .enumerate_physical_devices = try loadInstanceProc(types.PFN_vkEnumeratePhysicalDevices, proc, instance, "vkEnumeratePhysicalDevices"),
            .get_physical_device_queue_family_properties = try loadInstanceProc(types.PFN_vkGetPhysicalDeviceQueueFamilyProperties, proc, instance, "vkGetPhysicalDeviceQueueFamilyProperties"),
            .get_physical_device_features = try loadInstanceProc(types.PFN_vkGetPhysicalDeviceFeatures, proc, instance, "vkGetPhysicalDeviceFeatures"),
            .get_physical_device_properties = try loadInstanceProc(types.PFN_vkGetPhysicalDeviceProperties, proc, instance, "vkGetPhysicalDeviceProperties"),
            .get_physical_device_memory_properties = try loadInstanceProc(types.PFN_vkGetPhysicalDeviceMemoryProperties, proc, instance, "vkGetPhysicalDeviceMemoryProperties"),
            .enumerate_device_extension_properties = try loadInstanceProc(types.PFN_vkEnumerateDeviceExtensionProperties, proc, instance, "vkEnumerateDeviceExtensionProperties"),
            .create_device = try loadInstanceProc(types.PFN_vkCreateDevice, proc, instance, "vkCreateDevice"),
            .get_device_proc_addr = try loadInstanceProc(types.PFN_vkGetDeviceProcAddr, proc, instance, "vkGetDeviceProcAddr"),
            .destroy_surface = try loadInstanceProc(types.PFN_vkDestroySurfaceKHR, proc, instance, "vkDestroySurfaceKHR"),
            .get_physical_device_surface_support = try loadInstanceProc(types.PFN_vkGetPhysicalDeviceSurfaceSupportKHR, proc, instance, "vkGetPhysicalDeviceSurfaceSupportKHR"),
            .get_physical_device_surface_capabilities = try loadInstanceProc(types.PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR, proc, instance, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR"),
            .get_physical_device_surface_formats = try loadInstanceProc(types.PFN_vkGetPhysicalDeviceSurfaceFormatsKHR, proc, instance, "vkGetPhysicalDeviceSurfaceFormatsKHR"),
            .get_physical_device_surface_present_modes = try loadInstanceProc(types.PFN_vkGetPhysicalDeviceSurfacePresentModesKHR, proc, instance, "vkGetPhysicalDeviceSurfacePresentModesKHR"),
        };
    }
};

pub const DeviceDispatch = struct {
    destroy_device: types.PFN_vkDestroyDevice,
    get_device_queue: types.PFN_vkGetDeviceQueue,
    queue_submit: types.PFN_vkQueueSubmit,
    queue_wait_idle: types.PFN_vkQueueWaitIdle,
    allocate_memory: types.PFN_vkAllocateMemory,
    free_memory: types.PFN_vkFreeMemory,
    map_memory: types.PFN_vkMapMemory,
    unmap_memory: types.PFN_vkUnmapMemory,
    flush_mapped_memory_ranges: types.PFN_vkFlushMappedMemoryRanges,
    invalidate_mapped_memory_ranges: types.PFN_vkInvalidateMappedMemoryRanges,
    create_buffer: types.PFN_vkCreateBuffer,
    destroy_buffer: types.PFN_vkDestroyBuffer,
    get_buffer_memory_requirements: types.PFN_vkGetBufferMemoryRequirements,
    bind_buffer_memory: types.PFN_vkBindBufferMemory,
    create_image: types.PFN_vkCreateImage,
    destroy_image: types.PFN_vkDestroyImage,
    get_image_memory_requirements: types.PFN_vkGetImageMemoryRequirements,
    bind_image_memory: types.PFN_vkBindImageMemory,
    create_image_view: types.PFN_vkCreateImageView,
    destroy_image_view: types.PFN_vkDestroyImageView,
    cmd_pipeline_barrier: types.PFN_vkCmdPipelineBarrier,
    cmd_copy_buffer: types.PFN_vkCmdCopyBuffer,
    cmd_copy_buffer_to_image: types.PFN_vkCmdCopyBufferToImage,
    cmd_bind_pipeline: types.PFN_vkCmdBindPipeline,
    cmd_bind_descriptor_sets: types.PFN_vkCmdBindDescriptorSets,
    cmd_bind_vertex_buffers: types.PFN_vkCmdBindVertexBuffers,
    cmd_set_viewport: types.PFN_vkCmdSetViewport,
    cmd_set_scissor: types.PFN_vkCmdSetScissor,
    cmd_draw: types.PFN_vkCmdDraw,
    create_command_pool: types.PFN_vkCreateCommandPool,
    destroy_command_pool: types.PFN_vkDestroyCommandPool,
    reset_command_pool: types.PFN_vkResetCommandPool,
    allocate_command_buffers: types.PFN_vkAllocateCommandBuffers,
    free_command_buffers: types.PFN_vkFreeCommandBuffers,
    begin_command_buffer: types.PFN_vkBeginCommandBuffer,
    end_command_buffer: types.PFN_vkEndCommandBuffer,
    create_fence: types.PFN_vkCreateFence,
    destroy_fence: types.PFN_vkDestroyFence,
    reset_fences: types.PFN_vkResetFences,
    wait_for_fences: types.PFN_vkWaitForFences,
    get_fence_status: types.PFN_vkGetFenceStatus,
    create_semaphore: types.PFN_vkCreateSemaphore,
    destroy_semaphore: types.PFN_vkDestroySemaphore,
    wait_semaphores: types.PFN_vkWaitSemaphores,
    signal_semaphore: types.PFN_vkSignalSemaphore,
    create_swapchain: types.PFN_vkCreateSwapchainKHR,
    destroy_swapchain: types.PFN_vkDestroySwapchainKHR,
    get_swapchain_images: types.PFN_vkGetSwapchainImagesKHR,
    acquire_next_image: types.PFN_vkAcquireNextImageKHR,
    queue_present: types.PFN_vkQueuePresentKHR,
    get_refresh_cycle_duration_google: types.PFN_vkGetRefreshCycleDurationGOOGLE,
    get_past_presentation_timing_google: types.PFN_vkGetPastPresentationTimingGOOGLE,

    fn load(device: types.VkDevice, proc: types.PFN_vkGetDeviceProcAddr) !DeviceDispatch {
        return DeviceDispatch{
            .destroy_device = try loadDeviceProc(types.PFN_vkDestroyDevice, proc, device, "vkDestroyDevice"),
            .get_device_queue = try loadDeviceProc(types.PFN_vkGetDeviceQueue, proc, device, "vkGetDeviceQueue"),
            .queue_submit = try loadDeviceProc(types.PFN_vkQueueSubmit, proc, device, "vkQueueSubmit"),
            .queue_wait_idle = try loadDeviceProc(types.PFN_vkQueueWaitIdle, proc, device, "vkQueueWaitIdle"),
            .allocate_memory = try loadDeviceProc(types.PFN_vkAllocateMemory, proc, device, "vkAllocateMemory"),
            .free_memory = try loadDeviceProc(types.PFN_vkFreeMemory, proc, device, "vkFreeMemory"),
            .map_memory = try loadDeviceProc(types.PFN_vkMapMemory, proc, device, "vkMapMemory"),
            .unmap_memory = try loadDeviceProc(types.PFN_vkUnmapMemory, proc, device, "vkUnmapMemory"),
            .flush_mapped_memory_ranges = try loadDeviceProc(types.PFN_vkFlushMappedMemoryRanges, proc, device, "vkFlushMappedMemoryRanges"),
            .invalidate_mapped_memory_ranges = try loadDeviceProc(types.PFN_vkInvalidateMappedMemoryRanges, proc, device, "vkInvalidateMappedMemoryRanges"),
            .create_buffer = try loadDeviceProc(types.PFN_vkCreateBuffer, proc, device, "vkCreateBuffer"),
            .destroy_buffer = try loadDeviceProc(types.PFN_vkDestroyBuffer, proc, device, "vkDestroyBuffer"),
            .get_buffer_memory_requirements = try loadDeviceProc(types.PFN_vkGetBufferMemoryRequirements, proc, device, "vkGetBufferMemoryRequirements"),
            .bind_buffer_memory = try loadDeviceProc(types.PFN_vkBindBufferMemory, proc, device, "vkBindBufferMemory"),
            .create_image = try loadDeviceProc(types.PFN_vkCreateImage, proc, device, "vkCreateImage"),
            .destroy_image = try loadDeviceProc(types.PFN_vkDestroyImage, proc, device, "vkDestroyImage"),
            .get_image_memory_requirements = try loadDeviceProc(types.PFN_vkGetImageMemoryRequirements, proc, device, "vkGetImageMemoryRequirements"),
            .bind_image_memory = try loadDeviceProc(types.PFN_vkBindImageMemory, proc, device, "vkBindImageMemory"),
            .create_image_view = try loadDeviceProc(types.PFN_vkCreateImageView, proc, device, "vkCreateImageView"),
            .destroy_image_view = try loadDeviceProc(types.PFN_vkDestroyImageView, proc, device, "vkDestroyImageView"),
            .cmd_pipeline_barrier = try loadDeviceProc(types.PFN_vkCmdPipelineBarrier, proc, device, "vkCmdPipelineBarrier"),
            .cmd_copy_buffer = try loadDeviceProc(types.PFN_vkCmdCopyBuffer, proc, device, "vkCmdCopyBuffer"),
            .cmd_copy_buffer_to_image = try loadDeviceProc(types.PFN_vkCmdCopyBufferToImage, proc, device, "vkCmdCopyBufferToImage"),
            .cmd_bind_pipeline = try loadDeviceProc(types.PFN_vkCmdBindPipeline, proc, device, "vkCmdBindPipeline"),
            .cmd_bind_descriptor_sets = try loadDeviceProc(types.PFN_vkCmdBindDescriptorSets, proc, device, "vkCmdBindDescriptorSets"),
            .cmd_bind_vertex_buffers = try loadDeviceProc(types.PFN_vkCmdBindVertexBuffers, proc, device, "vkCmdBindVertexBuffers"),
            .cmd_set_viewport = try loadDeviceProc(types.PFN_vkCmdSetViewport, proc, device, "vkCmdSetViewport"),
            .cmd_set_scissor = try loadDeviceProc(types.PFN_vkCmdSetScissor, proc, device, "vkCmdSetScissor"),
            .cmd_draw = try loadDeviceProc(types.PFN_vkCmdDraw, proc, device, "vkCmdDraw"),
            .create_command_pool = try loadDeviceProc(types.PFN_vkCreateCommandPool, proc, device, "vkCreateCommandPool"),
            .destroy_command_pool = try loadDeviceProc(types.PFN_vkDestroyCommandPool, proc, device, "vkDestroyCommandPool"),
            .reset_command_pool = try loadDeviceProc(types.PFN_vkResetCommandPool, proc, device, "vkResetCommandPool"),
            .allocate_command_buffers = try loadDeviceProc(types.PFN_vkAllocateCommandBuffers, proc, device, "vkAllocateCommandBuffers"),
            .free_command_buffers = try loadDeviceProc(types.PFN_vkFreeCommandBuffers, proc, device, "vkFreeCommandBuffers"),
            .begin_command_buffer = try loadDeviceProc(types.PFN_vkBeginCommandBuffer, proc, device, "vkBeginCommandBuffer"),
            .end_command_buffer = try loadDeviceProc(types.PFN_vkEndCommandBuffer, proc, device, "vkEndCommandBuffer"),
            .create_fence = try loadDeviceProc(types.PFN_vkCreateFence, proc, device, "vkCreateFence"),
            .destroy_fence = try loadDeviceProc(types.PFN_vkDestroyFence, proc, device, "vkDestroyFence"),
            .reset_fences = try loadDeviceProc(types.PFN_vkResetFences, proc, device, "vkResetFences"),
            .wait_for_fences = try loadDeviceProc(types.PFN_vkWaitForFences, proc, device, "vkWaitForFences"),
            .get_fence_status = try loadDeviceProc(types.PFN_vkGetFenceStatus, proc, device, "vkGetFenceStatus"),
            .create_semaphore = try loadDeviceProc(types.PFN_vkCreateSemaphore, proc, device, "vkCreateSemaphore"),
            .destroy_semaphore = try loadDeviceProc(types.PFN_vkDestroySemaphore, proc, device, "vkDestroySemaphore"),
            .wait_semaphores = try loadDeviceProc(types.PFN_vkWaitSemaphores, proc, device, "vkWaitSemaphores"),
            .signal_semaphore = try loadDeviceProc(types.PFN_vkSignalSemaphore, proc, device, "vkSignalSemaphore"),
            .create_swapchain = try loadDeviceProc(types.PFN_vkCreateSwapchainKHR, proc, device, "vkCreateSwapchainKHR"),
            .destroy_swapchain = try loadDeviceProc(types.PFN_vkDestroySwapchainKHR, proc, device, "vkDestroySwapchainKHR"),
            .get_swapchain_images = try loadDeviceProc(types.PFN_vkGetSwapchainImagesKHR, proc, device, "vkGetSwapchainImagesKHR"),
            .acquire_next_image = try loadDeviceProc(types.PFN_vkAcquireNextImageKHR, proc, device, "vkAcquireNextImageKHR"),
            .queue_present = try loadDeviceProc(types.PFN_vkQueuePresentKHR, proc, device, "vkQueuePresentKHR"),
            .get_refresh_cycle_duration_google = loadOptionalDeviceProc(types.PFN_vkGetRefreshCycleDurationGOOGLE, proc, device, "vkGetRefreshCycleDurationGOOGLE"),
            .get_past_presentation_timing_google = loadOptionalDeviceProc(types.PFN_vkGetPastPresentationTimingGOOGLE, proc, device, "vkGetPastPresentationTimingGOOGLE"),
        };
    }
};

fn loadInstanceProc(comptime T: type, proc: types.PFN_vkGetInstanceProcAddr, instance: ?types.VkInstance, name: [:0]const u8) !T {
    const raw = proc(instance, name);
    if (raw) |fn_ptr| return castProc(T, fn_ptr);
    return vk_errors.Error.MissingSymbol;
}

fn loadDeviceProc(comptime T: type, proc: types.PFN_vkGetDeviceProcAddr, device: types.VkDevice, name: [:0]const u8) !T {
    const raw = proc(device, name);
    if (raw) |fn_ptr| return castProc(T, fn_ptr);
    return vk_errors.Error.MissingSymbol;
}

fn loadOptionalDeviceProc(comptime T: type, proc: types.PFN_vkGetDeviceProcAddr, device: types.VkDevice, name: [:0]const u8) T {
    const raw = proc(device, name);
    if (raw) |fn_ptr| {
        return @as(T, @ptrCast(fn_ptr));
    }
    return null;
}

pub const LoaderScope = struct {
    loader: *Loader,

    pub fn global(self: LoaderScope) !*const GlobalDispatch {
        return self.loader.global();
    }
};

fn loadGlobalProc(comptime T: type, proc: types.PFN_vkGetInstanceProcAddr, name: [:0]const u8) !T {
    const raw = proc(null, name);
    if (raw) |fn_ptr| return castProc(T, fn_ptr);
    return vk_errors.Error.MissingSymbol;
}

fn castProc(comptime T: type, ptr: types.PFN_vkVoidFunctionNonNull) T {
    return @as(T, @ptrCast(ptr));
}

test "Loader reports missing Vulkan library" {
    const allocator = std.testing.allocator;
    const result = Loader.init(allocator, .{ .search_paths = &.{"/__vk_missing__/libvulkan.so"} });
    try std.testing.expectError(vk_errors.Error.LibraryNotFound, result);
}
