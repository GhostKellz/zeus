//! Zeus text rendering quickstart (mocked environment)
//!
//! This example demonstrates how to use the `TextRenderer` API, including the
//! new batching and telemetry helpers introduced in Phase 6.  Rather than
//! creating a full Vulkan swapchain, we stand up a lightweight mock device
//! using the same stubs that power the unit tests.  The goal is to highlight
//! the sequencing of the frame API (`beginFrame → queueQuads → encode → stats`).

const std = @import("std");
const zeus = @import("zeus");
const vulkan = zeus.vulkan;

const TextRenderer = vulkan.TextRenderer;
const TextQuad = vulkan.TextQuad;
const types = vulkan.types;
const device_mod = vulkan.device;
const loader = vulkan.loader;

const fake_device_handle = @as(types.VkDevice, @ptrFromInt(@as(usize, 0xDEAD_BEEF)));
const fake_command_buffer = @as(types.VkCommandBuffer, @ptrFromInt(@as(usize, 0xBEEF_DEAD)));
const fake_queue = @as(types.VkQueue, @ptrFromInt(@as(usize, 0xABCD_EF01)));

var next_handle: usize = 0x2000;
fn makeHandle(comptime T: type) T {
    next_handle += 0x10;
    return @as(T, @ptrFromInt(next_handle));
}

var mapped_storage: [8192]u8 = [_]u8{0} ** 8192;

fn setupMockDispatch(device: *device_mod.Device) void {
    device.dispatch.destroy_device = stubDestroyDevice;
    device.dispatch.get_device_queue = stubGetDeviceQueue;
    device.dispatch.queue_submit = stubQueueSubmit;
    device.dispatch.queue_wait_idle = stubQueueWaitIdle;
    device.dispatch.create_descriptor_set_layout = stubCreateDescriptorSetLayout;
    device.dispatch.destroy_descriptor_set_layout = stubDestroyDescriptorSetLayout;
    device.dispatch.create_descriptor_pool = stubCreateDescriptorPool;
    device.dispatch.destroy_descriptor_pool = stubDestroyDescriptorPool;
    device.dispatch.allocate_descriptor_sets = stubAllocateDescriptorSets;
    device.dispatch.free_descriptor_sets = stubFreeDescriptorSets;
    device.dispatch.update_descriptor_sets = stubUpdateDescriptorSets;
    device.dispatch.create_pipeline_layout = stubCreatePipelineLayout;
    device.dispatch.destroy_pipeline_layout = stubDestroyPipelineLayout;
    device.dispatch.create_render_pass = stubCreateRenderPass;
    device.dispatch.destroy_render_pass = stubDestroyRenderPass;
    device.dispatch.create_shader_module = stubCreateShaderModule;
    device.dispatch.destroy_shader_module = stubDestroyShaderModule;
    device.dispatch.create_graphics_pipelines = stubCreateGraphicsPipelines;
    device.dispatch.destroy_pipeline = stubDestroyPipeline;
    device.dispatch.create_sampler = stubCreateSampler;
    device.dispatch.destroy_sampler = stubDestroySampler;
    device.dispatch.create_image = stubCreateImage;
    device.dispatch.destroy_image = stubDestroyImage;
    device.dispatch.get_image_memory_requirements = stubImageRequirements;
    device.dispatch.bind_image_memory = stubBindImageMemory;
    device.dispatch.create_image_view = stubCreateImageView;
    device.dispatch.destroy_image_view = stubDestroyImageView;
    device.dispatch.create_buffer = stubCreateBuffer;
    device.dispatch.destroy_buffer = stubDestroyBuffer;
    device.dispatch.get_buffer_memory_requirements = stubBufferRequirements;
    device.dispatch.bind_buffer_memory = stubBindBufferMemory;
    device.dispatch.allocate_memory = stubAllocateMemory;
    device.dispatch.free_memory = stubFreeMemory;
    device.dispatch.map_memory = stubMapMemory;
    device.dispatch.unmap_memory = stubUnmapMemory;
    device.dispatch.flush_mapped_memory_ranges = stubFlushMappedMemoryRanges;
    device.dispatch.invalidate_mapped_memory_ranges = stubInvalidateMappedMemoryRanges;
    device.dispatch.cmd_pipeline_barrier = stubCmdPipelineBarrier;
    device.dispatch.cmd_copy_buffer = stubCmdCopyBuffer;
    device.dispatch.create_framebuffer = stubCreateFramebuffer;
    device.dispatch.destroy_framebuffer = stubDestroyFramebuffer;
    device.dispatch.create_command_pool = stubCreateCommandPool;
    device.dispatch.destroy_command_pool = stubDestroyCommandPool;
    device.dispatch.reset_command_pool = stubResetCommandPool;
    device.dispatch.allocate_command_buffers = stubAllocateCommandBuffers;
    device.dispatch.free_command_buffers = stubFreeCommandBuffers;
    device.dispatch.create_fence = stubCreateFence;
    device.dispatch.destroy_fence = stubDestroyFence;
    device.dispatch.reset_fences = stubResetFences;
    device.dispatch.wait_for_fences = stubWaitForFences;
    device.dispatch.get_fence_status = stubGetFenceStatus;
    device.dispatch.create_semaphore = stubCreateSemaphore;
    device.dispatch.destroy_semaphore = stubDestroySemaphore;
    device.dispatch.wait_semaphores = stubWaitSemaphores;
    device.dispatch.signal_semaphore = stubSignalSemaphore;
    device.dispatch.cmd_bind_pipeline = stubCmdBindPipeline;
    device.dispatch.cmd_bind_descriptor_sets = stubCmdBindDescriptorSets;
    device.dispatch.cmd_bind_vertex_buffers = stubCmdBindVertexBuffers;
    device.dispatch.cmd_push_constants = stubCmdPushConstants;
    device.dispatch.cmd_set_viewport = stubCmdSetViewport;
    device.dispatch.cmd_set_scissor = stubCmdSetScissor;
    device.dispatch.cmd_draw = stubCmdDraw;
    device.dispatch.cmd_copy_buffer_to_image = stubCmdCopyBufferToImage;
    device.dispatch.cmd_copy_image_to_buffer = stubCmdCopyImageToBuffer;
    device.dispatch.begin_command_buffer = stubBeginCommandBuffer;
    device.dispatch.end_command_buffer = stubEndCommandBuffer;
}

