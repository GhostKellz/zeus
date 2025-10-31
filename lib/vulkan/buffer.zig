const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const loader = @import("loader.zig");
const memory = @import("memory.zig");
const commands = @import("commands.zig");

pub const BufferCreateOptions = struct {
    size: types.VkDeviceSize,
    usage: types.VkBufferUsageFlags,
    sharing_mode: types.VkSharingMode = .EXCLUSIVE,
    queue_family_indices: []const u32 = &.{},
    flags: types.VkBufferCreateFlags = 0,
};

pub fn createBuffer(device: *device_mod.Device, size: types.VkDeviceSize, usage: types.VkBufferUsageFlags) errors.Error!types.VkBuffer {
    return createBufferWithOptions(device, .{ .size = size, .usage = usage });
}

pub fn createBufferWithOptions(device: *device_mod.Device, options: BufferCreateOptions) errors.Error!types.VkBuffer {
    const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;

    var queue_indices_ptr: ?[*]const u32 = null;
    if (options.queue_family_indices.len > 0) {
        queue_indices_ptr = @as([*]const u32, @ptrCast(options.queue_family_indices.ptr));
    }

    var create_info = types.VkBufferCreateInfo{
        .flags = options.flags,
        .size = options.size,
        .usage = options.usage,
        .sharingMode = options.sharing_mode,
        .queueFamilyIndexCount = @intCast(options.queue_family_indices.len),
        .pQueueFamilyIndices = queue_indices_ptr,
    };

    var buffer: types.VkBuffer = undefined;
    try errors.ensureSuccess(device.dispatch.create_buffer(device_handle, &create_info, device.allocation_callbacks, &buffer));
    return buffer;
}

pub fn destroyBuffer(device: *device_mod.Device, buffer: types.VkBuffer) void {
    const device_handle = device.handle orelse return;
    device.dispatch.destroy_buffer(device_handle, buffer, device.allocation_callbacks);
}

pub const ManagedBuffer = struct {
    device: *device_mod.Device,
    buffer: types.VkBuffer,
    allocation: memory.Allocation,
    size: types.VkDeviceSize,
    usage: types.VkBufferUsageFlags,
    memory_type_index: u32,
    memory_flags: types.VkMemoryPropertyFlags,

    pub fn deinit(self: *ManagedBuffer) void {
        destroyBuffer(self.device, self.buffer);
        self.allocation.destroy();
    }

    pub fn map(self: *ManagedBuffer, offset: types.VkDeviceSize, length: types.VkDeviceSize) errors.Error![*]u8 {
        return self.allocation.map(offset, length);
    }

    pub fn unmap(self: *ManagedBuffer) void {
        self.allocation.unmap();
    }

    fn isCoherent(self: *ManagedBuffer) bool {
        return (self.memory_flags & types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) != 0;
    }

    fn ensureMapped(self: *ManagedBuffer, offset: types.VkDeviceSize, length: usize) errors.Error!struct {
        ptr: [*]u8,
        existing: bool,
    } {
        if (self.allocation.isMapped()) {
            const mapped = try self.allocation.map(offset, @intCast(length));
            return .{ .ptr = mapped, .existing = true };
        }

        const mapped = try self.allocation.map(offset, @intCast(length));
        return .{ .ptr = mapped, .existing = false };
    }

    pub fn write(self: *ManagedBuffer, data: []const u8, offset: types.VkDeviceSize) errors.Error!void {
        const data_len = @as(types.VkDeviceSize, @intCast(data.len));
        std.debug.assert(offset + data_len <= self.size);

        var map_state = try self.ensureMapped(offset, data.len);
        defer if (!map_state.existing) self.allocation.unmap();

        std.mem.copy(u8, map_state.ptr[0..data.len], data);

        if (!self.isCoherent()) {
            const range = types.VkMappedMemoryRange{
                .memory = self.allocation.memory.?,
                .offset = offset,
                .size = data_len,
            };
            try self.allocation.flush(&.{range});
        }
    }
};

pub const ManagedBufferOptions = struct {
    filter: memory.MemoryTypeFilter = .{},
};

