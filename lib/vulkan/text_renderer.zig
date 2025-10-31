const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const buffer = @import("buffer.zig");
const loader = @import("loader.zig");

pub const AtlasConfig = struct {
    image: types.VkImage,
    format: types.VkFormat,
    extent: types.VkExtent2D,
    mip_levels: u32 = 1,
    layer_count: u32 = 1,
    aspect_mask: types.VkImageAspectFlags = types.VK_IMAGE_ASPECT_COLOR_BIT,
    view_type: types.VkImageViewType = .@"2D",
};

pub const CreateInfo = struct {
    pipeline: types.VkPipeline,
    atlas: AtlasConfig,
    command_buffer: types.VkCommandBuffer,
    old_layout: types.VkImageLayout = .UNDEFINED,
    target_layout: types.VkImageLayout = .SHADER_READ_ONLY_OPTIMAL,
    queue_family_index: u32 = types.VK_QUEUE_FAMILY_IGNORED,
};

pub const TextRenderer = struct {
    device: *device_mod.Device,
    pipeline: types.VkPipeline,
    atlas_image: types.VkImage,
    atlas_view: types.VkImageView,
    atlas_layout: types.VkImageLayout,
    extent: types.VkExtent2D,
    subresource_range: types.VkImageSubresourceRange,
    queue_family_index: u32,

    pub fn init(device: *device_mod.Device, info: CreateInfo) errors.Error!TextRenderer {
        const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;

        const subresource_range = types.VkImageSubresourceRange{
            .aspectMask = info.atlas.aspect_mask,
            .baseMipLevel = 0,
            .levelCount = info.atlas.mip_levels,
            .baseArrayLayer = 0,
            .layerCount = info.atlas.layer_count,
        };

        const view_info = types.VkImageViewCreateInfo{
            .image = info.atlas.image,
            .viewType = info.atlas.view_type,
            .format = info.atlas.format,
            .subresourceRange = subresource_range,
        };

        var atlas_view: types.VkImageView = undefined;
        try errors.ensureSuccess(device.dispatch.create_image_view(device_handle, &view_info, device.allocation_callbacks, &atlas_view));

        const transition_opts = buffer.TransitionOptions{
            .device = device,
            .range = subresource_range,
            .src_queue_family_index = info.queue_family_index,
            .dst_queue_family_index = info.queue_family_index,
        };
        try buffer.transitionImageLayout(info.command_buffer, info.atlas.image, info.old_layout, info.target_layout, transition_opts);

        return TextRenderer{
            .device = device,
            .pipeline = info.pipeline,
            .atlas_image = info.atlas.image,
            .atlas_view = atlas_view,
            .atlas_layout = info.target_layout,
            .extent = info.atlas.extent,
            .subresource_range = subresource_range,
            .queue_family_index = info.queue_family_index,
        };
    }

    pub fn destroy(self: *TextRenderer) void {
        const device_handle = self.device.handle orelse return;
        self.device.dispatch.destroy_image_view(device_handle, self.atlas_view, self.device.allocation_callbacks);
        self.atlas_view = @as(types.VkImageView, @ptrFromInt(@as(usize, 0)));
    }

    pub fn ensureAtlasLayout(self: *TextRenderer, cmd: types.VkCommandBuffer, desired_layout: types.VkImageLayout) errors.Error!void {
        if (self.atlas_layout == desired_layout) return;
        try buffer.transitionImageLayout(cmd, self.atlas_image, self.atlas_layout, desired_layout, .{
            .device = self.device,
            .range = self.subresource_range,
            .src_queue_family_index = self.queue_family_index,
            .dst_queue_family_index = self.queue_family_index,
        });
        self.atlas_layout = desired_layout;
    }

    pub fn beginAtlasUpload(self: *TextRenderer, cmd: types.VkCommandBuffer) errors.Error!void {
        try self.ensureAtlasLayout(cmd, .TRANSFER_DST_OPTIMAL);
    }

    pub fn finishAtlasUpload(self: *TextRenderer, cmd: types.VkCommandBuffer) errors.Error!void {
        try self.ensureAtlasLayout(cmd, .SHADER_READ_ONLY_OPTIMAL);
    }

    pub fn recordDraw(self: *TextRenderer, cmd: types.VkCommandBuffer, glyph_count: u32) errors.Error!void {
        _ = glyph_count;
        try self.ensureAtlasLayout(cmd, .SHADER_READ_ONLY_OPTIMAL);
        std.debug.assert(@intFromPtr(cmd) != 0);
    }
};

const fake_device_handle = @as(types.VkDevice, @ptrFromInt(@as(usize, 0x10)));
const fake_image_view = @as(types.VkImageView, @ptrFromInt(@as(usize, 0x20)));

