const std = @import("std");
const types = @import("types.zig");
const loader = @import("loader.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");

pub const Status = enum {
    success,
    suboptimal,
    out_of_date,
};

pub const Swapchain = struct {
    allocator: std.mem.Allocator,
    device_handle: types.VkDevice,
    dispatch: *const loader.DeviceDispatch,
    allocation_callbacks: ?*const types.VkAllocationCallbacks,
    handle: ?types.VkSwapchainKHR,
    format: types.VkFormat,
    color_space: types.VkColorSpaceKHR,
    extent: types.VkExtent2D,
    image_array_layers: u32,
    present_mode: types.VkPresentModeKHR,
    images: []types.VkImage,

    pub const CreateOptions = struct {
        surface: types.VkSurfaceKHR,
        format: types.VkSurfaceFormatKHR,
        extent: types.VkExtent2D,
        image_usage: types.VkImageUsageFlags,
        min_image_count: u32,
        image_array_layers: u32 = 1,
        present_mode: types.VkPresentModeKHR,
        pre_transform: types.VkSurfaceTransformFlagBitsKHR,
        composite_alpha: types.VkCompositeAlphaFlagBitsKHR,
        queue_family_indices: []const u32 = &.{},
        clipped: bool = true,
        old_swapchain: ?types.VkSwapchainKHR = null,
    };

    pub fn create(device: *device_mod.Device, allocator: std.mem.Allocator, options: CreateOptions) !Swapchain {
        const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;
        const queue_family_indices_ptr: ?[*]const u32 = if (options.queue_family_indices.len == 0)
            null
        else
            options.queue_family_indices.ptr;
        const sharing_mode: types.VkSharingMode = if (options.queue_family_indices.len > 1)
            .CONCURRENT
        else
            .EXCLUSIVE;

        var create_info = types.VkSwapchainCreateInfoKHR{
            .surface = options.surface,
            .minImageCount = options.min_image_count,
            .imageFormat = options.format.format,
            .imageColorSpace = options.format.colorSpace,
            .imageExtent = options.extent,
            .imageArrayLayers = options.image_array_layers,
            .imageUsage = options.image_usage,
            .imageSharingMode = sharing_mode,
            .queueFamilyIndexCount = @intCast(options.queue_family_indices.len),
            .pQueueFamilyIndices = queue_family_indices_ptr,
            .preTransform = options.pre_transform,
            .compositeAlpha = options.composite_alpha,
            .presentMode = options.present_mode,
            .clipped = if (options.clipped) 1 else 0,
            .oldSwapchain = options.old_swapchain,
        };

        var swapchain_handle: types.VkSwapchainKHR = undefined;
        try errors.ensureSuccess(device.dispatch.create_swapchain(device_handle, &create_info, device.allocation_callbacks, &swapchain_handle));

        const images = try loadImages(allocator, &device.dispatch, device_handle, swapchain_handle);

        return Swapchain{
            .allocator = allocator,
            .device_handle = device_handle,
            .dispatch = &device.dispatch,
            .allocation_callbacks = device.allocation_callbacks,
            .handle = swapchain_handle,
            .format = options.format.format,
            .color_space = options.format.colorSpace,
            .extent = options.extent,
            .image_array_layers = options.image_array_layers,
            .present_mode = options.present_mode,
            .images = images,
        };
    }

    pub fn destroy(self: *Swapchain) void {
        if (self.handle) |swapchain_handle| {
            self.dispatch.destroy_swapchain(self.device_handle, swapchain_handle, self.allocation_callbacks);
            self.handle = null;
        }

        if (self.images.len != 0) {
            const owned = self.images;
            self.images = owned[0..0];
            self.allocator.free(owned);
        }
    }

    pub fn recreate(self: *Swapchain, device: *device_mod.Device, options: CreateOptions) !void {
        var recreate_options = options;
        recreate_options.old_swapchain = self.handle;

        const new_swapchain = try Swapchain.create(device, self.allocator, recreate_options);
        self.destroy();
        self.* = new_swapchain;
    }

    pub fn acquireNextImage(self: *Swapchain, timeout_ns: u64, semaphore: ?types.VkSemaphore, fence: ?types.VkFence) errors.Error!AcquireResult {
        const swapchain_handle = self.handle orelse return errors.Error.DeviceCreationFailed;
        var image_index: u32 = undefined;
        const semaphore_handle: types.VkSemaphore = if (semaphore) |sem| sem else @ptrFromInt(@as(usize, 0));
        const fence_handle: types.VkFence = if (fence) |f| f else @ptrFromInt(@as(usize, 0));
        const result = self.dispatch.acquire_next_image(self.device_handle, swapchain_handle, timeout_ns, semaphore_handle, fence_handle, &image_index);
        const status = try classifyResult(result);
        return AcquireResult{ .index = image_index, .status = status };
    }

    pub fn present(self: *Swapchain, queue: types.VkQueue, wait_semaphores: []const types.VkSemaphore, image_index: u32) errors.Error!Status {
        const swapchain_handle = self.handle orelse return errors.Error.DeviceCreationFailed;
        const wait_ptr: ?[*]const types.VkSemaphore = if (wait_semaphores.len == 0) null else wait_semaphores.ptr;
        const swapchains = [_]types.VkSwapchainKHR{swapchain_handle};
        const indices = [_]u32{image_index};
        var present_info = types.VkPresentInfoKHR{
            .waitSemaphoreCount = @intCast(wait_semaphores.len),
            .pWaitSemaphores = wait_ptr,
            .swapchainCount = 1,
            .pSwapchains = swapchains[0..].ptr,
            .pImageIndices = indices[0..].ptr,
            .pResults = null,
        };

        const result = self.dispatch.queue_present(queue, &present_info);
        return classifyResult(result);
    }

    pub fn getImages(self: Swapchain) []const types.VkImage {
        return self.images;
    }

    pub fn imageFormat(self: Swapchain) types.VkFormat {
        return self.format;
    }

    pub fn imageExtent(self: Swapchain) types.VkExtent2D {
        return self.extent;
    }

    pub fn handleOrNull(self: Swapchain) ?types.VkSwapchainKHR {
        return self.handle;
    }
};

