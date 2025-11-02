//! Pipeline barrier helper for automatic layout transitions and synchronization

const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");

const log = std.log.scoped(.barrier_helper);

/// Image layout transition info
pub const ImageTransition = struct {
    image: types.VkImage,
    old_layout: types.VkImageLayout,
    new_layout: types.VkImageLayout,
    aspect_mask: types.VkImageAspectFlags,
    base_mip_level: u32 = 0,
    level_count: u32 = 1,
    base_array_layer: u32 = 0,
    layer_count: u32 = 1,
};

/// Buffer barrier info
pub const BufferBarrier = struct {
    buffer: types.VkBuffer,
    offset: types.VkDeviceSize = 0,
    size: types.VkDeviceSize = types.VK_WHOLE_SIZE,
    src_access: types.VkAccessFlags,
    dst_access: types.VkAccessFlags,
};

/// Automatic pipeline stage and access mask inference
pub fn inferPipelineStageAndAccess(layout: types.VkImageLayout) struct {
    stage: types.VkPipelineStageFlags,
    access: types.VkAccessFlags,
} {
    return switch (layout) {
        .UNDEFINED => .{
            .stage = types.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            .access = 0,
        },
        .PREINITIALIZED => .{
            .stage = types.VK_PIPELINE_STAGE_HOST_BIT,
            .access = types.VK_ACCESS_HOST_WRITE_BIT,
        },
        .TRANSFER_SRC_OPTIMAL => .{
            .stage = types.VK_PIPELINE_STAGE_TRANSFER_BIT,
            .access = types.VK_ACCESS_TRANSFER_READ_BIT,
        },
        .TRANSFER_DST_OPTIMAL => .{
            .stage = types.VK_PIPELINE_STAGE_TRANSFER_BIT,
            .access = types.VK_ACCESS_TRANSFER_WRITE_BIT,
        },
        .SHADER_READ_ONLY_OPTIMAL => .{
            .stage = types.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
            .access = types.VK_ACCESS_SHADER_READ_BIT,
        },
        .COLOR_ATTACHMENT_OPTIMAL => .{
            .stage = types.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .access = types.VK_ACCESS_COLOR_ATTACHMENT_READ_BIT | types.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        },
        .DEPTH_STENCIL_ATTACHMENT_OPTIMAL => .{
            .stage = types.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
            .access = types.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT | types.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
        },
        .DEPTH_STENCIL_READ_ONLY_OPTIMAL => .{
            .stage = types.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
            .access = types.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT,
        },
        .PRESENT_SRC_KHR => .{
            .stage = types.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
            .access = 0,
        },
        .GENERAL => .{
            .stage = types.VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
            .access = types.VK_ACCESS_MEMORY_READ_BIT | types.VK_ACCESS_MEMORY_WRITE_BIT,
        },
        else => .{
            .stage = types.VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
            .access = types.VK_ACCESS_MEMORY_READ_BIT | types.VK_ACCESS_MEMORY_WRITE_BIT,
        },
    };
}

/// Transition image layout with automatic pipeline stage inference
pub fn transitionImageLayout(
    device: *device_mod.Device,
    command_buffer: types.VkCommandBuffer,
    transition: ImageTransition,
) void {
    const src_info = inferPipelineStageAndAccess(transition.old_layout);
    const dst_info = inferPipelineStageAndAccess(transition.new_layout);

    const barrier = types.VkImageMemoryBarrier{
        .srcAccessMask = src_info.access,
        .dstAccessMask = dst_info.access,
        .oldLayout = transition.old_layout,
        .newLayout = transition.new_layout,
        .srcQueueFamilyIndex = types.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = types.VK_QUEUE_FAMILY_IGNORED,
        .image = transition.image,
        .subresourceRange = .{
            .aspectMask = transition.aspect_mask,
            .baseMipLevel = transition.base_mip_level,
            .levelCount = transition.level_count,
            .baseArrayLayer = transition.base_array_layer,
            .layerCount = transition.layer_count,
        },
    };

    device.dispatch.cmd_pipeline_barrier(
        command_buffer,
        src_info.stage,
        dst_info.stage,
        0, // dependency flags
        0,
        null, // memory barriers
        0,
        null, // buffer barriers
        1,
        @ptrCast(&barrier),
    );

    log.debug("Image layout transition: {s} -> {s}", .{
        @tagName(transition.old_layout),
        @tagName(transition.new_layout),
    });
}

