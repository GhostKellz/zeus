const std = @import("std");
const types = @import("types.zig");
const loader = @import("loader.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");

pub const PresentMode = enum {
    fifo,
    fifo_relaxed,
    mailbox,
    immediate,

    pub fn toVk(self: PresentMode) types.VkPresentModeKHR {
        return switch (self) {
            .fifo => types.VkPresentModeKHR.FIFO,
            .fifo_relaxed => types.VkPresentModeKHR.FIFO_RELAXED,
            .mailbox => types.VkPresentModeKHR.MAILBOX,
            .immediate => types.VkPresentModeKHR.IMMEDIATE,
        };
    }
};

fn hasPresentMode(modes: []const types.VkPresentModeKHR, mode: types.VkPresentModeKHR) bool {
    for (modes) |available| {
        if (available == mode) return true;
    }
    return false;
}

pub fn selectPresentMode(available_modes: []const types.VkPresentModeKHR, preferred: PresentMode) types.VkPresentModeKHR {
    const desired = preferred.toVk();
    if (hasPresentMode(available_modes, desired)) return desired;

    return switch (preferred) {
        .fifo => types.VkPresentModeKHR.FIFO,
        .fifo_relaxed => if (hasPresentMode(available_modes, types.VkPresentModeKHR.FIFO))
            types.VkPresentModeKHR.FIFO
        else
            types.VkPresentModeKHR.FIFO,
        .mailbox => blk: {
            if (hasPresentMode(available_modes, types.VkPresentModeKHR.IMMEDIATE)) {
                break :blk types.VkPresentModeKHR.IMMEDIATE;
            }
            break :blk types.VkPresentModeKHR.FIFO;
        },
        .immediate => blk: {
            if (hasPresentMode(available_modes, types.VkPresentModeKHR.MAILBOX)) {
                break :blk types.VkPresentModeKHR.MAILBOX;
            }
            break :blk types.VkPresentModeKHR.FIFO;
        },
    };
}

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

    pub const PresentTiming = struct {
        present_id: u32,
        desired_present_time_ns: u64,
    };

    pub const PresentOptions = struct {
        wait_semaphores: []const types.VkSemaphore = &.{},
        timing: ?PresentTiming = null,
    };

    pub const PastPresentationTimings = struct {
        allocator: std.mem.Allocator,
        data: []types.VkPastPresentationTimingGOOGLE,
        valid_count: usize,

        pub fn slice(self: PastPresentationTimings) []const types.VkPastPresentationTimingGOOGLE {
            return self.data[0..self.valid_count];
        }

        pub fn deinit(self: *PastPresentationTimings) void {
            if (self.data.len != 0) {
                self.allocator.free(self.data);
                self.data = &.{};
            }
            self.valid_count = 0;
        }
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
        return self.presentWithOptions(queue, image_index, .{ .wait_semaphores = wait_semaphores });
    }

    pub fn presentWithOptions(self: *Swapchain, queue: types.VkQueue, image_index: u32, options: PresentOptions) errors.Error!Status {
        const swapchain_handle = self.handle orelse return errors.Error.DeviceCreationFailed;
        const wait_ptr: ?[*]const types.VkSemaphore = if (options.wait_semaphores.len == 0) null else options.wait_semaphores.ptr;
        var swapchains = [_]types.VkSwapchainKHR{swapchain_handle};
        var indices = [_]u32{image_index};
        var present_info = types.VkPresentInfoKHR{
            .waitSemaphoreCount = @intCast(options.wait_semaphores.len),
            .pWaitSemaphores = wait_ptr,
            .swapchainCount = 1,
            .pSwapchains = swapchains[0..].ptr,
            .pImageIndices = indices[0..].ptr,
            .pResults = null,
        };

        var present_time_storage = [_]types.VkPresentTimeGOOGLE{.{ .presentID = 0, .desiredPresentTime = 0 }};
        var timing_info_storage = types.VkPresentTimesInfoGOOGLE{
            .swapchainCount = 0,
            .pTimes = null,
        };

        if (options.timing) |timing| {
            if (!self.supportsDisplayTiming()) return errors.Error.FeatureNotPresent;
            present_time_storage[0] = .{
                .presentID = timing.present_id,
                .desiredPresentTime = timing.desired_present_time_ns,
            };
            timing_info_storage = types.VkPresentTimesInfoGOOGLE{
                .swapchainCount = 1,
                .pTimes = @ptrCast(present_time_storage[0..].ptr),
            };
            present_info.pNext = @as(?*const anyopaque, @ptrCast(&timing_info_storage));
        }

        const result = self.dispatch.queue_present(queue, &present_info);
        return classifyResult(result);
    }

    pub fn supportsDisplayTiming(self: *const Swapchain) bool {
        return self.dispatch.get_refresh_cycle_duration_google != null and self.dispatch.get_past_presentation_timing_google != null;
    }

    pub fn queryRefreshCycleDuration(self: *Swapchain) errors.Error!?u64 {
        const swapchain_handle = self.handle orelse return errors.Error.DeviceCreationFailed;
        const fn_ptr = self.dispatch.get_refresh_cycle_duration_google orelse return null;
        var duration = types.VkRefreshCycleDurationGOOGLE{ .refreshDuration = 0 };
        try errors.ensureSuccess(fn_ptr(self.device_handle, swapchain_handle, &duration));
        return duration.refreshDuration;
    }

    pub fn fetchPastPresentationTimings(self: *Swapchain, allocator: std.mem.Allocator) errors.Error!?PastPresentationTimings {
        const swapchain_handle = self.handle orelse return errors.Error.DeviceCreationFailed;
        const fn_ptr = self.dispatch.get_past_presentation_timing_google orelse return null;
        var count: u32 = 0;
        try errors.ensureSuccess(fn_ptr(self.device_handle, swapchain_handle, &count, null));

        const alloc_count = @as(usize, @intCast(count));
        const buffer = try allocator.alloc(types.VkPastPresentationTimingGOOGLE, alloc_count);
        errdefer allocator.free(buffer);

        if (alloc_count != 0) {
            try errors.ensureSuccess(fn_ptr(self.device_handle, swapchain_handle, &count, buffer.ptr));
        }

        return PastPresentationTimings{
            .allocator = allocator,
            .data = buffer,
            .valid_count = @as(usize, @intCast(count)),
        };
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

const TestTimingCapture = struct {
    pub var queue_present_calls: usize = 0;
    pub var last_has_timing: bool = false;
    pub var last_present_id: u32 = 0;
    pub var last_desired_time: u64 = 0;
    pub var refresh_calls: usize = 0;
    pub var refresh_value: u64 = 0;
    pub var past_calls: usize = 0;
    pub var past_request_count: u32 = 0;

    pub fn reset() void {
        queue_present_calls = 0;
        last_has_timing = false;
        last_present_id = 0;
        last_desired_time = 0;
        refresh_calls = 0;
        refresh_value = 0;
        past_calls = 0;
        past_request_count = 0;
    }

    pub fn queuePresent(_: types.VkQueue, info: *const types.VkPresentInfoKHR) callconv(.c) types.VkResult {
        queue_present_calls += 1;
        if (info.pNext) |pnext| {
            const timing = @as(*const types.VkPresentTimesInfoGOOGLE, @ptrCast(pnext));
            last_has_timing = true;
            if (timing.pTimes) |times| {
                const first = times[0];
                last_present_id = first.presentID;
                last_desired_time = first.desiredPresentTime;
            }
        } else {
            last_has_timing = false;
        }
        return .SUCCESS;
    }

    pub fn getRefresh(_: types.VkDevice, _: types.VkSwapchainKHR, duration: *types.VkRefreshCycleDurationGOOGLE) callconv(.c) types.VkResult {
        refresh_calls += 1;
        duration.refreshDuration = refresh_value;
        return .SUCCESS;
    }

    pub fn getPastTiming(_: types.VkDevice, _: types.VkSwapchainKHR, count: *u32, timings: ?[*]types.VkPastPresentationTimingGOOGLE) callconv(.c) types.VkResult {
        past_calls += 1;
        if (timings) |ptr| {
            past_request_count = count.*;
            if (count.* >= 2) {
                ptr[0] = types.VkPastPresentationTimingGOOGLE{
                    .presentID = 1,
                    .desiredPresentTime = 100,
                    .actualPresentTime = 110,
                    .earliestPresentTime = 90,
                    .presentMargin = 10,
                };
                ptr[1] = types.VkPastPresentationTimingGOOGLE{
                    .presentID = 2,
                    .desiredPresentTime = 200,
                    .actualPresentTime = 210,
                    .earliestPresentTime = 190,
                    .presentMargin = 15,
                };
                count.* = 2;
            } else if (count.* >= 1) {
                ptr[0] = types.VkPastPresentationTimingGOOGLE{
                    .presentID = 1,
                    .desiredPresentTime = 100,
                    .actualPresentTime = 110,
                    .earliestPresentTime = 90,
                    .presentMargin = 10,
                };
                count.* = 1;
            }
        } else {
            count.* = 2;
        }
        return .SUCCESS;
    }
};

test "classifyResult maps known statuses" {
    const res_ok = try classifyResult(.SUCCESS);
    try std.testing.expectEqual(Status.success, res_ok);

    const res_sub = try classifyResult(.SUBOPTIMAL_KHR);
    try std.testing.expectEqual(Status.suboptimal, res_sub);

    const res_out = try classifyResult(.ERROR_OUT_OF_DATE_KHR);
    try std.testing.expectEqual(Status.out_of_date, res_out);
}

test "selectPresentMode honors preferred when available" {
    const available = [_]types.VkPresentModeKHR{
        .FIFO,
        .FIFO_RELAXED,
        .MAILBOX,
        .IMMEDIATE,
    };
    const chosen_mailbox = selectPresentMode(&available, .mailbox);
    try std.testing.expectEqual(types.VkPresentModeKHR.MAILBOX, chosen_mailbox);

    const chosen_immediate = selectPresentMode(&available, .immediate);
    try std.testing.expectEqual(types.VkPresentModeKHR.IMMEDIATE, chosen_immediate);

    const chosen_relaxed = selectPresentMode(&available, .fifo_relaxed);
    try std.testing.expectEqual(types.VkPresentModeKHR.FIFO_RELAXED, chosen_relaxed);
}

test "selectPresentMode falls back gracefully" {
    const available = [_]types.VkPresentModeKHR{
        .FIFO,
    };
    const chosen_immediate = selectPresentMode(&available, .immediate);
    try std.testing.expectEqual(types.VkPresentModeKHR.FIFO, chosen_immediate);

    const chosen_mailbox = selectPresentMode(&available, .mailbox);
    try std.testing.expectEqual(types.VkPresentModeKHR.FIFO, chosen_mailbox);

    const chosen_relaxed = selectPresentMode(&available, .fifo_relaxed);
    try std.testing.expectEqual(types.VkPresentModeKHR.FIFO, chosen_relaxed);
}

test "presentWithOptions attaches timing when supported" {
    TestTimingCapture.reset();
    var dispatch = std.mem.zeroes(loader.DeviceDispatch);
    dispatch.queue_present = TestTimingCapture.queuePresent;
    dispatch.get_refresh_cycle_duration_google = TestTimingCapture.getRefresh;
    dispatch.get_past_presentation_timing_google = TestTimingCapture.getPastTiming;

    var swapchain = Swapchain{
        .allocator = std.testing.allocator,
        .device_handle = @as(types.VkDevice, @ptrFromInt(@as(usize, 0x10))),
        .dispatch = &dispatch,
        .allocation_callbacks = null,
        .handle = @as(types.VkSwapchainKHR, @ptrFromInt(@as(usize, 0x20))),
        .format = types.VkFormat.B8G8R8A8_UNORM,
        .color_space = types.VkColorSpaceKHR.SRGB_NONLINEAR,
        .extent = .{ .width = 1, .height = 1 },
        .image_array_layers = 1,
        .present_mode = types.VkPresentModeKHR.FIFO,
        .images = &.{},
    };

    const queue = @as(types.VkQueue, @ptrFromInt(@as(usize, 0x30)));
    try swapchain.presentWithOptions(queue, 0, .{
        .timing = .{ .present_id = 7, .desired_present_time_ns = 1234 },
    });

    try std.testing.expectEqual(@as(usize, 1), TestTimingCapture.queue_present_calls);
    try std.testing.expect(TestTimingCapture.last_has_timing);
    try std.testing.expectEqual(@as(u32, 7), TestTimingCapture.last_present_id);
    try std.testing.expectEqual(@as(u64, 1234), TestTimingCapture.last_desired_time);
}

test "presentWithOptions timing requires extension" {
    TestTimingCapture.reset();
    var dispatch = std.mem.zeroes(loader.DeviceDispatch);
    dispatch.queue_present = TestTimingCapture.queuePresent;

    var swapchain = Swapchain{
        .allocator = std.testing.allocator,
        .device_handle = @as(types.VkDevice, @ptrFromInt(@as(usize, 0x11))),
        .dispatch = &dispatch,
        .allocation_callbacks = null,
        .handle = @as(types.VkSwapchainKHR, @ptrFromInt(@as(usize, 0x21))),
        .format = types.VkFormat.B8G8R8A8_UNORM,
        .color_space = types.VkColorSpaceKHR.SRGB_NONLINEAR,
        .extent = .{ .width = 1, .height = 1 },
        .image_array_layers = 1,
        .present_mode = types.VkPresentModeKHR.FIFO,
        .images = &.{},
    };

    const queue = @as(types.VkQueue, @ptrFromInt(@as(usize, 0x31)));
    const result = swapchain.presentWithOptions(queue, 0, .{
        .timing = .{ .present_id = 1, .desired_present_time_ns = 55 },
    });
    try std.testing.expectError(errors.Error.FeatureNotPresent, result);
    try std.testing.expectEqual(@as(usize, 0), TestTimingCapture.queue_present_calls);
}

test "queryRefreshCycleDuration uses extension" {
    TestTimingCapture.reset();
    TestTimingCapture.refresh_value = 16_666_667;

    var dispatch = std.mem.zeroes(loader.DeviceDispatch);
    dispatch.get_refresh_cycle_duration_google = TestTimingCapture.getRefresh;
    dispatch.get_past_presentation_timing_google = TestTimingCapture.getPastTiming;
    dispatch.queue_present = TestTimingCapture.queuePresent;

    var swapchain = Swapchain{
        .allocator = std.testing.allocator,
        .device_handle = @as(types.VkDevice, @ptrFromInt(@as(usize, 0x12))),
        .dispatch = &dispatch,
        .allocation_callbacks = null,
        .handle = @as(types.VkSwapchainKHR, @ptrFromInt(@as(usize, 0x22))),
        .format = types.VkFormat.B8G8R8A8_UNORM,
        .color_space = types.VkColorSpaceKHR.SRGB_NONLINEAR,
        .extent = .{ .width = 1, .height = 1 },
        .image_array_layers = 1,
        .present_mode = types.VkPresentModeKHR.FIFO,
        .images = &.{},
    };

    const duration = try swapchain.queryRefreshCycleDuration();
    try std.testing.expect(duration != null);
    try std.testing.expectEqual(@as(u64, 16_666_667), duration.?);
    try std.testing.expectEqual(@as(usize, 1), TestTimingCapture.refresh_calls);
}

test "fetchPastPresentationTimings retrieves data" {
    TestTimingCapture.reset();
    var dispatch = std.mem.zeroes(loader.DeviceDispatch);
    dispatch.get_past_presentation_timing_google = TestTimingCapture.getPastTiming;
    dispatch.queue_present = TestTimingCapture.queuePresent;

    var swapchain = Swapchain{
        .allocator = std.testing.allocator,
        .device_handle = @as(types.VkDevice, @ptrFromInt(@as(usize, 0x13))),
        .dispatch = &dispatch,
        .allocation_callbacks = null,
        .handle = @as(types.VkSwapchainKHR, @ptrFromInt(@as(usize, 0x23))),
        .format = types.VkFormat.B8G8R8A8_UNORM,
        .color_space = types.VkColorSpaceKHR.SRGB_NONLINEAR,
        .extent = .{ .width = 1, .height = 1 },
        .image_array_layers = 1,
        .present_mode = types.VkPresentModeKHR.FIFO,
        .images = &.{},
    };

    const result = try swapchain.fetchPastPresentationTimings(std.testing.allocator);
    try std.testing.expect(result != null);
    var timings = result.?;
    defer timings.deinit();
    try std.testing.expectEqual(@as(usize, 2), timings.valid_count);
    const slice = timings.slice();
    try std.testing.expectEqual(@as(u32, 1), slice[0].presentID);
    try std.testing.expectEqual(@as(u64, 210), slice[1].actualPresentTime);
    try std.testing.expectEqual(@as(usize, 2), TestTimingCapture.past_calls);
}
