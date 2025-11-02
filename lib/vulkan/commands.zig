const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const loader = @import("loader.zig");

pub const CommandPool = struct {
    device: *device_mod.Device,
    handle: ?types.VkCommandPool,
    queue_family_index: u32,
    flags: types.VkCommandPoolCreateFlags,

    pub const CreateOptions = struct {
        queue_family_index: u32,
        flags: types.VkCommandPoolCreateFlags = 0,
    };

    pub fn create(device: *device_mod.Device, options: CreateOptions) !CommandPool {
        const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;
        var create_info = types.VkCommandPoolCreateInfo{
            .flags = options.flags,
            .queueFamilyIndex = options.queue_family_index,
        };
        var pool_handle: types.VkCommandPool = undefined;
        try errors.ensureSuccess(device.dispatch.create_command_pool(device_handle, &create_info, device.allocation_callbacks, &pool_handle));
        return CommandPool{
            .device = device,
            .handle = pool_handle,
            .queue_family_index = options.queue_family_index,
            .flags = options.flags,
        };
    }

    pub fn destroy(self: *CommandPool) void {
        const pool_handle = self.handle orelse return;
        const device_handle = self.device.handle orelse return;
        self.device.dispatch.destroy_command_pool(device_handle, pool_handle, self.device.allocation_callbacks);
        self.handle = null;
    }

    pub fn reset(self: *CommandPool, flags: types.VkCommandPoolResetFlags) !void {
        const pool_handle = self.handle orelse return;
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;
        try errors.ensureSuccess(self.device.dispatch.reset_command_pool(device_handle, pool_handle, flags));
    }

    pub fn allocate(self: *CommandPool, allocator: std.mem.Allocator, count: u32, level: types.VkCommandBufferLevel) ![]types.VkCommandBuffer {
        std.debug.assert(count > 0);
        const pool_handle = self.handle orelse return errors.Error.DeviceCreationFailed;
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;

        const buffers = try allocator.alloc(types.VkCommandBuffer, count);
        errdefer allocator.free(buffers);

        var alloc_info = types.VkCommandBufferAllocateInfo{
            .commandPool = pool_handle,
            .level = level,
            .commandBufferCount = count,
        };

        try errors.ensureSuccess(self.device.dispatch.allocate_command_buffers(device_handle, &alloc_info, buffers.ptr));
        return buffers;
    }

    pub fn allocateOne(self: *CommandPool, level: types.VkCommandBufferLevel) !types.VkCommandBuffer {
        const pool_handle = self.handle orelse return errors.Error.DeviceCreationFailed;
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;

        var command: types.VkCommandBuffer = undefined;
        var alloc_info = types.VkCommandBufferAllocateInfo{
            .commandPool = pool_handle,
            .level = level,
            .commandBufferCount = 1,
        };

        try errors.ensureSuccess(self.device.dispatch.allocate_command_buffers(device_handle, &alloc_info, &command));
        return command;
    }

    pub fn free(self: *CommandPool, buffers: []const types.VkCommandBuffer) void {
        if (buffers.len == 0) return;
        const pool_handle = self.handle orelse return;
        const device_handle = self.device.handle orelse return;
        self.device.dispatch.free_command_buffers(device_handle, pool_handle, @intCast(buffers.len), buffers.ptr);
    }
};

pub fn beginCommandBuffer(device: *device_mod.Device, command_buffer: types.VkCommandBuffer, usage_flags: types.VkCommandBufferUsageFlags, inheritance: ?*const types.VkCommandBufferInheritanceInfo) !void {
    const begin_info = types.VkCommandBufferBeginInfo{
        .flags = usage_flags,
        .pInheritanceInfo = inheritance,
    };
    try errors.ensureSuccess(device.dispatch.begin_command_buffer(command_buffer, &begin_info));
}

pub const CommandBufferReusability = enum {
    one_time,
    reusable,
    simultaneous,
};

pub fn beginRecording(
    device: *device_mod.Device,
    command_buffer: types.VkCommandBuffer,
    reusability: CommandBufferReusability,
    inheritance: ?*const types.VkCommandBufferInheritanceInfo,
) !void {
    const flags: types.VkCommandBufferUsageFlags = switch (reusability) {
        .one_time => types.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        .reusable => 0,
        .simultaneous => types.VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT,
    };

    try beginCommandBuffer(device, command_buffer, flags, inheritance);
}

pub fn endCommandBuffer(device: *device_mod.Device, command_buffer: types.VkCommandBuffer) !void {
    try errors.ensureSuccess(device.dispatch.end_command_buffer(command_buffer));
}

pub fn singleUse(device: *device_mod.Device, pool: *CommandPool, queue: types.VkQueue, callback: anytype) !void {
    const command = try pool.allocateOne(.PRIMARY);
    var lifetime = [_]types.VkCommandBuffer{command};
    defer pool.free(lifetime[0..]);

    try beginRecording(device, command, .one_time, null);
    var finished = false;
    defer if (!finished) {
        _ = device.dispatch.end_command_buffer(command);
    };

    try callback(command);
    try endCommandBuffer(device, command);
    finished = true;

    var submit_info = types.VkSubmitInfo{
        .commandBufferCount = 1,
        .pCommandBuffers = lifetime[0..].ptr,
    };

    try errors.ensureSuccess(device.dispatch.queue_submit(queue, 1, &submit_info, null));
    try errors.ensureSuccess(device.dispatch.queue_wait_idle(queue));
}

test "CommandPool reset guards null handle" {
    var fake_device = device_mod.Device{
        .allocator = std.testing.allocator,
        .loader = undefined,
        .dispatch = undefined,
        .handle = null,
        .allocation_callbacks = null,
    };
    var pool = CommandPool{
        .device = &fake_device,
        .handle = null,
        .queue_family_index = 0,
        .flags = 0,
    };
    try pool.reset(0);
}

test "beginRecording applies correct usage flags" {
    const fake_cmd = @as(types.VkCommandBuffer, @ptrFromInt(@as(usize, 0x1234)));

    const Capture = struct {
        pub var flags: [3]types.VkCommandBufferUsageFlags = .{0} ** 3;
        pub var index: usize = 0;

        pub fn reset() void {
            flags = .{0} ** 3;
            index = 0;
        }

        pub fn begin(_: types.VkCommandBuffer, info: *const types.VkCommandBufferBeginInfo) callconv(.c) types.VkResult {
            if (index < flags.len) {
                flags[index] = info.flags;
            }
            index += 1;
            return .SUCCESS;
        }
    };

    Capture.reset();

    var device = device_mod.Device{
        .allocator = std.testing.allocator,
        .loader = undefined,
        .dispatch = std.mem.zeroes(loader.DeviceDispatch),
        .handle = @as(types.VkDevice, @ptrFromInt(@as(usize, 0xDEAD))),
        .allocation_callbacks = null,
    };
    device.dispatch.begin_command_buffer = Capture.begin;

    try beginRecording(&device, fake_cmd, .one_time, null);
    try beginRecording(&device, fake_cmd, .reusable, null);
    try beginRecording(&device, fake_cmd, .simultaneous, null);

    try std.testing.expectEqual(types.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT, Capture.flags[0]);
    try std.testing.expectEqual(@as(types.VkCommandBufferUsageFlags, 0), Capture.flags[1]);
    try std.testing.expectEqual(types.VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT, Capture.flags[2]);
}