pub fn createManagedBuffer(device: *device_mod.Device, memory_props: types.VkPhysicalDeviceMemoryProperties, size: types.VkDeviceSize, usage: types.VkBufferUsageFlags, options: ManagedBufferOptions) errors.Error!ManagedBuffer {
    const buffer = try createBuffer(device, size, usage);
    errdefer destroyBuffer(device, buffer);

    const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;

    var requirements: types.VkMemoryRequirements = undefined;
    device.dispatch.get_buffer_memory_requirements(device_handle, buffer, &requirements);

    const type_index = try memory.findMemoryTypeIndex(memory_props, requirements, options.filter);
    var allocation = try memory.allocate(device, requirements, type_index);
    errdefer allocation.destroy();

    try errors.ensureSuccess(device.dispatch.bind_buffer_memory(device_handle, buffer, allocation.memory.?, 0));

    const flags = memory_props.memoryTypes[type_index].propertyFlags;
    memory.logReBARUsage(memory_props, type_index, size);

    return ManagedBuffer{
        .device = device,
        .buffer = buffer,
        .allocation = allocation,
        .size = size,
        .usage = usage,
        .memory_type_index = type_index,
        .memory_flags = flags,
    };
}

pub const BufferCopyOptions = struct {
    src_offset: types.VkDeviceSize = 0,
    dst_offset: types.VkDeviceSize = 0,
};

pub fn copyBuffer(device: *device_mod.Device, pool: *commands.CommandPool, queue: types.VkQueue, src: types.VkBuffer, dst: types.VkBuffer, size: types.VkDeviceSize, options: BufferCopyOptions) errors.Error!void {
    const command = try pool.allocateOne(.PRIMARY);
    var buffers = [_]types.VkCommandBuffer{command};
    defer pool.free(buffers[0..]);

    try commands.beginCommandBuffer(device, command, types.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT, null);

    var region = types.VkBufferCopy{
        .srcOffset = options.src_offset,
        .dstOffset = options.dst_offset,
        .size = size,
    };

    device.dispatch.cmd_copy_buffer(command, src, dst, 1, &region);
    try commands.endCommandBuffer(device, command);

    var submit = types.VkSubmitInfo{
        .commandBufferCount = 1,
        .pCommandBuffers = buffers[0..].ptr,
    };

    try errors.ensureSuccess(device.dispatch.queue_submit(queue, 1, &submit, null));
    try errors.ensureSuccess(device.dispatch.queue_wait_idle(queue));
}

pub const TransitionOptions = struct {
    device: *device_mod.Device,
    range: ?types.VkImageSubresourceRange = null,
    src_access: ?types.VkAccessFlags = null,
    dst_access: ?types.VkAccessFlags = null,
    src_stage: ?types.VkPipelineStageFlags = null,
    dst_stage: ?types.VkPipelineStageFlags = null,
    src_queue_family_index: u32 = types.VK_QUEUE_FAMILY_IGNORED,
    dst_queue_family_index: u32 = types.VK_QUEUE_FAMILY_IGNORED,
    dependency_flags: types.VkDependencyFlags = 0,
};

const TransitionInfo = struct {
    src_stage: types.VkPipelineStageFlags,
    dst_stage: types.VkPipelineStageFlags,
    src_access: types.VkAccessFlags,
    dst_access: types.VkAccessFlags,
    range: types.VkImageSubresourceRange,
};

pub fn transitionImageLayout(cmd: types.VkCommandBuffer, image: types.VkImage, old_layout: types.VkImageLayout, new_layout: types.VkImageLayout, options: TransitionOptions) errors.Error!void {
    const device_handle = options.device.handle orelse return errors.Error.DeviceCreationFailed;
    _ = device_handle;

    const inferred = try inferTransition(old_layout, new_layout);

    const barrier = types.VkImageMemoryBarrier{
        .srcAccessMask = options.src_access orelse inferred.src_access,
        .dstAccessMask = options.dst_access orelse inferred.dst_access,
        .oldLayout = old_layout,
        .newLayout = new_layout,
        .srcQueueFamilyIndex = options.src_queue_family_index,
        .dstQueueFamilyIndex = options.dst_queue_family_index,
        .image = image,
        .subresourceRange = options.range orelse inferred.range,
    };

    options.device.dispatch.cmd_pipeline_barrier(
        cmd,
        options.src_stage orelse inferred.src_stage,
        options.dst_stage orelse inferred.dst_stage,
        options.dependency_flags,
        0,
        null,
        0,
        null,
        1,
        &barrier,
    );
}

pub fn transitionImageLayoutSimple(device: *device_mod.Device, cmd: types.VkCommandBuffer, image: types.VkImage, old_layout: types.VkImageLayout, new_layout: types.VkImageLayout) errors.Error!void {
    return transitionImageLayout(cmd, image, old_layout, new_layout, .{ .device = device });
}

