//! Immediate submit helper for one-shot command buffers

const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const command_manager = @import("command_manager.zig");
const commands = @import("commands.zig");

const log = std.log.scoped(.immediate_submit);

/// Context for immediate command submission
pub const ImmediateContext = struct {
    device: *device_mod.Device,
    queue: types.VkQueue,
    pool: commands.CommandPool,
    command_buffer: types.VkCommandBuffer,
    fence: types.VkFence,

    pub fn init(device: *device_mod.Device, queue: types.VkQueue, queue_family: u32) !ImmediateContext {
        const pool = try commands.CommandPool.create(device, .{
            .queue_family_index = queue_family,
            .flags = types.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        });
        errdefer pool.destroy();

        const cmd = try pool.allocateOne(.PRIMARY);

        const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;
        const fence_info = types.VkFenceCreateInfo{
            .flags = 0,
        };
        var fence: types.VkFence = undefined;
        try errors.ensureSuccess(device.dispatch.create_fence(device_handle, &fence_info, device.allocation_callbacks, &fence));

        return ImmediateContext{
            .device = device,
            .queue = queue,
            .pool = pool,
            .command_buffer = cmd,
            .fence = fence,
        };
    }

    pub fn deinit(self: *ImmediateContext) void {
        const device_handle = self.device.handle orelse return;
        self.device.dispatch.destroy_fence(device_handle, self.fence, self.device.allocation_callbacks);
        self.pool.destroy();
    }

    /// Submit a single command immediately and wait
    pub fn submit(self: *ImmediateContext, callback: anytype) !void {
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;

        try errors.ensureSuccess(self.device.dispatch.reset_command_buffer(self.command_buffer, 0));
        try errors.ensureSuccess(self.device.dispatch.reset_fences(device_handle, 1, @ptrCast(&self.fence)));

        const begin_info = types.VkCommandBufferBeginInfo{
            .flags = types.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            .pInheritanceInfo = null,
        };

        try errors.ensureSuccess(self.device.dispatch.begin_command_buffer(self.command_buffer, &begin_info));

        try callback(self.command_buffer);

        try errors.ensureSuccess(self.device.dispatch.end_command_buffer(self.command_buffer));

        const submit_info = types.VkSubmitInfo{
            .commandBufferCount = 1,
            .pCommandBuffers = &self.command_buffer,
            .waitSemaphoreCount = 0,
            .pWaitSemaphores = null,
            .pWaitDstStageMask = null,
            .signalSemaphoreCount = 0,
            .pSignalSemaphores = null,
        };

        try errors.ensureSuccess(self.device.dispatch.queue_submit(self.queue, 1, @ptrCast(&submit_info), self.fence));
        try errors.ensureSuccess(self.device.dispatch.wait_for_fences(device_handle, 1, @ptrCast(&self.fence), 1, std.math.maxInt(u64)));
    }
};

/// One-shot immediate submit (allocates everything on the fly)
pub fn immediate(
    device: *device_mod.Device,
    queue: types.VkQueue,
    queue_family: u32,
    callback: anytype,
) !void {
    var ctx = try ImmediateContext.init(device, queue, queue_family);
    defer ctx.deinit();
    try ctx.submit(callback);
}