fn stubDestroyDevice(_: types.VkDevice, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {}

fn stubGetDeviceQueue(_: types.VkDevice, _: u32, _: u32, out_queue: *types.VkQueue) callconv(.c) void {
    out_queue.* = fake_queue;
}

fn stubQueueSubmit(_: types.VkQueue, _: u32, _: ?[*]const types.VkSubmitInfo, _: ?types.VkFence) callconv(.c) types.VkResult {
    return .SUCCESS;
}

fn stubQueueWaitIdle(_: types.VkQueue) callconv(.c) types.VkResult {
    return .SUCCESS;
}

fn stubCreateDescriptorSetLayout(_: types.VkDevice, _: *const types.VkDescriptorSetLayoutCreateInfo, _: ?*const types.VkAllocationCallbacks, out_layout: *types.VkDescriptorSetLayout) callconv(.c) types.VkResult {
    out_layout.* = makeHandle(types.VkDescriptorSetLayout);
    return .SUCCESS;
}

fn stubDestroyDescriptorSetLayout(_: types.VkDevice, _: types.VkDescriptorSetLayout, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {}

fn stubCreateDescriptorPool(_: types.VkDevice, _: *const types.VkDescriptorPoolCreateInfo, _: ?*const types.VkAllocationCallbacks, out_pool: *types.VkDescriptorPool) callconv(.c) types.VkResult {
    out_pool.* = makeHandle(types.VkDescriptorPool);
    return .SUCCESS;
}

fn stubDestroyDescriptorPool(_: types.VkDevice, _: types.VkDescriptorPool, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {}

fn stubAllocateDescriptorSets(_: types.VkDevice, info: *const types.VkDescriptorSetAllocateInfo, sets: [*]types.VkDescriptorSet) callconv(.c) types.VkResult {
    const count: usize = @intCast(info.descriptorSetCount);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        sets[i] = makeHandle(types.VkDescriptorSet);
    }
    return .SUCCESS;
}

fn stubFreeDescriptorSets(_: types.VkDevice, _: types.VkDescriptorPool, _: u32, _: [*]const types.VkDescriptorSet) callconv(.c) types.VkResult {
    return .SUCCESS;
}

fn stubUpdateDescriptorSets(_: types.VkDevice, _: u32, _: ?[*]const types.VkWriteDescriptorSet, _: u32, _: ?[*]const types.VkCopyDescriptorSet) callconv(.c) void {}

fn stubCreatePipelineLayout(_: types.VkDevice, _: *const types.VkPipelineLayoutCreateInfo, _: ?*const types.VkAllocationCallbacks, out_layout: *types.VkPipelineLayout) callconv(.c) types.VkResult {
    out_layout.* = makeHandle(types.VkPipelineLayout);
    return .SUCCESS;
}

fn stubDestroyPipelineLayout(_: types.VkDevice, _: types.VkPipelineLayout, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {}

fn stubCreateRenderPass(_: types.VkDevice, _: *const types.VkRenderPassCreateInfo, _: ?*const types.VkAllocationCallbacks, out_pass: *types.VkRenderPass) callconv(.c) types.VkResult {
    out_pass.* = makeHandle(types.VkRenderPass);
    return .SUCCESS;
}

fn stubDestroyRenderPass(_: types.VkDevice, _: types.VkRenderPass, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {}

fn stubCreateShaderModule(_: types.VkDevice, info: *const types.VkShaderModuleCreateInfo, _: ?*const types.VkAllocationCallbacks, out_module: *types.VkShaderModule) callconv(.c) types.VkResult {
    std.debug.assert(info.codeSize > 0);
    out_module.* = makeHandle(types.VkShaderModule);
    return .SUCCESS;
}

fn stubDestroyShaderModule(_: types.VkDevice, _: types.VkShaderModule, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {}

fn stubCreateGraphicsPipelines(_: types.VkDevice, _: types.VkPipelineCache, count: u32, _: [*]const types.VkGraphicsPipelineCreateInfo, _: ?*const types.VkAllocationCallbacks, out_pipelines: [*]types.VkPipeline) callconv(.c) types.VkResult {
    std.debug.assert(count == 1);
    out_pipelines[0] = makeHandle(types.VkPipeline);
    return .SUCCESS;
}

fn stubDestroyPipeline(_: types.VkDevice, _: types.VkPipeline, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {}

fn stubCreateSampler(_: types.VkDevice, _: *const types.VkSamplerCreateInfo, _: ?*const types.VkAllocationCallbacks, out_sampler: *types.VkSampler) callconv(.c) types.VkResult {
    out_sampler.* = makeHandle(types.VkSampler);
    return .SUCCESS;
}

fn stubDestroySampler(_: types.VkDevice, _: types.VkSampler, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {}

fn stubCreateImage(_: types.VkDevice, _: *const types.VkImageCreateInfo, _: ?*const types.VkAllocationCallbacks, out_image: *types.VkImage) callconv(.c) types.VkResult {
    out_image.* = makeHandle(types.VkImage);
    return .SUCCESS;
}

fn stubDestroyImage(_: types.VkDevice, _: types.VkImage, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {}

fn stubImageRequirements(_: types.VkDevice, _: types.VkImage, requirements: *types.VkMemoryRequirements) callconv(.c) void {
    requirements.* = types.VkMemoryRequirements{
        .size = 4096,
        .alignment = 256,
        .memoryTypeBits = 0b11,
    };
}

fn stubBindImageMemory(_: types.VkDevice, _: types.VkImage, _: types.VkDeviceMemory, _: types.VkDeviceSize) callconv(.c) types.VkResult {
    return .SUCCESS;
}

fn stubCreateImageView(_: types.VkDevice, _: *const types.VkImageViewCreateInfo, _: ?*const types.VkAllocationCallbacks, out_view: *types.VkImageView) callconv(.c) types.VkResult {
    out_view.* = makeHandle(types.VkImageView);
    return .SUCCESS;
}

fn stubDestroyImageView(_: types.VkDevice, _: types.VkImageView, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {}

fn stubCreateBuffer(_: types.VkDevice, info: *const types.VkBufferCreateInfo, _: ?*const types.VkAllocationCallbacks, out_buffer: *types.VkBuffer) callconv(.c) types.VkResult {
    std.debug.assert(info.size > 0);
    out_buffer.* = makeHandle(types.VkBuffer);
    return .SUCCESS;
}

fn stubDestroyBuffer(_: types.VkDevice, _: types.VkBuffer, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {}

fn stubBufferRequirements(_: types.VkDevice, _: types.VkBuffer, requirements: *types.VkMemoryRequirements) callconv(.c) void {
    requirements.* = types.VkMemoryRequirements{
        .size = 2048,
        .alignment = 256,
        .memoryTypeBits = 0b11,
    };
}

fn stubBindBufferMemory(_: types.VkDevice, _: types.VkBuffer, _: types.VkDeviceMemory, _: types.VkDeviceSize) callconv(.c) types.VkResult {
    return .SUCCESS;
}

fn stubAllocateMemory(_: types.VkDevice, info: *const types.VkMemoryAllocateInfo, _: ?*const types.VkAllocationCallbacks, out_memory: *types.VkDeviceMemory) callconv(.c) types.VkResult {
    out_memory.* = @as(types.VkDeviceMemory, @ptrFromInt(@as(usize, info.allocationSize) + 0xCAFE));
    return .SUCCESS;
}

fn stubFreeMemory(_: types.VkDevice, _: types.VkDeviceMemory, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {}

fn stubMapMemory(_: types.VkDevice, _: types.VkDeviceMemory, _: types.VkDeviceSize, _: types.VkDeviceSize, _: types.VkMemoryMapFlags, data: *?*anyopaque) callconv(.c) types.VkResult {
    data.* = @as(*anyopaque, @ptrCast(mapped_storage[0..].ptr));
    return .SUCCESS;
}

fn stubUnmapMemory(_: types.VkDevice, _: types.VkDeviceMemory) callconv(.c) void {}

fn stubFlushMappedMemoryRanges(_: types.VkDevice, _: u32, _: [*]const types.VkMappedMemoryRange) callconv(.c) types.VkResult {
    return .SUCCESS;
}

fn stubInvalidateMappedMemoryRanges(_: types.VkDevice, _: u32, _: [*]const types.VkMappedMemoryRange) callconv(.c) types.VkResult {
    return .SUCCESS;
}

fn stubCreateFramebuffer(_: types.VkDevice, _: *const types.VkFramebufferCreateInfo, _: ?*const types.VkAllocationCallbacks, out_framebuffer: *types.VkFramebuffer) callconv(.c) types.VkResult {
    out_framebuffer.* = makeHandle(types.VkFramebuffer);
    return .SUCCESS;
}

fn stubDestroyFramebuffer(_: types.VkDevice, _: types.VkFramebuffer, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {}

fn stubCreateCommandPool(_: types.VkDevice, _: *const types.VkCommandPoolCreateInfo, _: ?*const types.VkAllocationCallbacks, out_pool: *types.VkCommandPool) callconv(.c) types.VkResult {
    out_pool.* = makeHandle(types.VkCommandPool);
    return .SUCCESS;
}

fn stubDestroyCommandPool(_: types.VkDevice, _: types.VkCommandPool, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {}

fn stubResetCommandPool(_: types.VkDevice, _: types.VkCommandPool, _: types.VkCommandPoolResetFlags) callconv(.c) types.VkResult {
    return .SUCCESS;
}

fn stubAllocateCommandBuffers(_: types.VkDevice, info: *const types.VkCommandBufferAllocateInfo, buffers: [*]types.VkCommandBuffer) callconv(.c) types.VkResult {
    const count: usize = @intCast(info.commandBufferCount);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        buffers[i] = makeHandle(types.VkCommandBuffer);
    }
    return .SUCCESS;
}

fn stubFreeCommandBuffers(_: types.VkDevice, _: types.VkCommandPool, _: u32, _: [*]const types.VkCommandBuffer) callconv(.c) void {}

fn stubCreateFence(_: types.VkDevice, _: *const types.VkFenceCreateInfo, _: ?*const types.VkAllocationCallbacks, out_fence: *types.VkFence) callconv(.c) types.VkResult {
    out_fence.* = makeHandle(types.VkFence);
    return .SUCCESS;
}

fn stubDestroyFence(_: types.VkDevice, _: types.VkFence, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {}

fn stubResetFences(_: types.VkDevice, _: u32, _: *const types.VkFence) callconv(.c) types.VkResult {
    return .SUCCESS;
}

fn stubWaitForFences(_: types.VkDevice, _: u32, _: *const types.VkFence, _: types.VkBool32, _: u64) callconv(.c) types.VkResult {
    return .SUCCESS;
}

fn stubGetFenceStatus(_: types.VkDevice, _: types.VkFence) callconv(.c) types.VkResult {
    return .SUCCESS;
}

fn stubCreateSemaphore(_: types.VkDevice, _: *const types.VkSemaphoreCreateInfo, _: ?*const types.VkAllocationCallbacks, out_semaphore: *types.VkSemaphore) callconv(.c) types.VkResult {
    out_semaphore.* = makeHandle(types.VkSemaphore);
    return .SUCCESS;
}

fn stubDestroySemaphore(_: types.VkDevice, _: types.VkSemaphore, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {}

fn stubWaitSemaphores(_: types.VkDevice, _: *const types.VkSemaphoreWaitInfo, _: u64) callconv(.c) types.VkResult {
    return .SUCCESS;
}

fn stubSignalSemaphore(_: types.VkDevice, _: *const types.VkSemaphoreSignalInfo) callconv(.c) types.VkResult {
    return .SUCCESS;
}

fn stubCmdBindPipeline(_: types.VkCommandBuffer, _: types.VkPipelineBindPoint, _: types.VkPipeline) callconv(.c) void {}

fn stubCmdBindDescriptorSets(_: types.VkCommandBuffer, _: types.VkPipelineBindPoint, _: types.VkPipelineLayout, _: u32, _: u32, _: *const types.VkDescriptorSet, _: u32, _: ?[*]const u32) callconv(.c) void {}

fn stubCmdBindVertexBuffers(_: types.VkCommandBuffer, _: u32, _: u32, _: *const types.VkBuffer, _: *const types.VkDeviceSize) callconv(.c) void {}

fn stubCmdPushConstants(_: types.VkCommandBuffer, _: types.VkPipelineLayout, _: types.VkShaderStageFlags, _: u32, _: u32, _: ?*const anyopaque) callconv(.c) void {}

fn stubCmdSetViewport(_: types.VkCommandBuffer, _: u32, _: u32, _: *const types.VkViewport) callconv(.c) void {}

fn stubCmdSetScissor(_: types.VkCommandBuffer, _: u32, _: u32, _: *const types.VkRect2D) callconv(.c) void {}

fn stubCmdDraw(_: types.VkCommandBuffer, _: u32, _: u32, _: u32, _: u32) callconv(.c) void {}

fn stubCmdCopyBuffer(_: types.VkCommandBuffer, _: types.VkBuffer, _: types.VkBuffer, _: u32, _: *const types.VkBufferCopy) callconv(.c) void {}

fn stubCmdCopyBufferToImage(_: types.VkCommandBuffer, _: types.VkBuffer, _: types.VkImage, _: types.VkImageLayout, _: u32, _: *const types.VkBufferImageCopy) callconv(.c) void {}

fn stubCmdCopyImageToBuffer(_: types.VkCommandBuffer, _: types.VkImage, _: types.VkImageLayout, _: types.VkBuffer, _: u32, _: *const types.VkBufferImageCopy) callconv(.c) void {}

fn stubCmdPipelineBarrier(_: types.VkCommandBuffer, _: types.VkPipelineStageFlags, _: types.VkPipelineStageFlags, _: types.VkDependencyFlags, _: u32, _: ?[*]const types.VkMemoryBarrier, _: u32, _: ?[*]const types.VkBufferMemoryBarrier, _: u32, _: ?[*]const types.VkImageMemoryBarrier) callconv(.c) void {}

fn stubBeginCommandBuffer(_: types.VkCommandBuffer, _: *const types.VkCommandBufferBeginInfo) callconv(.c) types.VkResult {
    return .SUCCESS;
}

fn stubEndCommandBuffer(_: types.VkCommandBuffer) callconv(.c) types.VkResult {
    return .SUCCESS;
}

fn makeMemoryProps() types.VkPhysicalDeviceMemoryProperties {
    var props = std.mem.zeroes(types.VkPhysicalDeviceMemoryProperties);
    props.memoryTypeCount = 2;
    props.memoryTypes[0] = .{ .propertyFlags = types.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, .heapIndex = 0 };
    props.memoryTypes[1] = .{ .propertyFlags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, .heapIndex = 1 };
    props.memoryHeapCount = 2;
    props.memoryHeaps[0] = .{ .size = 2 * 1024 * 1024 * 1024, .flags = types.VK_MEMORY_HEAP_DEVICE_LOCAL_BIT };
    props.memoryHeaps[1] = .{ .size = 1 * 1024 * 1024 * 1024, .flags = 0 };
    return props;
}

fn orthoProjection(width: f32, height: f32) [16]f32 {
    const left: f32 = 0.0;
    const right = width;
    const top = 0.0;
    const bottom = height;
    const near: f32 = -1.0;
    const far: f32 = 1.0;

    return .{
        2.0 / (right - left),             0.0,                              0.0,                          0.0,
        0.0,                              2.0 / (top - bottom),             0.0,                          0.0,
        0.0,                              0.0,                              -2.0 / (far - near),          0.0,
        -(right + left) / (right - left), -(top + bottom) / (top - bottom), -(far + near) / (far - near), 1.0,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Zeus simple text telemetry demo (mocked)\n", .{});

    var device = device_mod.Device{
        .allocator = allocator,
        .loader = undefined,
        .dispatch = std.mem.zeroes(loader.DeviceDispatch),
        .handle = fake_device_handle,
        .allocation_callbacks = null,
        .default_queue_family = 0,
        .default_queue = fake_queue,
    };
    setupMockDispatch(&device);
    defer device.destroy();

    var renderer = try TextRenderer.init(allocator, &device, .{
        .extent = .{ .width = 1280, .height = 720 },
        .surface_format = types.VK_FORMAT_B8G8R8A8_SRGB,
        .memory_props = makeMemoryProps(),
        .frames_in_flight = 1,
        .max_instances = 512,
        .batch_target = 256,
        .batch_min = 128,
    });
    defer renderer.deinit();

    try renderer.beginFrame(0);
    const projection = orthoProjection(1280.0, 720.0);
    try renderer.setProjection(projection[0..]);

    const quads = [_]TextQuad{
        .{ .position = .{ 100.0, 320.0 }, .size = .{ 24.0, 32.0 }, .atlas_rect = .{ 0.0, 0.0, 0.1, 0.1 }, .color = .{ 1.0, 0.2, 0.2, 1.0 } },
        .{ .position = .{ 140.0, 320.0 }, .size = .{ 24.0, 32.0 }, .atlas_rect = .{ 0.1, 0.0, 0.1, 0.1 }, .color = .{ 0.2, 1.0, 0.2, 1.0 } },
        .{ .position = .{ 180.0, 320.0 }, .size = .{ 24.0, 32.0 }, .atlas_rect = .{ 0.2, 0.0, 0.1, 0.1 }, .color = .{ 0.2, 0.6, 1.0, 1.0 } },
        .{ .position = .{ 220.0, 320.0 }, .size = .{ 24.0, 32.0 }, .atlas_rect = .{ 0.3, 0.0, 0.1, 0.1 }, .color = .{ 1.0, 0.9, 0.2, 1.0 } },
    };

    try renderer.queueQuads(quads[0..]);

    try renderer.encode(fake_command_buffer);
    renderer.endFrame();

    const stats = try renderer.frameStats(0);
    std.debug.print(
        "Captured telemetry -> glyphs: {d}, draws: {d}, atlas uploads: {d}\n",
        .{ stats.glyph_count, stats.draw_count, stats.atlas_uploads },
    );
    std.debug.print(
        "CPU encode time: {d} ns, transfer queue time: {d} ns\n",
        .{ stats.encode_cpu_ns, stats.transfer_cpu_ns },
    );
    std.debug.print("Transfer queue used this frame: {s}\n", .{if (stats.used_transfer_queue) "yes" else "no"});

    if (try renderer.frameSyncInfo(0)) |sync_info| {
        std.debug.print(
            "Wait on timeline semaphore {p} value {d} at stage mask 0x{x}\n",
            .{ sync_info.semaphore, sync_info.value, sync_info.stage_mask },
        );
    } else {
        std.debug.print("No transfer semaphore wait needed for this frame.\n", .{});
    }

    renderer.releaseAtlasUploads();

    std.debug.print("Example complete – combine this with a real render pass + queue submit in your application.\n", .{});
}