fn inferTransition(old_layout: types.VkImageLayout, new_layout: types.VkImageLayout) errors.Error!TransitionInfo {
    const full_color_range = types.VkImageSubresourceRange{
        .aspectMask = types.VK_IMAGE_ASPECT_COLOR_BIT,
        .baseMipLevel = 0,
        .levelCount = types.VK_REMAINING_MIP_LEVELS,
        .baseArrayLayer = 0,
        .layerCount = types.VK_REMAINING_ARRAY_LAYERS,
    };

    const full_depth_range = types.VkImageSubresourceRange{
        .aspectMask = types.VK_IMAGE_ASPECT_DEPTH_BIT | types.VK_IMAGE_ASPECT_STENCIL_BIT,
        .baseMipLevel = 0,
        .levelCount = types.VK_REMAINING_MIP_LEVELS,
        .baseArrayLayer = 0,
        .layerCount = types.VK_REMAINING_ARRAY_LAYERS,
    };

    switch (old_layout) {
        .UNDEFINED => switch (new_layout) {
            .TRANSFER_DST_OPTIMAL => return TransitionInfo{
                .src_stage = types.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
                .dst_stage = types.VK_PIPELINE_STAGE_TRANSFER_BIT,
                .src_access = 0,
                .dst_access = types.VK_ACCESS_TRANSFER_WRITE_BIT,
                .range = full_color_range,
            },
            .SHADER_READ_ONLY_OPTIMAL => return TransitionInfo{
                .src_stage = types.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
                .dst_stage = types.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
                .src_access = 0,
                .dst_access = types.VK_ACCESS_SHADER_READ_BIT,
                .range = full_color_range,
            },
            .COLOR_ATTACHMENT_OPTIMAL => return TransitionInfo{
                .src_stage = types.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
                .dst_stage = types.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                .src_access = 0,
                .dst_access = types.VK_ACCESS_COLOR_ATTACHMENT_READ_BIT | types.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
                .range = full_color_range,
            },
            .DEPTH_STENCIL_ATTACHMENT_OPTIMAL => return TransitionInfo{
                .src_stage = types.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
                .dst_stage = types.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
                .src_access = 0,
                .dst_access = types.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT | types.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
                .range = full_depth_range,
            },
            else => {},
        },
        .TRANSFER_DST_OPTIMAL => switch (new_layout) {
            .SHADER_READ_ONLY_OPTIMAL => return TransitionInfo{
                .src_stage = types.VK_PIPELINE_STAGE_TRANSFER_BIT,
                .dst_stage = types.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
                .src_access = types.VK_ACCESS_TRANSFER_WRITE_BIT,
                .dst_access = types.VK_ACCESS_SHADER_READ_BIT,
                .range = full_color_range,
            },
            else => {},
        },
        .COLOR_ATTACHMENT_OPTIMAL => switch (new_layout) {
            .PRESENT_SRC_KHR => return TransitionInfo{
                .src_stage = types.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                .dst_stage = types.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
                .src_access = types.VK_ACCESS_COLOR_ATTACHMENT_READ_BIT | types.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
                .dst_access = 0,
                .range = full_color_range,
            },
            else => {},
        },
        else => {},
    }

    return errors.Error.FeatureNotPresent;
}

const fake_buffer_handle = @as(types.VkBuffer, @ptrFromInt(@as(usize, 0x1)));

const Capture = struct {
    pub var last_buffer_info: ?types.VkBufferCreateInfo = null;
    pub var last_barrier: ?types.VkImageMemoryBarrier = null;
    pub var last_src_stage: types.VkPipelineStageFlags = 0;
    pub var last_dst_stage: types.VkPipelineStageFlags = 0;

    pub fn reset() void {
        last_buffer_info = null;
        last_barrier = null;
        last_src_stage = 0;
        last_dst_stage = 0;
    }

    pub fn stubCreateBuffer(_: types.VkDevice, info: *const types.VkBufferCreateInfo, _: ?*const types.VkAllocationCallbacks, buffer: *types.VkBuffer) callconv(.C) types.VkResult {
        last_buffer_info = info.*;
        buffer.* = fake_buffer_handle;
        return .SUCCESS;
    }

    pub fn stubDestroyBuffer(_: types.VkDevice, _: types.VkBuffer, _: ?*const types.VkAllocationCallbacks) callconv(.C) void {}

    pub fn stubPipelineBarrier(_: types.VkCommandBuffer, src_stage_mask: types.VkPipelineStageFlags, dst_stage_mask: types.VkPipelineStageFlags, _: types.VkDependencyFlags, _: u32, _: ?[*]const types.VkMemoryBarrier, _: u32, _: ?[*]const types.VkBufferMemoryBarrier, image_barrier_count: u32, image_barriers: ?[*]const types.VkImageMemoryBarrier) callconv(.C) void {
        std.debug.assert(image_barrier_count == 1);
        last_barrier = image_barriers.?[0];
        last_src_stage = src_stage_mask;
        last_dst_stage = dst_stage_mask;
    }
};

