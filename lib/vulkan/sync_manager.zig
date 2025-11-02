//! Synchronization primitive manager (fences, semaphores, timeline semaphores)

const std = @import("std");
const types = @import("std");
const vk_types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");

const log = std.log.scoped(.sync_manager);

/// Fence pool for recycling
pub const FencePool = struct {
    device: *device_mod.Device,
    available_fences: std.ArrayList(vk_types.VkFence),
    in_use_fences: std.ArrayList(vk_types.VkFence),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, device: *device_mod.Device) FencePool {
        return .{
            .device = device,
            .available_fences = std.ArrayList(vk_types.VkFence).init(allocator),
            .in_use_fences = std.ArrayList(vk_types.VkFence).init(allocator),
            .mutex = .{},
        };
    }

    pub fn deinit(self: *FencePool) void {
        const device_handle = self.device.handle orelse return;

        for (self.available_fences.items) |fence| {
            self.device.dispatch.destroy_fence(device_handle, fence, self.device.allocation_callbacks);
        }

        for (self.in_use_fences.items) |fence| {
            self.device.dispatch.destroy_fence(device_handle, fence, self.device.allocation_callbacks);
        }

        self.available_fences.deinit();
        self.in_use_fences.deinit();
    }

    /// Acquire a fence (creates new or recycles)
    pub fn acquire(self: *FencePool, signaled: bool) !vk_types.VkFence {
        self.mutex.lock();
        defer self.mutex.unlock();

        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;

        // Try to recycle
        if (self.available_fences.popOrNull()) |fence| {
            // Reset fence
            try errors.ensureSuccess(self.device.dispatch.reset_fences(device_handle, 1, @ptrCast(&fence)));
            try self.in_use_fences.append(fence);
            return fence;
        }

        // Create new
        const create_info = vk_types.VkFenceCreateInfo{
            .flags = if (signaled) vk_types.VK_FENCE_CREATE_SIGNALED_BIT else 0,
        };

        var fence: vk_types.VkFence = undefined;
        try errors.ensureSuccess(self.device.dispatch.create_fence(device_handle, &create_info, self.device.allocation_callbacks, &fence));
        try self.in_use_fences.append(fence);

        log.debug("Created new fence (total in-use: {})", .{self.in_use_fences.items.len});
        return fence;
    }

    /// Release fence back to pool
    pub fn release(self: *FencePool, fence: vk_types.VkFence) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Remove from in-use
        for (self.in_use_fences.items, 0..) |f, i| {
            if (f == fence) {
                _ = self.in_use_fences.swapRemove(i);
                try self.available_fences.append(fence);
                return;
            }
        }

        log.warn("Attempted to release fence that wasn't in-use", .{});
    }

    /// Wait for fence and release it
    pub fn waitAndRelease(self: *FencePool, fence: vk_types.VkFence, timeout: u64) !void {
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;
        try errors.ensureSuccess(self.device.dispatch.wait_for_fences(device_handle, 1, @ptrCast(&fence), 1, timeout));
        try self.release(fence);
    }
};

/// Semaphore pool for recycling
pub const SemaphorePool = struct {
    device: *device_mod.Device,
    available_semaphores: std.ArrayList(vk_types.VkSemaphore),
    in_use_semaphores: std.ArrayList(vk_types.VkSemaphore),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, device: *device_mod.Device) SemaphorePool {
        return .{
            .device = device,
            .available_semaphores = std.ArrayList(vk_types.VkSemaphore).init(allocator),
            .in_use_semaphores = std.ArrayList(vk_types.VkSemaphore).init(allocator),
            .mutex = .{},
        };
    }

    pub fn deinit(self: *SemaphorePool) void {
        const device_handle = self.device.handle orelse return;

        for (self.available_semaphores.items) |sem| {
            self.device.dispatch.destroy_semaphore(device_handle, sem, self.device.allocation_callbacks);
        }

        for (self.in_use_semaphores.items) |sem| {
            self.device.dispatch.destroy_semaphore(device_handle, sem, self.device.allocation_callbacks);
        }

        self.available_semaphores.deinit();
        self.in_use_semaphores.deinit();
    }

    /// Acquire a semaphore (creates new or recycles)
    pub fn acquire(self: *SemaphorePool) !vk_types.VkSemaphore {
        self.mutex.lock();
        defer self.mutex.unlock();

        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;

        // Try to recycle
        if (self.available_semaphores.popOrNull()) |sem| {
            try self.in_use_semaphores.append(sem);
            return sem;
        }

        // Create new
        const create_info = vk_types.VkSemaphoreCreateInfo{};

        var sem: vk_types.VkSemaphore = undefined;
        try errors.ensureSuccess(self.device.dispatch.create_semaphore(device_handle, &create_info, self.device.allocation_callbacks, &sem));
        try self.in_use_semaphores.append(sem);

        log.debug("Created new semaphore (total in-use: {})", .{self.in_use_semaphores.items.len});
        return sem;
    }

    /// Release semaphore back to pool
    pub fn release(self: *SemaphorePool, semaphore: vk_types.VkSemaphore) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Remove from in-use
        for (self.in_use_semaphores.items, 0..) |sem, i| {
            if (sem == semaphore) {
                _ = self.in_use_semaphores.swapRemove(i);
                try self.available_semaphores.append(semaphore);
                return;
            }
        }

        log.warn("Attempted to release semaphore that wasn't in-use", .{});
    }
};

