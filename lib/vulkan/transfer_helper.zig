//! Transfer queue helper for async buffer and image uploads

const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const buffer_allocator = @import("buffer_allocator.zig");
const image_allocator = @import("image_allocator.zig");
const command_manager = @import("command_manager.zig");
const sync_manager = @import("sync_manager.zig");
const barrier_helper = @import("barrier_helper.zig");

const log = std.log.scoped(.transfer_helper);

/// Transfer operation for batch submission
pub const TransferOp = union(enum) {
    buffer_to_buffer: struct {
        src: types.VkBuffer,
        dst: types.VkBuffer,
        regions: []const types.VkBufferCopy,
    },
    buffer_to_image: struct {
        src: types.VkBuffer,
        dst: types.VkImage,
        dst_layout: types.VkImageLayout,
        regions: []const types.VkBufferImageCopy,
    },
    image_to_buffer: struct {
        src: types.VkImage,
        src_layout: types.VkImageLayout,
        dst: types.VkBuffer,
        regions: []const types.VkBufferImageCopy,
    },
    image_to_image: struct {
        src: types.VkImage,
        src_layout: types.VkImageLayout,
        dst: types.VkImage,
        dst_layout: types.VkImageLayout,
        regions: []const types.VkImageCopy,
    },
};

/// Pending transfer batch
pub const TransferBatch = struct {
    allocator: std.mem.Allocator,
    operations: std.ArrayList(TransferOp),
    command_buffer: ?types.VkCommandBuffer,
    fence: ?types.VkFence,
    submitted: bool,

    pub fn init(allocator: std.mem.Allocator) TransferBatch {
        return .{
            .allocator = allocator,
            .operations = std.ArrayList(TransferOp).init(allocator),
            .command_buffer = null,
            .fence = null,
            .submitted = false,
        };
    }

    pub fn deinit(self: *TransferBatch) void {
        self.operations.deinit();
    }

    pub fn addBufferCopy(
        self: *TransferBatch,
        src: types.VkBuffer,
        dst: types.VkBuffer,
        regions: []const types.VkBufferCopy,
    ) !void {
        try self.operations.append(.{
            .buffer_to_buffer = .{
                .src = src,
                .dst = dst,
                .regions = regions,
            },
        });
    }

    pub fn addBufferToImage(
        self: *TransferBatch,
        src: types.VkBuffer,
        dst: types.VkImage,
        dst_layout: types.VkImageLayout,
        regions: []const types.VkBufferImageCopy,
    ) !void {
        try self.operations.append(.{
            .buffer_to_image = .{
                .src = src,
                .dst = dst,
                .dst_layout = dst_layout,
                .regions = regions,
            },
        });
    }
};