fn makeFakeDevice() device_mod.Device {
    var device = device_mod.Device{
        .allocator = std.testing.allocator,
        .loader = undefined,
        .dispatch = std.mem.zeroes(loader.DeviceDispatch),
        .handle = @as(types.VkDevice, @ptrFromInt(@as(usize, 0x2))),
        .allocation_callbacks = null,
    };
    device.dispatch.create_buffer = Capture.stubCreateBuffer;
    device.dispatch.destroy_buffer = Capture.stubDestroyBuffer;
    device.dispatch.cmd_pipeline_barrier = Capture.stubPipelineBarrier;
    return device;
}

test "createBuffer forwards parameters" {
    Capture.reset();
    var device = makeFakeDevice();
    const buffer = try createBuffer(&device, 4096, types.VK_BUFFER_USAGE_TRANSFER_DST_BIT | types.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
    try std.testing.expect(buffer == fake_buffer_handle);
    const info = Capture.last_buffer_info orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(types.VkDeviceSize, 4096), info.size);
    try std.testing.expectEqual(types.VK_BUFFER_USAGE_TRANSFER_DST_BIT | types.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, info.usage);
    try std.testing.expect(info.sharingMode == .EXCLUSIVE);
}

test "transitionImageLayout infers transfer to shader read" {
    Capture.reset();
    var device = makeFakeDevice();
    try transitionImageLayoutSimple(&device, @as(types.VkCommandBuffer, @ptrFromInt(@as(usize, 0x3))), @as(types.VkImage, @ptrFromInt(@as(usize, 0x4))), .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL);
    const barrier = Capture.last_barrier orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(types.VK_ACCESS_TRANSFER_WRITE_BIT, barrier.srcAccessMask);
    try std.testing.expectEqual(types.VK_ACCESS_SHADER_READ_BIT, barrier.dstAccessMask);
    try std.testing.expectEqual(types.VkImageLayout.TRANSFER_DST_OPTIMAL, barrier.oldLayout);
    try std.testing.expectEqual(types.VkImageLayout.SHADER_READ_ONLY_OPTIMAL, barrier.newLayout);
    try std.testing.expectEqual(types.VK_IMAGE_ASPECT_COLOR_BIT, barrier.subresourceRange.aspectMask);
    try std.testing.expectEqual(types.VK_PIPELINE_STAGE_TRANSFER_BIT, Capture.last_src_stage);
    try std.testing.expectEqual(types.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, Capture.last_dst_stage);
}

test "transitionImageLayout rejects unsupported transition" {
    Capture.reset();
    var device = makeFakeDevice();
    const result = transitionImageLayoutSimple(&device, @as(types.VkCommandBuffer, @ptrFromInt(@as(usize, 0x5))), @as(types.VkImage, @ptrFromInt(@as(usize, 0x6))), .GENERAL, .PRESENT_SRC_KHR);
    try std.testing.expectError(errors.Error.FeatureNotPresent, result);
}

test "createManagedBuffer binds memory and records usage" {
    Capture.reset();
    resetMemoryCapture();
    bound_memory = null;

    var device = makeFakeDevice();
    device.dispatch.get_buffer_memory_requirements = stubGetBufferRequirements;
    device.dispatch.bind_buffer_memory = stubBindBufferMemory;
    device.dispatch.allocate_memory = memoryStubAllocateMemory;
    device.dispatch.free_memory = memoryStubFreeMemory;
    device.dispatch.map_memory = memoryStubMap;
    device.dispatch.unmap_memory = memoryStubUnmap;
    device.dispatch.flush_mapped_memory_ranges = memoryStubFlush;

    const props = memoryProps();
    var managed = try createManagedBuffer(&device, props, 2048, types.VK_BUFFER_USAGE_TRANSFER_DST_BIT | types.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, .{
        .filter = .{
            .required_flags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT,
            .preferred_flags = types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        },
    });
    defer managed.deinit();

    try std.testing.expectEqual(@as(types.VkDeviceSize, 2048), managed.size);
    try std.testing.expectEqual(@as(u32, 1), managed.memory_type_index);
    try std.testing.expectEqual(types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, managed.memory_flags);
    try std.testing.expect(Capture.last_buffer_info != null);
    try std.testing.expectEqual(@as(types.VkDeviceMemory, @ptrFromInt(@as(usize, 0x900))), bound_memory.?);
}