pub const AcquireResult = struct {
    index: u32,
    status: Status,
};

fn loadImages(allocator: std.mem.Allocator, dispatch: *const loader.DeviceDispatch, device_handle: types.VkDevice, swapchain_handle: types.VkSwapchainKHR) ![]types.VkImage {
    var count: u32 = 0;
    try errors.ensureSuccess(dispatch.get_swapchain_images(device_handle, swapchain_handle, &count, null));
    if (count == 0) return allocator.alloc(types.VkImage, 0);
    const images = try allocator.alloc(types.VkImage, count);
    errdefer allocator.free(images);
    try errors.ensureSuccess(dispatch.get_swapchain_images(device_handle, swapchain_handle, &count, images.ptr));
    return images;
}

fn classifyResult(result: types.VkResult) errors.Error!Status {
    return switch (result) {
        .SUCCESS => Status.success,
        .SUBOPTIMAL_KHR => Status.suboptimal,
        .ERROR_OUT_OF_DATE_KHR => Status.out_of_date,
        else => blk: {
            try errors.ensureSuccess(result);
            break :blk Status.success;
        },
    };
}

test "classifyResult maps known statuses" {
    const res_ok = try classifyResult(.SUCCESS);
    try std.testing.expectEqual(Status.success, res_ok);

    const res_sub = try classifyResult(.SUBOPTIMAL_KHR);
    try std.testing.expectEqual(Status.suboptimal, res_sub);

    const res_out = try classifyResult(.ERROR_OUT_OF_DATE_KHR);
    try std.testing.expectEqual(Status.out_of_date, res_out);
}