/// Insert buffer memory barrier
pub fn bufferBarrier(
    device: *device_mod.Device,
    command_buffer: types.VkCommandBuffer,
    barrier: BufferBarrier,
    src_stage: types.VkPipelineStageFlags,
    dst_stage: types.VkPipelineStageFlags,
) void {
    const buffer_barrier = types.VkBufferMemoryBarrier{
        .srcAccessMask = barrier.src_access,
        .dstAccessMask = barrier.dst_access,
        .srcQueueFamilyIndex = types.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = types.VK_QUEUE_FAMILY_IGNORED,
        .buffer = barrier.buffer,
        .offset = barrier.offset,
        .size = barrier.size,
    };

    device.dispatch.cmd_pipeline_barrier(
        command_buffer,
        src_stage,
        dst_stage,
        0,
        0,
        null,
        1,
        @ptrCast(&buffer_barrier),
        0,
        null,
    );
}

/// Common layout transitions as convenience functions

/// Transition image for transfer source
pub fn transitionToTransferSrc(
    device: *device_mod.Device,
    command_buffer: types.VkCommandBuffer,
    image: types.VkImage,
    old_layout: types.VkImageLayout,
    aspect_mask: types.VkImageAspectFlags,
) void {
    transitionImageLayout(device, command_buffer, .{
        .image = image,
        .old_layout = old_layout,
        .new_layout = .TRANSFER_SRC_OPTIMAL,
        .aspect_mask = aspect_mask,
    });
}

/// Transition image for transfer destination
pub fn transitionToTransferDst(
    device: *device_mod.Device,
    command_buffer: types.VkCommandBuffer,
    image: types.VkImage,
    old_layout: types.VkImageLayout,
    aspect_mask: types.VkImageAspectFlags,
) void {
    transitionImageLayout(device, command_buffer, .{
        .image = image,
        .old_layout = old_layout,
        .new_layout = .TRANSFER_DST_OPTIMAL,
        .aspect_mask = aspect_mask,
    });
}

/// Transition image for shader read
pub fn transitionToShaderRead(
    device: *device_mod.Device,
    command_buffer: types.VkCommandBuffer,
    image: types.VkImage,
    old_layout: types.VkImageLayout,
    aspect_mask: types.VkImageAspectFlags,
) void {
    transitionImageLayout(device, command_buffer, .{
        .image = image,
        .old_layout = old_layout,
        .new_layout = .SHADER_READ_ONLY_OPTIMAL,
        .aspect_mask = aspect_mask,
    });
}

/// Transition image for color attachment
pub fn transitionToColorAttachment(
    device: *device_mod.Device,
    command_buffer: types.VkCommandBuffer,
    image: types.VkImage,
    old_layout: types.VkImageLayout,
) void {
    transitionImageLayout(device, command_buffer, .{
        .image = image,
        .old_layout = old_layout,
        .new_layout = .COLOR_ATTACHMENT_OPTIMAL,
        .aspect_mask = types.VK_IMAGE_ASPECT_COLOR_BIT,
    });
}

/// Transition image for depth attachment
pub fn transitionToDepthAttachment(
    device: *device_mod.Device,
    command_buffer: types.VkCommandBuffer,
    image: types.VkImage,
    old_layout: types.VkImageLayout,
) void {
    transitionImageLayout(device, command_buffer, .{
        .image = image,
        .old_layout = old_layout,
        .new_layout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        .aspect_mask = types.VK_IMAGE_ASPECT_DEPTH_BIT,
    });
}

/// Transition image for presentation
pub fn transitionToPresent(
    device: *device_mod.Device,
    command_buffer: types.VkCommandBuffer,
    image: types.VkImage,
    old_layout: types.VkImageLayout,
) void {
    transitionImageLayout(device, command_buffer, .{
        .image = image,
        .old_layout = old_layout,
        .new_layout = .PRESENT_SRC_KHR,
        .aspect_mask = types.VK_IMAGE_ASPECT_COLOR_BIT,
    });
}