test "ManagedBuffer.write maps copy flushes when not coherent" {
    Capture.reset();
    resetMemoryCapture();
    bound_memory = null;

    var device = makeFakeDevice();
    device.dispatch.get_buffer_memory_requirements = stubGetBufferRequirements;
    device.dispatch.bind_buffer_memory = stubBindBufferMemory;
    device.dispatch.allocate_memory = memoryStubAllocateMemory;
    device.dispatch.free_memory = memoryStubFreeMemory;
    device.dispatch.map_memory = memoryStubMap;
    device.dispatch.unmap_memory = memoryStubUnmap;
    device.dispatch.flush_mapped_memory_ranges = memoryStubFlush;
    device.dispatch.invalidate_mapped_memory_ranges = memoryStubInvalidate;

    var props = memoryProps();
    props.memoryTypes[1].propertyFlags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT;

    var managed = try createManagedBuffer(&device, props, 1024, types.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, .{
        .filter = .{ .required_flags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT },
    });
    defer managed.deinit();

    const data = [_]u8{ 1, 2, 3, 4 };
    try managed.write(&data, 0);
    try std.testing.expectEqual(@as(usize, 1), memory_flush_calls);
    try std.testing.expectEqual(@as(usize, 1), memory_unmap_calls);
    try std.testing.expectEqualSlices(u8, data[0..], memory_storage[0..data.len]);
}

test "copyBuffer records command and submits" {
    resetCopyCapture();

    var device = makeFakeDevice();
    device.dispatch.begin_command_buffer = stubBeginCommand;
    device.dispatch.end_command_buffer = stubEndCommand;
    device.dispatch.cmd_copy_buffer = stubCmdCopyBuffer;
    device.dispatch.queue_submit = stubQueueSubmit;
    device.dispatch.queue_wait_idle = stubQueueWaitIdle;
    device.dispatch.allocate_command_buffers = stubAllocateCommandBuffers;
    device.dispatch.free_command_buffers = stubFreeCommandBuffers;

    var pool = commands.CommandPool{
        .device = &device,
        .handle = @as(types.VkCommandPool, @ptrFromInt(@as(usize, 0x700))),
        .queue_family_index = 0,
        .flags = 0,
    };

    global_command_buffer = @as(types.VkCommandBuffer, @ptrFromInt(@as(usize, 0x701)));

    try copyBuffer(&device, &pool, @as(types.VkQueue, @ptrFromInt(@as(usize, 0x702))), @as(types.VkBuffer, @ptrFromInt(@as(usize, 0x800))), @as(types.VkBuffer, @ptrFromInt(@as(usize, 0x801))), 256, .{ .src_offset = 64, .dst_offset = 128 });

    try std.testing.expectEqual(@as(types.VkDeviceSize, 64), last_copy_region.srcOffset);
    try std.testing.expectEqual(@as(types.VkDeviceSize, 128), last_copy_region.dstOffset);
    try std.testing.expectEqual(@as(types.VkDeviceSize, 256), last_copy_region.size);
    try std.testing.expectEqual(@as(usize, 1), submit_calls);
    try std.testing.expectEqual(@as(usize, 1), wait_calls);
}

fn memoryProps() types.VkPhysicalDeviceMemoryProperties {
    var props: types.VkPhysicalDeviceMemoryProperties = std.mem.zeroes(types.VkPhysicalDeviceMemoryProperties);
    props.memoryTypeCount = 2;
    props.memoryTypes[0] = .{ .propertyFlags = types.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, .heapIndex = 0 };
    props.memoryTypes[1] = .{ .propertyFlags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, .heapIndex = 1 };
    props.memoryHeapCount = 2;
    props.memoryHeaps[0] = .{ .size = 1024 * 1024 * 1024, .flags = types.VK_MEMORY_HEAP_DEVICE_LOCAL_BIT };
    props.memoryHeaps[1] = .{ .size = 512 * 1024 * 1024, .flags = 0 };
    return props;
}

fn stubGetBufferRequirements(_: types.VkDevice, _: types.VkBuffer, requirements: *types.VkMemoryRequirements) callconv(.C) void {
    requirements.* = types.VkMemoryRequirements{
        .size = 4096,
        .alignment = 256,
        .memoryTypeBits = 0b10,
    };
}

