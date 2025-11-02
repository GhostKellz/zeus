//! Command pool manager with per-queue, per-thread pools and recycling

const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const commands = @import("commands.zig");

const log = std.log.scoped(.command_manager);

/// Command buffer state for tracking
pub const CommandBufferState = enum {
    initial,
    recording,
    executable,
    pending,
    invalid,
};

/// Managed command buffer with state tracking and RAII
pub const ManagedCommandBuffer = struct {
    device: *device_mod.Device,
    command_buffer: types.VkCommandBuffer,
    pool: *commands.CommandPool,
    state: CommandBufferState,
    level: types.VkCommandBufferLevel,

    /// Begin recording (RAII pattern)
    pub fn begin(self: *ManagedCommandBuffer, usage: types.VkCommandBufferUsageFlags) !void {
        if (self.state != .initial and self.state != .executable) {
            return errors.Error.InvalidState;
        }

        try commands.beginCommandBuffer(self.device, self.command_buffer, usage, null);
        self.state = .recording;
    }

    /// Begin one-time submit recording
    pub fn beginOneTime(self: *ManagedCommandBuffer) !void {
        try self.begin(types.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT);
    }

    /// Begin reusable recording
    pub fn beginReusable(self: *ManagedCommandBuffer) !void {
        try self.begin(0);
    }

    /// End recording
    pub fn end(self: *ManagedCommandBuffer) !void {
        if (self.state != .recording) {
            return errors.Error.InvalidState;
        }

        try commands.endCommandBuffer(self.device, self.command_buffer);
        self.state = .executable;
    }

    /// Reset command buffer (if pool allows)
    pub fn reset(self: *ManagedCommandBuffer, flags: types.VkCommandBufferResetFlags) !void {
        if (self.state == .pending) {
            return errors.Error.InvalidState;
        }

        try errors.ensureSuccess(self.device.dispatch.reset_command_buffer(self.command_buffer, flags));
        self.state = .initial;
    }

    /// Get raw command buffer handle
    pub fn handle(self: *ManagedCommandBuffer) types.VkCommandBuffer {
        return self.command_buffer;
    }

    /// Scoped recording helper (RAII)
    pub fn record(self: *ManagedCommandBuffer, callback: anytype) !void {
        try self.beginOneTime();
        errdefer _ = self.device.dispatch.end_command_buffer(self.command_buffer);

        try callback(self.command_buffer);

        try self.end();
    }
};

/// Per-thread command pool
pub const ThreadCommandPool = struct {
    pool: commands.CommandPool,
    allocated_buffers: std.ArrayList(types.VkCommandBuffer),
    free_buffers: std.ArrayList(types.VkCommandBuffer),
    thread_id: std.Thread.Id,

    pub fn init(allocator: std.mem.Allocator, device: *device_mod.Device, queue_family: u32, thread_id: std.Thread.Id) !*ThreadCommandPool {
        const self = try allocator.create(ThreadCommandPool);
        self.* = .{
            .pool = try commands.CommandPool.create(device, .{
                .queue_family_index = queue_family,
                .flags = types.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            }),
            .allocated_buffers = std.ArrayList(types.VkCommandBuffer).init(allocator),
            .free_buffers = std.ArrayList(types.VkCommandBuffer).init(allocator),
            .thread_id = thread_id,
        };
        return self;
    }

    pub fn deinit(self: *ThreadCommandPool, allocator: std.mem.Allocator) void {
        self.pool.destroy();
        self.allocated_buffers.deinit();
        self.free_buffers.deinit();
        allocator.destroy(self);
    }

    /// Allocate or recycle a command buffer
    pub fn acquire(self: *ThreadCommandPool) !types.VkCommandBuffer {
        // Try to recycle first
        if (self.free_buffers.popOrNull()) |buffer| {
            try errors.ensureSuccess(self.pool.device.dispatch.reset_command_buffer(buffer, 0));
            return buffer;
        }

        // Allocate new
        const buffer = try self.pool.allocateOne(.PRIMARY);
        try self.allocated_buffers.append(buffer);
        return buffer;
    }

    /// Return command buffer to pool for recycling
    pub fn release(self: *ThreadCommandPool, buffer: types.VkCommandBuffer) !void {
        try self.free_buffers.append(buffer);
    }

    /// Reset all command buffers in the pool
    pub fn resetAll(self: *ThreadCommandPool) !void {
        try self.pool.reset(0);
        self.free_buffers.clearRetainingCapacity();
        try self.free_buffers.appendSlice(self.allocated_buffers.items);
    }
};

