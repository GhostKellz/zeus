/// Helper for one-time command submission (immediate execution)
/// Useful for uploading data, layout transitions, etc.
const std = @import("std");
const types = @import("types.zig");
const loader = @import("loader.zig");

/// Execute a one-time command immediately and wait for completion
pub fn execute(
    device: types.VkDevice,
    device_dispatch: *const loader.DeviceDispatch,
    queue: types.VkQueue,
    command_pool: types.VkCommandPool,
    comptime CommandFn: type,
    record_fn: CommandFn,
) !void {
    // Allocate command buffer
    const alloc_info = types.VkCommandBufferAllocateInfo{
        .command_pool = command_pool,
        .level = .primary,
        .command_buffer_count = 1,
    };

    var cmd_buffer: types.VkCommandBuffer = undefined;
    const alloc_result = device_dispatch.allocate_command_buffers(device, &alloc_info, &cmd_buffer);
    if (alloc_result != .success) return error.CommandBufferAllocationFailed;
    defer device_dispatch.free_command_buffers(device, command_pool, 1, &cmd_buffer);

    // Begin command buffer
    const begin_info = types.VkCommandBufferBeginInfo{
        .flags = @intFromEnum(types.VkCommandBufferUsageFlagBits.one_time_submit),
    };

    var result = device_dispatch.begin_command_buffer(cmd_buffer, &begin_info);
    if (result != .success) return error.CommandBufferBeginFailed;

    // Record commands via callback
    record_fn(cmd_buffer);

    // End command buffer
    result = device_dispatch.end_command_buffer(cmd_buffer);
    if (result != .success) return error.CommandBufferEndFailed;

    // Submit and wait
    const submit_info = types.VkSubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = &cmd_buffer,
    };

    result = device_dispatch.queue_submit(queue, 1, &submit_info, .null_handle);
    if (result != .success) return error.QueueSubmitFailed;

    result = device_dispatch.queue_wait_idle(queue);
    if (result != .success) return error.QueueWaitIdleFailed;
}

/// Scoped one-time command helper with automatic cleanup
pub const OneTimeCommand = struct {
    device: types.VkDevice,
    device_dispatch: *const loader.DeviceDispatch,
    queue: types.VkQueue,
    command_pool: types.VkCommandPool,
    cmd_buffer: types.VkCommandBuffer,

    /// Begin recording a one-time command
    pub fn begin(
        device: types.VkDevice,
        device_dispatch: *const loader.DeviceDispatch,
        queue: types.VkQueue,
        command_pool: types.VkCommandPool,
    ) !OneTimeCommand {
        const alloc_info = types.VkCommandBufferAllocateInfo{
            .command_pool = command_pool,
            .level = .primary,
            .command_buffer_count = 1,
        };

        var cmd_buffer: types.VkCommandBuffer = undefined;
        const alloc_result = device_dispatch.allocate_command_buffers(device, &alloc_info, &cmd_buffer);
        if (alloc_result != .success) return error.CommandBufferAllocationFailed;
        errdefer device_dispatch.free_command_buffers(device, command_pool, 1, &cmd_buffer);

        const begin_info = types.VkCommandBufferBeginInfo{
            .flags = @intFromEnum(types.VkCommandBufferUsageFlagBits.one_time_submit),
        };

        const result = device_dispatch.begin_command_buffer(cmd_buffer, &begin_info);
        if (result != .success) return error.CommandBufferBeginFailed;

        return OneTimeCommand{
            .device = device,
            .device_dispatch = device_dispatch,
            .queue = queue,
            .command_pool = command_pool,
            .cmd_buffer = cmd_buffer,
        };
    }

    /// Get the command buffer for recording
    pub fn commandBuffer(self: *OneTimeCommand) types.VkCommandBuffer {
        return self.cmd_buffer;
    }

    /// Submit and wait for completion, then cleanup
    pub fn submit(self: *OneTimeCommand) !void {
        var result = self.device_dispatch.end_command_buffer(self.cmd_buffer);
        if (result != .success) return error.CommandBufferEndFailed;

        const submit_info = types.VkSubmitInfo{
            .command_buffer_count = 1,
            .p_command_buffers = &self.cmd_buffer,
        };

        result = self.device_dispatch.queue_submit(self.queue, 1, &submit_info, .null_handle);
        if (result != .success) return error.QueueSubmitFailed;

        result = self.device_dispatch.queue_wait_idle(self.queue);
        if (result != .success) return error.QueueWaitIdleFailed;

        self.device_dispatch.free_command_buffers(self.device, self.command_pool, 1, &self.cmd_buffer);
    }
};

