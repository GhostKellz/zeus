//! Command buffer recycling to reduce allocation overhead
//!
//! Maintains pools of command buffers that can be reset and reused

const std = @import("std");
const types = @import("types.zig");

const log = std.log.scoped(.command_recycler);

pub const CommandBufferPool = struct {
    allocator: std.mem.Allocator,
    device_dispatch: *const anyopaque, // DeviceDispatch
    device: types.VkDevice,
    command_pool: types.VkCommandPool,
    available_buffers: std.ArrayList(types.VkCommandBuffer),
    in_use_buffers: std.ArrayList(types.VkCommandBuffer),
    mutex: std.Thread.Mutex,
    total_allocated: u64,
    total_reused: u64,

    pub fn init(
        allocator: std.mem.Allocator,
        device_dispatch: *const anyopaque,
        device: types.VkDevice,
        command_pool: types.VkCommandPool,
    ) CommandBufferPool {
        return .{
            .allocator = allocator,
            .device_dispatch = device_dispatch,
            .device = device,
            .command_pool = command_pool,
            .available_buffers = std.ArrayList(types.VkCommandBuffer).init(allocator),
            .in_use_buffers = std.ArrayList(types.VkCommandBuffer).init(allocator),
            .mutex = .{},
            .total_allocated = 0,
            .total_reused = 0,
        };
    }

    pub fn deinit(self: *CommandBufferPool) void {
        self.available_buffers.deinit();
        self.in_use_buffers.deinit();
    }

    /// Acquire a command buffer (allocate or reuse)
    pub fn acquire(self: *CommandBufferPool) !types.VkCommandBuffer {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Try to reuse an available buffer
        if (self.available_buffers.items.len > 0) {
            const buffer = self.available_buffers.pop();
            try self.in_use_buffers.append(buffer);
            self.total_reused += 1;
            log.debug("Reused command buffer (available: {})", .{self.available_buffers.items.len});
            return buffer;
        }

        // Allocate new buffer
        log.debug("Allocating new command buffer", .{});
        self.total_allocated += 1;
        return error.NotImplemented; // Would allocate here
    }

    /// Release a command buffer back to the pool
    pub fn release(self: *CommandBufferPool, buffer: types.VkCommandBuffer) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Find and remove from in-use list
        for (self.in_use_buffers.items, 0..) |b, i| {
            if (@intFromPtr(b) == @intFromPtr(buffer)) {
                _ = self.in_use_buffers.swapRemove(i);
                try self.available_buffers.append(buffer);
                log.debug("Released command buffer (available: {})", .{self.available_buffers.items.len});
                return;
            }
        }

        log.warn("Attempted to release unknown command buffer", .{});
    }

    pub fn printStatistics(self: *CommandBufferPool) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        log.info("=== Command Buffer Pool Statistics ===", .{});
        log.info("Total allocated: {}", .{self.total_allocated});
        log.info("Total reused: {}", .{self.total_reused});
        log.info("Available: {}", .{self.available_buffers.items.len});
        log.info("In use: {}", .{self.in_use_buffers.items.len});

        if (self.total_allocated > 0) {
            const reuse_rate = (@as(f64, @floatFromInt(self.total_reused)) /
                               @as(f64, @floatFromInt(self.total_allocated + self.total_reused))) * 100.0;
            log.info("Reuse rate: {d:.1}%", .{reuse_rate});
        }
        log.info("", .{});
    }
};