/// Transfer helper for managing async transfers
pub const TransferHelper = struct {
    allocator: std.mem.Allocator,
    device: *device_mod.Device,
    transfer_queue: types.VkQueue,
    command_mgr: *command_manager.CommandManager,
    sync_mgr: *sync_manager.SyncManager,
    pending_batches: std.ArrayList(*TransferBatch),
    completed_batches: std.ArrayList(*TransferBatch),

    pub fn init(
        allocator: std.mem.Allocator,
        device: *device_mod.Device,
        transfer_queue: types.VkQueue,
        command_mgr: *command_manager.CommandManager,
        sync_mgr: *sync_manager.SyncManager,
    ) !*TransferHelper {
        const self = try allocator.create(TransferHelper);
        self.* = .{
            .allocator = allocator,
            .device = device,
            .transfer_queue = transfer_queue,
            .command_mgr = command_mgr,
            .sync_mgr = sync_mgr,
            .pending_batches = std.ArrayList(*TransferBatch).init(allocator),
            .completed_batches = std.ArrayList(*TransferBatch).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *TransferHelper) void {
        for (self.pending_batches.items) |batch| {
            batch.deinit();
            self.allocator.destroy(batch);
        }
        for (self.completed_batches.items) |batch| {
            batch.deinit();
            self.allocator.destroy(batch);
        }
        self.pending_batches.deinit();
        self.completed_batches.deinit();
        self.allocator.destroy(self);
    }

    /// Create a new transfer batch
    pub fn createBatch(self: *TransferHelper) !*TransferBatch {
        const batch = try self.allocator.create(TransferBatch);
        batch.* = TransferBatch.init(self.allocator);
        return batch;
    }

    /// Submit a transfer batch for execution
    pub fn submitBatch(self: *TransferHelper, batch: *TransferBatch) !void {
        if (batch.operations.items.len == 0) return;

        const cmd = try self.command_mgr.allocateTransfer();
        try cmd.beginOneTime();

        for (batch.operations.items) |op| {
            switch (op) {
                .buffer_to_buffer => |copy| {
                    self.device.dispatch.cmd_copy_buffer(
                        cmd.command_buffer,
                        copy.src,
                        copy.dst,
                        @intCast(copy.regions.len),
                        @ptrCast(copy.regions.ptr),
                    );
                },
                .buffer_to_image => |copy| {
                    self.device.dispatch.cmd_copy_buffer_to_image(
                        cmd.command_buffer,
                        copy.src,
                        copy.dst,
                        copy.dst_layout,
                        @intCast(copy.regions.len),
                        @ptrCast(copy.regions.ptr),
                    );
                },
                .image_to_buffer => |copy| {
                    self.device.dispatch.cmd_copy_image_to_buffer(
                        cmd.command_buffer,
                        copy.src,
                        copy.src_layout,
                        copy.dst,
                        @intCast(copy.regions.len),
                        @ptrCast(copy.regions.ptr),
                    );
                },
                .image_to_image => |copy| {
                    self.device.dispatch.cmd_copy_image(
                        cmd.command_buffer,
                        copy.src,
                        copy.src_layout,
                        copy.dst,
                        copy.dst_layout,
                        @intCast(copy.regions.len),
                        @ptrCast(copy.regions.ptr),
                    );
                },
            }
        }

        try cmd.end();

        const fence = try self.sync_mgr.acquireFence(false);

        const submit_info = types.VkSubmitInfo{
            .commandBufferCount = 1,
            .pCommandBuffers = &cmd.command_buffer,
            .waitSemaphoreCount = 0,
            .pWaitSemaphores = null,
            .pWaitDstStageMask = null,
            .signalSemaphoreCount = 0,
            .pSignalSemaphores = null,
        };

        try errors.ensureSuccess(self.device.dispatch.queue_submit(self.transfer_queue, 1, @ptrCast(&submit_info), fence));

        batch.command_buffer = cmd.command_buffer;
        batch.fence = fence;
        batch.submitted = true;

        try self.pending_batches.append(batch);

        log.debug("Submitted transfer batch with {} operations", .{batch.operations.items.len});
    }

    /// Poll for completed transfers
    pub fn poll(self: *TransferHelper) !void {
        const device_handle = self.device.handle orelse return;

        var i: usize = 0;
        while (i < self.pending_batches.items.len) {
            const batch = self.pending_batches.items[i];
            if (batch.fence) |fence| {
                const result = self.device.dispatch.get_fence_status(device_handle, fence);
                if (result == .SUCCESS) {
                    try self.sync_mgr.releaseFence(fence);
                    try self.command_mgr.release(command_manager.ManagedCommandBuffer{
                        .device = self.device,
                        .command_buffer = batch.command_buffer.?,
                        .pool = undefined,
                        .state = .executable,
                        .level = .PRIMARY,
                    }, .transfer);

                    _ = self.pending_batches.swapRemove(i);
                    try self.completed_batches.append(batch);

                    log.debug("Transfer batch completed", .{});
                    continue;
                }
            }
            i += 1;
        }
    }

    /// Wait for all pending transfers to complete
    pub fn waitIdle(self: *TransferHelper) !void {
        try errors.ensureSuccess(self.device.dispatch.queue_wait_idle(self.transfer_queue));

        for (self.pending_batches.items) |batch| {
            if (batch.fence) |fence| {
                try self.sync_mgr.releaseFence(fence);
            }
            try self.completed_batches.append(batch);
        }

        self.pending_batches.clearRetainingCapacity();
    }

    /// Upload buffer data (convenience function)
    pub fn uploadBuffer(
        self: *TransferHelper,
        staging: *buffer_allocator.AllocatedBuffer,
        dst: *buffer_allocator.AllocatedBuffer,
        data: []const u8,
    ) !void {
        try staging.write(data, 0);

        const batch = try self.createBatch();
        const region = types.VkBufferCopy{
            .srcOffset = 0,
            .dstOffset = 0,
            .size = @intCast(data.len),
        };
        try batch.addBufferCopy(staging.buffer, dst.buffer, &[_]types.VkBufferCopy{region});
        try self.submitBatch(batch);
    }

    /// Upload image data (convenience function)
    pub fn uploadImage(
        self: *TransferHelper,
        staging: *buffer_allocator.AllocatedBuffer,
        dst: *image_allocator.AllocatedImage,
        data: []const u8,
    ) !void {
        try staging.write(data, 0);

        const batch = try self.createBatch();
        const region = types.VkBufferImageCopy{
            .bufferOffset = 0,
            .bufferRowLength = 0,
            .bufferImageHeight = 0,
            .imageSubresource = .{
                .aspectMask = types.VK_IMAGE_ASPECT_COLOR_BIT,
                .mipLevel = 0,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
            .imageOffset = .{ .x = 0, .y = 0, .z = 0 },
            .imageExtent = dst.extent,
        };
        try batch.addBufferToImage(staging.buffer, dst.image, .TRANSFER_DST_OPTIMAL, &[_]types.VkBufferImageCopy{region});
        try self.submitBatch(batch);
    }
};