/// Helper for common immediate operations
pub const ImmediateCommands = struct {
    device: types.VkDevice,
    device_dispatch: *const loader.DeviceDispatch,
    queue: types.VkQueue,
    command_pool: types.VkCommandPool,

    pub fn init(
        device: types.VkDevice,
        device_dispatch: *const loader.DeviceDispatch,
        queue: types.VkQueue,
        command_pool: types.VkCommandPool,
    ) ImmediateCommands {
        return ImmediateCommands{
            .device = device,
            .device_dispatch = device_dispatch,
            .queue = queue,
            .command_pool = command_pool,
        };
    }

    /// Copy buffer immediately
    pub fn copyBuffer(
        self: *ImmediateCommands,
        src: types.VkBuffer,
        dst: types.VkBuffer,
        size: u64,
    ) !void {
        const RecordFn = struct {
            fn record(cmd: types.VkCommandBuffer, dd: *const loader.DeviceDispatch, s: types.VkBuffer, d: types.VkBuffer, sz: u64) void {
                const region = types.VkBufferCopy{
                    .src_offset = 0,
                    .dst_offset = 0,
                    .size = sz,
                };
                dd.cmd_copy_buffer(cmd, s, d, 1, &region);
            }
        };

        var cmd = try OneTimeCommand.begin(self.device, self.device_dispatch, self.queue, self.command_pool);
        RecordFn.record(cmd.commandBuffer(), self.device_dispatch, src, dst, size);
        try cmd.submit();
    }

    /// Transition image layout immediately
    pub fn transitionImageLayout(
        self: *ImmediateCommands,
        image: types.VkImage,
        old_layout: types.VkImageLayout,
        new_layout: types.VkImageLayout,
        aspect_mask: types.VkImageAspectFlags,
    ) !void {
        const RecordFn = struct {
            fn record(
                cmd: types.VkCommandBuffer,
                dd: *const loader.DeviceDispatch,
                img: types.VkImage,
                old: types.VkImageLayout,
                new: types.VkImageLayout,
                aspect: types.VkImageAspectFlags,
            ) void {
                const src_access = accessMaskForLayout(old);
                const dst_access = accessMaskForLayout(new);
                const src_stage = stageMaskForLayout(old);
                const dst_stage = stageMaskForLayout(new);

                const barrier = types.VkImageMemoryBarrier{
                    .old_layout = old,
                    .new_layout = new,
                    .src_queue_family_index = types.VK_QUEUE_FAMILY_IGNORED,
                    .dst_queue_family_index = types.VK_QUEUE_FAMILY_IGNORED,
                    .image = img,
                    .subresource_range = types.VkImageSubresourceRange{
                        .aspect_mask = aspect,
                        .base_mip_level = 0,
                        .level_count = 1,
                        .base_array_layer = 0,
                        .layer_count = 1,
                    },
                    .src_access_mask = src_access,
                    .dst_access_mask = dst_access,
                };

                dd.cmd_pipeline_barrier(
                    cmd,
                    src_stage,
                    dst_stage,
                    0,
                    0,
                    null,
                    0,
                    null,
                    1,
                    &barrier,
                );
            }
        };

        var cmd = try OneTimeCommand.begin(self.device, self.device_dispatch, self.queue, self.command_pool);
        RecordFn.record(cmd.commandBuffer(), self.device_dispatch, image, old_layout, new_layout, aspect_mask);
        try cmd.submit();
    }
};

/// Derive access mask from image layout
fn accessMaskForLayout(layout: types.VkImageLayout) types.VkAccessFlags {
    return switch (layout) {
        .undefined => 0,
        .general => @intFromEnum(types.VkAccessFlagBits.shader_read) |
            @intFromEnum(types.VkAccessFlagBits.shader_write),
        .color_attachment_optimal => @intFromEnum(types.VkAccessFlagBits.color_attachment_read) |
            @intFromEnum(types.VkAccessFlagBits.color_attachment_write),
        .depth_stencil_attachment_optimal => @intFromEnum(types.VkAccessFlagBits.depth_stencil_attachment_read) |
            @intFromEnum(types.VkAccessFlagBits.depth_stencil_attachment_write),
        .depth_stencil_read_only_optimal => @intFromEnum(types.VkAccessFlagBits.depth_stencil_attachment_read),
        .shader_read_only_optimal => @intFromEnum(types.VkAccessFlagBits.shader_read),
        .transfer_src_optimal => @intFromEnum(types.VkAccessFlagBits.transfer_read),
        .transfer_dst_optimal => @intFromEnum(types.VkAccessFlagBits.transfer_write),
        .preinitialized => @intFromEnum(types.VkAccessFlagBits.host_write),
        .present_src_khr => @intFromEnum(types.VkAccessFlagBits.memory_read),
        else => 0,
    };
}

/// Derive pipeline stage from image layout
fn stageMaskForLayout(layout: types.VkImageLayout) types.VkPipelineStageFlags {
    return switch (layout) {
        .undefined => @intFromEnum(types.VkPipelineStageFlagBits.top_of_pipe),
        .general => @intFromEnum(types.VkPipelineStageFlagBits.all_commands),
        .color_attachment_optimal => @intFromEnum(types.VkPipelineStageFlagBits.color_attachment_output),
        .depth_stencil_attachment_optimal => @intFromEnum(types.VkPipelineStageFlagBits.early_fragment_tests) |
            @intFromEnum(types.VkPipelineStageFlagBits.late_fragment_tests),
        .depth_stencil_read_only_optimal => @intFromEnum(types.VkPipelineStageFlagBits.early_fragment_tests) |
            @intFromEnum(types.VkPipelineStageFlagBits.late_fragment_tests),
        .shader_read_only_optimal => @intFromEnum(types.VkPipelineStageFlagBits.fragment_shader),
        .transfer_src_optimal => @intFromEnum(types.VkPipelineStageFlagBits.transfer),
        .transfer_dst_optimal => @intFromEnum(types.VkPipelineStageFlagBits.transfer),
        .preinitialized => @intFromEnum(types.VkPipelineStageFlagBits.host),
        .present_src_khr => @intFromEnum(types.VkPipelineStageFlagBits.bottom_of_pipe),
        else => @intFromEnum(types.VkPipelineStageFlagBits.all_commands),
    };
}