/// Command pool manager for a specific queue family
pub const QueueCommandManager = struct {
    allocator: std.mem.Allocator,
    device: *device_mod.Device,
    queue_family: u32,
    thread_pools: std.AutoHashMap(std.Thread.Id, *ThreadCommandPool),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, device: *device_mod.Device, queue_family: u32) !*QueueCommandManager {
        const self = try allocator.create(QueueCommandManager);
        self.* = .{
            .allocator = allocator,
            .device = device,
            .queue_family = queue_family,
            .thread_pools = std.AutoHashMap(std.Thread.Id, *ThreadCommandPool).init(allocator),
            .mutex = .{},
        };
        return self;
    }

    pub fn deinit(self: *QueueCommandManager) void {
        var it = self.thread_pools.valueIterator();
        while (it.next()) |pool| {
            pool.*.deinit(self.allocator);
        }
        self.thread_pools.deinit();
        self.allocator.destroy(self);
    }

    /// Get or create thread-local command pool
    pub fn getThreadPool(self: *QueueCommandManager) !*ThreadCommandPool {
        const thread_id = std.Thread.getCurrentId();

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.thread_pools.get(thread_id)) |pool| {
            return pool;
        }

        const pool = try ThreadCommandPool.init(self.allocator, self.device, self.queue_family, thread_id);
        try self.thread_pools.put(thread_id, pool);
        return pool;
    }

    /// Allocate command buffer from current thread's pool
    pub fn allocate(self: *QueueCommandManager) !ManagedCommandBuffer {
        const pool = try self.getThreadPool();
        const buffer = try pool.acquire();

        return ManagedCommandBuffer{
            .device = self.device,
            .command_buffer = buffer,
            .pool = &pool.pool,
            .state = .initial,
            .level = .PRIMARY,
        };
    }

    /// Release command buffer back to pool
    pub fn release(self: *QueueCommandManager, buffer: ManagedCommandBuffer) !void {
        const pool = try self.getThreadPool();
        try pool.release(buffer.command_buffer);
    }

    /// Reset all pools for this queue family
    pub fn resetAll(self: *QueueCommandManager) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var it = self.thread_pools.valueIterator();
        while (it.next()) |pool| {
            try pool.*.resetAll();
        }
    }
};

/// Global command manager for all queue families
pub const CommandManager = struct {
    allocator: std.mem.Allocator,
    device: *device_mod.Device,
    graphics_manager: ?*QueueCommandManager,
    compute_manager: ?*QueueCommandManager,
    transfer_manager: ?*QueueCommandManager,

    pub fn init(
        allocator: std.mem.Allocator,
        device: *device_mod.Device,
        graphics_family: ?u32,
        compute_family: ?u32,
        transfer_family: ?u32,
    ) !*CommandManager {
        var self = try allocator.create(CommandManager);
        self.* = .{
            .allocator = allocator,
            .device = device,
            .graphics_manager = null,
            .compute_manager = null,
            .transfer_manager = null,
        };

        if (graphics_family) |family| {
            self.graphics_manager = try QueueCommandManager.init(allocator, device, family);
        }

        if (compute_family) |family| {
            self.compute_manager = try QueueCommandManager.init(allocator, device, family);
        }

        if (transfer_family) |family| {
            self.transfer_manager = try QueueCommandManager.init(allocator, device, family);
        }

        return self;
    }

    pub fn deinit(self: *CommandManager) void {
        if (self.graphics_manager) |mgr| mgr.deinit();
        if (self.compute_manager) |mgr| mgr.deinit();
        if (self.transfer_manager) |mgr| mgr.deinit();
        self.allocator.destroy(self);
    }

    /// Allocate graphics command buffer
    pub fn allocateGraphics(self: *CommandManager) !ManagedCommandBuffer {
        if (self.graphics_manager) |mgr| {
            return mgr.allocate();
        }
        return errors.Error.FeatureNotPresent;
    }

    /// Allocate compute command buffer
    pub fn allocateCompute(self: *CommandManager) !ManagedCommandBuffer {
        if (self.compute_manager) |mgr| {
            return mgr.allocate();
        }
        return errors.Error.FeatureNotPresent;
    }

    /// Allocate transfer command buffer
    pub fn allocateTransfer(self: *CommandManager) !ManagedCommandBuffer {
        if (self.transfer_manager) |mgr| {
            return mgr.allocate();
        }
        return errors.Error.FeatureNotPresent;
    }

    /// Release command buffer back to appropriate pool
    pub fn release(self: *CommandManager, buffer: ManagedCommandBuffer, queue_type: QueueType) !void {
        const mgr = switch (queue_type) {
            .graphics => self.graphics_manager orelse return errors.Error.FeatureNotPresent,
            .compute => self.compute_manager orelse return errors.Error.FeatureNotPresent,
            .transfer => self.transfer_manager orelse return errors.Error.FeatureNotPresent,
        };
        try mgr.release(buffer);
    }
};

pub const QueueType = enum {
    graphics,
    compute,
    transfer,
};