var bound_memory: ?types.VkDeviceMemory = null;

fn stubBindBufferMemory(_: types.VkDevice, _: types.VkBuffer, memory_handle: types.VkDeviceMemory, _: types.VkDeviceSize) callconv(.C) types.VkResult {
    bound_memory = memory_handle;
    return .SUCCESS;
}

var memory_alloc_info: ?types.VkMemoryAllocateInfo = null;
var memory_flush_calls: usize = 0;
var memory_unmap_calls: usize = 0;
var memory_storage: [4096]u8 = undefined;

fn resetMemoryCapture() void {
    memory_alloc_info = null;
    memory_flush_calls = 0;
    memory_unmap_calls = 0;
    std.mem.set(u8, memory_storage[0..], 0);
}

fn memoryStubAllocateMemory(_: types.VkDevice, info: *const types.VkMemoryAllocateInfo, _: ?*const types.VkAllocationCallbacks, memory_out: *types.VkDeviceMemory) callconv(.C) types.VkResult {
    memory_alloc_info = info.*;
    memory_out.* = @as(types.VkDeviceMemory, @ptrFromInt(@as(usize, 0x900)));
    return .SUCCESS;
}

fn memoryStubFreeMemory(_: types.VkDevice, _: types.VkDeviceMemory, _: ?*const types.VkAllocationCallbacks) callconv(.C) void {}

fn memoryStubMap(_: types.VkDevice, _: types.VkDeviceMemory, _: types.VkDeviceSize, _: types.VkDeviceSize, _: types.VkMemoryMapFlags, data_out: *?*anyopaque) callconv(.C) types.VkResult {
    data_out.* = @as(*anyopaque, @ptrCast(memory_storage[0..].ptr));
    return .SUCCESS;
}

fn memoryStubUnmap(_: types.VkDevice, _: types.VkDeviceMemory) callconv(.C) void {
    memory_unmap_calls += 1;
}

fn memoryStubFlush(_: types.VkDevice, _: u32, _: [*]const types.VkMappedMemoryRange) callconv(.C) types.VkResult {
    memory_flush_calls += 1;
    return .SUCCESS;
}

fn memoryStubInvalidate(_: types.VkDevice, _: u32, _: [*]const types.VkMappedMemoryRange) callconv(.C) types.VkResult {
    return .SUCCESS;
}

var global_command_buffer: ?types.VkCommandBuffer = null;
var last_copy_region: types.VkBufferCopy = types.VkBufferCopy{
    .srcOffset = 0,
    .dstOffset = 0,
    .size = 0,
};
var submit_calls: usize = 0;
var wait_calls: usize = 0;

fn resetCopyCapture() void {
    global_command_buffer = null;
    last_copy_region = types.VkBufferCopy{ .srcOffset = 0, .dstOffset = 0, .size = 0 };
    submit_calls = 0;
    wait_calls = 0;
}

fn stubBeginCommand(_: types.VkCommandBuffer, _: *const types.VkCommandBufferBeginInfo) callconv(.C) types.VkResult {
    return .SUCCESS;
}

fn stubEndCommand(_: types.VkCommandBuffer) callconv(.C) types.VkResult {
    return .SUCCESS;
}

fn stubAllocateCommandBuffers(_: types.VkDevice, _: *const types.VkCommandBufferAllocateInfo, buffers: *types.VkCommandBuffer) callconv(.C) types.VkResult {
    buffers.* = global_command_buffer.?;
    return .SUCCESS;
}

fn stubFreeCommandBuffers(_: types.VkDevice, _: types.VkCommandPool, _: u32, _: *const types.VkCommandBuffer) callconv(.C) void {}

fn stubCmdCopyBuffer(_: types.VkCommandBuffer, _: types.VkBuffer, _: types.VkBuffer, _: u32, regions: *const types.VkBufferCopy) callconv(.C) void {
    last_copy_region = regions.*;
}

fn stubQueueSubmit(_: types.VkQueue, submit_count: u32, submits: *const types.VkSubmitInfo, _: types.VkFence) callconv(.C) types.VkResult {
    submit_calls += 1;
    std.debug.assert(submit_count == 1);
    std.debug.assert(submits.*.commandBufferCount == 1);
    return .SUCCESS;
}

fn stubQueueWaitIdle(_: types.VkQueue) callconv(.C) types.VkResult {
    wait_calls += 1;
    return .SUCCESS;
}