const Capture = struct {
    pub var create_view_info: ?types.VkImageViewCreateInfo = null;
    pub var destroy_view_handle: ?types.VkImageView = null;
    pub var last_barrier: ?types.VkImageMemoryBarrier = null;
    pub var last_src_stage: types.VkPipelineStageFlags = 0;
    pub var last_dst_stage: types.VkPipelineStageFlags = 0;
    pub var transition_count: usize = 0;

    pub fn reset() void {
        create_view_info = null;
        destroy_view_handle = null;
        last_barrier = null;
        last_src_stage = 0;
        last_dst_stage = 0;
        transition_count = 0;
    }

    pub fn stubCreateImageView(_: types.VkDevice, info: *const types.VkImageViewCreateInfo, _: ?*const types.VkAllocationCallbacks, view: *types.VkImageView) callconv(.C) types.VkResult {
        create_view_info = info.*;
        view.* = fake_image_view;
        return .SUCCESS;
    }

    pub fn stubDestroyImageView(_: types.VkDevice, view: types.VkImageView, _: ?*const types.VkAllocationCallbacks) callconv(.C) void {
        destroy_view_handle = view;
    }

    pub fn stubPipelineBarrier(_: types.VkCommandBuffer, src_stage: types.VkPipelineStageFlags, dst_stage: types.VkPipelineStageFlags, _: types.VkDependencyFlags, _: u32, _: ?[*]const types.VkMemoryBarrier, _: u32, _: ?[*]const types.VkBufferMemoryBarrier, count: u32, barriers: ?[*]const types.VkImageMemoryBarrier) callconv(.C) void {
        std.debug.assert(count == 1);
        last_barrier = barriers.?[0];
        last_src_stage = src_stage;
        last_dst_stage = dst_stage;
        transition_count += 1;
    }
};

fn makeDevice() device_mod.Device {
    return device_mod.Device{
        .allocator = std.testing.allocator,
        .loader = undefined,
        .dispatch = std.mem.zeroes(loader.DeviceDispatch),
        .handle = fake_device_handle,
        .allocation_callbacks = null,
    };
}

test "TextRenderer init creates image view and transitions atlas" {
    Capture.reset();
    var device = makeDevice();
    device.dispatch.create_image_view = Capture.stubCreateImageView;
    device.dispatch.destroy_image_view = Capture.stubDestroyImageView;
    device.dispatch.cmd_pipeline_barrier = Capture.stubPipelineBarrier;

    const extent = types.VkExtent2D{ .width = 512, .height = 256 };
    const renderer = try TextRenderer.init(&device, .{
        .pipeline = @as(types.VkPipeline, @ptrFromInt(@as(usize, 0x30))),
        .atlas = .{
            .image = @as(types.VkImage, @ptrFromInt(@as(usize, 0x40))),
            .format = .R8G8B8A8_UNORM,
            .extent = extent,
        },
        .command_buffer = @as(types.VkCommandBuffer, @ptrFromInt(@as(usize, 0x50))),
    });

    const view_info = Capture.create_view_info orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(extent, renderer.extent);
    try std.testing.expectEqual(extent, renderer.extent);
    try std.testing.expectEqual(@as(types.VkImageViewType, .@"2D"), view_info.viewType);
    try std.testing.expectEqual(types.VK_IMAGE_ASPECT_COLOR_BIT, view_info.subresourceRange.aspectMask);
    try std.testing.expectEqual(types.VkImageLayout.SHADER_READ_ONLY_OPTIMAL, renderer.atlas_layout);
    try std.testing.expectEqual(@as(usize, 1), Capture.transition_count);
}

test "ensureAtlasLayout only transitions when required" {
    Capture.reset();
    var device = makeDevice();
    device.dispatch.create_image_view = Capture.stubCreateImageView;
    device.dispatch.destroy_image_view = Capture.stubDestroyImageView;
    device.dispatch.cmd_pipeline_barrier = Capture.stubPipelineBarrier;

    var renderer = try TextRenderer.init(&device, .{
        .pipeline = @as(types.VkPipeline, @ptrFromInt(@as(usize, 0x31))),
        .atlas = .{
            .image = @as(types.VkImage, @ptrFromInt(@as(usize, 0x41))),
            .format = .R8G8B8A8_UNORM,
            .extent = types.VkExtent2D{ .width = 1024, .height = 1024 },
        },
        .command_buffer = @as(types.VkCommandBuffer, @ptrFromInt(@as(usize, 0x51))),
    });

    try renderer.beginAtlasUpload(@as(types.VkCommandBuffer, @ptrFromInt(@as(usize, 0x60))));
    try std.testing.expectEqual(types.VkImageLayout.TRANSFER_DST_OPTIMAL, renderer.atlas_layout);
    try renderer.beginAtlasUpload(@as(types.VkCommandBuffer, @ptrFromInt(@as(usize, 0x61))));
    try std.testing.expectEqual(@as(usize, 2), Capture.transition_count);
    try renderer.finishAtlasUpload(@as(types.VkCommandBuffer, @ptrFromInt(@as(usize, 0x62))));
    try std.testing.expectEqual(types.VkImageLayout.SHADER_READ_ONLY_OPTIMAL, renderer.atlas_layout);
    try std.testing.expectEqual(@as(usize, 3), Capture.transition_count);
}

test "destroy releases image view" {
    Capture.reset();
    var device = makeDevice();
    device.dispatch.create_image_view = Capture.stubCreateImageView;
    device.dispatch.destroy_image_view = Capture.stubDestroyImageView;
    device.dispatch.cmd_pipeline_barrier = Capture.stubPipelineBarrier;

    var renderer = try TextRenderer.init(&device, .{
        .pipeline = @as(types.VkPipeline, @ptrFromInt(@as(usize, 0x32))),
        .atlas = .{
            .image = @as(types.VkImage, @ptrFromInt(@as(usize, 0x42))),
            .format = .R8G8B8A8_UNORM,
            .extent = types.VkExtent2D{ .width = 256, .height = 256 },
        },
        .command_buffer = @as(types.VkCommandBuffer, @ptrFromInt(@as(usize, 0x52))),
    });

    renderer.destroy();
    try std.testing.expectEqual(fake_image_view, Capture.destroy_view_handle.?);
}