/// Timeline semaphore for fine-grained synchronization
pub const TimelineSemaphore = struct {
    device: *device_mod.Device,
    semaphore: vk_types.VkSemaphore,
    current_value: u64,

    pub fn create(device: *device_mod.Device, initial_value: u64) !TimelineSemaphore {
        const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;

        var type_info = vk_types.VkSemaphoreTypeCreateInfo{
            .semaphoreType = .TIMELINE,
            .initialValue = initial_value,
        };

        const create_info = vk_types.VkSemaphoreCreateInfo{
            .pNext = &type_info,
        };

        var semaphore: vk_types.VkSemaphore = undefined;
        try errors.ensureSuccess(device.dispatch.create_semaphore(device_handle, &create_info, device.allocation_callbacks, &semaphore));

        log.debug("Created timeline semaphore with initial value {}", .{initial_value});

        return TimelineSemaphore{
            .device = device,
            .semaphore = semaphore,
            .current_value = initial_value,
        };
    }

    pub fn destroy(self: *TimelineSemaphore) void {
        const device_handle = self.device.handle orelse return;
        self.device.dispatch.destroy_semaphore(device_handle, self.semaphore, self.device.allocation_callbacks);
    }

    /// Signal timeline semaphore to a specific value
    pub fn signal(self: *TimelineSemaphore, value: u64) !void {
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;

        const signal_info = vk_types.VkSemaphoreSignalInfo{
            .semaphore = self.semaphore,
            .value = value,
        };

        try errors.ensureSuccess(self.device.dispatch.signal_semaphore(device_handle, &signal_info));
        self.current_value = value;
    }

    /// Wait for timeline semaphore to reach a specific value
    pub fn wait(self: *TimelineSemaphore, value: u64, timeout: u64) !void {
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;

        const wait_info = vk_types.VkSemaphoreWaitInfo{
            .semaphoreCount = 1,
            .pSemaphores = @ptrCast(&self.semaphore),
            .pValues = @ptrCast(&value),
        };

        try errors.ensureSuccess(self.device.dispatch.wait_semaphores(device_handle, &wait_info, timeout));
    }

    /// Get current timeline value
    pub fn getValue(self: *TimelineSemaphore) !u64 {
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;

        var value: u64 = undefined;
        try errors.ensureSuccess(self.device.dispatch.get_semaphore_counter_value(device_handle, self.semaphore, &value));
        return value;
    }
};

/// Synchronization manager
pub const SyncManager = struct {
    allocator: std.mem.Allocator,
    device: *device_mod.Device,
    fence_pool: FencePool,
    semaphore_pool: SemaphorePool,

    pub fn init(allocator: std.mem.Allocator, device: *device_mod.Device) SyncManager {
        return .{
            .allocator = allocator,
            .device = device,
            .fence_pool = FencePool.init(allocator, device),
            .semaphore_pool = SemaphorePool.init(allocator, device),
        };
    }

    pub fn deinit(self: *SyncManager) void {
        self.fence_pool.deinit();
        self.semaphore_pool.deinit();
    }

    /// Acquire fence from pool
    pub fn acquireFence(self: *SyncManager, signaled: bool) !vk_types.VkFence {
        return self.fence_pool.acquire(signaled);
    }

    /// Release fence back to pool
    pub fn releaseFence(self: *SyncManager, fence: vk_types.VkFence) !void {
        try self.fence_pool.release(fence);
    }

    /// Acquire semaphore from pool
    pub fn acquireSemaphore(self: *SyncManager) !vk_types.VkSemaphore {
        return self.semaphore_pool.acquire();
    }

    /// Release semaphore back to pool
    pub fn releaseSemaphore(self: *SyncManager, semaphore: vk_types.VkSemaphore) !void {
        try self.semaphore_pool.release(semaphore);
    }

    /// Create timeline semaphore
    pub fn createTimelineSemaphore(self: *SyncManager, initial_value: u64) !TimelineSemaphore {
        return TimelineSemaphore.create(self.device, initial_value);
    }
};
