const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");

pub const Fence = struct {
    device: *device_mod.Device,
    handle: ?types.VkFence,
    flags: types.VkFenceCreateFlags,

    pub const CreateOptions = struct {
        signaled: bool = false,
    };

    pub fn create(device: *device_mod.Device, options: CreateOptions) !Fence {
        const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;
        var create_info = types.VkFenceCreateInfo{
            .flags = if (options.signaled) types.VK_FENCE_CREATE_SIGNALED_BIT else 0,
        };
        var fence_handle: types.VkFence = undefined;
        try errors.ensureSuccess(device.dispatch.create_fence(device_handle, &create_info, device.allocation_callbacks, &fence_handle));
        return Fence{ .device = device, .handle = fence_handle, .flags = create_info.flags };
    }

    pub fn destroy(self: *Fence) void {
        const handle = self.handle orelse return;
        const device_handle = self.device.handle orelse return;
        self.device.dispatch.destroy_fence(device_handle, handle, self.device.allocation_callbacks);
        self.handle = null;
    }

    pub fn wait(self: *Fence, timeout_ns: u64) !bool {
        const handle = self.handle orelse return errors.Error.DeviceCreationFailed;
        const result = try self.waitMany(&.{handle}, true, timeout_ns);
        return result;
    }

    pub fn waitMany(self: *Fence, fences: []const types.VkFence, wait_all: bool, timeout_ns: u64) !bool {
        if (fences.len == 0) return true;
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;
        const wait_all_flag: types.VkBool32 = if (wait_all) 1 else 0;
        const res = self.device.dispatch.wait_for_fences(device_handle, @intCast(fences.len), fences.ptr, wait_all_flag, timeout_ns);
        if (res == .SUCCESS) return true;
        if (res == .TIMEOUT) return false;
        try errors.ensureSuccess(res);
        return false;
    }

    pub fn reset(self: *Fence) !void {
        const handle = self.handle orelse return;
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;
        try errors.ensureSuccess(self.device.dispatch.reset_fences(device_handle, 1, &handle));
    }

    pub fn status(self: *Fence) !types.VkResult {
        const handle = self.handle orelse return errors.Error.DeviceCreationFailed;
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;
        return self.device.dispatch.get_fence_status(device_handle, handle);
    }
};

pub const SemaphoreType = enum { binary, timeline };

pub const Semaphore = struct {
    device: *device_mod.Device,
    handle: ?types.VkSemaphore,
    kind: SemaphoreType,

    pub const CreateOptions = struct {
        kind: SemaphoreType = .binary,
        initial_value: u64 = 0,
    };

    pub fn create(device: *device_mod.Device, options: CreateOptions) !Semaphore {
        const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;
        var type_info_storage: types.VkSemaphoreTypeCreateInfo = undefined;
        var create_info = types.VkSemaphoreCreateInfo{};
        if (options.kind == .timeline) {
            type_info_storage = types.VkSemaphoreTypeCreateInfo{
                .semaphoreType = .TIMELINE,
                .initialValue = options.initial_value,
            };
            create_info.pNext = &type_info_storage;
        }

        var semaphore_handle: types.VkSemaphore = undefined;
        try errors.ensureSuccess(device.dispatch.create_semaphore(device_handle, &create_info, device.allocation_callbacks, &semaphore_handle));
        return Semaphore{
            .device = device,
            .handle = semaphore_handle,
            .kind = options.kind,
        };
    }

    pub fn destroy(self: *Semaphore) void {
        const handle = self.handle orelse return;
        const device_handle = self.device.handle orelse return;
        self.device.dispatch.destroy_semaphore(device_handle, handle, self.device.allocation_callbacks);
        self.handle = null;
    }

    pub fn wait(self: *Semaphore, value: u64, timeout_ns: u64) !bool {
        if (self.kind != .timeline) return errors.Error.FeatureNotPresent;
        const handle = self.handle orelse return errors.Error.DeviceCreationFailed;
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;
        var semaphores = [_]types.VkSemaphore{handle};
        var values = [_]u64{value};
        const wait_info = types.VkSemaphoreWaitInfo{
            .semaphoreCount = 1,
            .pSemaphores = semaphores[0..].ptr,
            .pValues = values[0..].ptr,
        };
        const result = self.device.dispatch.wait_semaphores(device_handle, &wait_info, timeout_ns);
        if (result == .SUCCESS) return true;
        if (result == .TIMEOUT) return false;
        try errors.ensureSuccess(result);
        return false;
    }

    pub fn signal(self: *Semaphore, value: u64) !void {
        if (self.kind != .timeline) return errors.Error.FeatureNotPresent;
        const handle = self.handle orelse return errors.Error.DeviceCreationFailed;
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;
        const signal_info = types.VkSemaphoreSignalInfo{
            .semaphore = handle,
            .value = value,
        };
        try errors.ensureSuccess(self.device.dispatch.signal_semaphore(device_handle, &signal_info));
    }
};

test "Fence::waitMany handles empty set" {
    var fake_device = device_mod.Device{
        .allocator = std.testing.allocator,
        .loader = undefined,
        .dispatch = undefined,
        .handle = null,
        .allocation_callbacks = null,
    };
    var fence = Fence{ .device = &fake_device, .handle = null, .flags = 0 };
    const res = try fence.waitMany(&.{}, true, 0);
    try std.testing.expect(res);
}
