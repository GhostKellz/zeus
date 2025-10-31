const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const buffer = @import("buffer.zig");
const descriptor = @import("descriptor.zig");
const render_pass = @import("render_pass.zig");
const pipeline = @import("pipeline.zig");
const sampler_mod = @import("sampler.zig");
const image = @import("image.zig");
const shader = @import("shader.zig");
const loader = @import("loader.zig");

const text_vert_spv align(@alignOf(u32)) = @embedFile("../../shaders/text.vert.spv");
const text_frag_spv align(@alignOf(u32)) = @embedFile("../../shaders/text.frag.spv");
const text_vert_code = std.mem.bytesAsSlice(u32, text_vert_spv);
const text_frag_code = std.mem.bytesAsSlice(u32, text_frag_spv);
const shader_entry_point: [:0]const u8 = "main";

pub const InitOptions = struct {
    extent: types.VkExtent2D,
    surface_format: types.VkFormat,
    memory_props: types.VkPhysicalDeviceMemoryProperties,
    frames_in_flight: u32 = 2,
    max_instances: u32 = 1024,
    uniform_buffer_size: types.VkDeviceSize = 64,
    atlas_extent: types.VkExtent2D = .{ .width = 1024, .height = 1024 },
    atlas_format: types.VkFormat = .R8_UNORM,
};

pub const TextRenderer = struct {
    allocator: std.mem.Allocator,
    device: *device_mod.Device,
    memory_props: types.VkPhysicalDeviceMemoryProperties,
    extent: types.VkExtent2D,
    surface_format: types.VkFormat,
    frames_in_flight: u32,
    max_instances: u32,
    uniform_buffer_size: types.VkDeviceSize,

    render_pass: render_pass.RenderPass,
    pipeline_layout: pipeline.PipelineLayout,
    pipeline: pipeline.GraphicsPipeline,

    descriptor_pool: types.VkDescriptorPool,
    descriptor_set_layout: types.VkDescriptorSetLayout,
    descriptor_sets: descriptor.DescriptorSetAllocation,

    sampler: sampler_mod.Sampler,
    atlas: image.ManagedImage,

    vertex_buffer: buffer.ManagedBuffer,
    instance_buffer: buffer.ManagedBuffer,
    uniform_buffers: []buffer.ManagedBuffer,

    pub fn init(allocator: std.mem.Allocator, device: *device_mod.Device, options: InitOptions) errors.Error!TextRenderer {
        std.debug.assert(options.frames_in_flight > 0);
        std.debug.assert(options.max_instances > 0);
        std.debug.assert(options.uniform_buffer_size > 0);

        const frame_count: usize = @intCast(options.frames_in_flight);

        const descriptor_bindings = [_]types.VkDescriptorSetLayoutBinding{
            .{
                .binding = 0,
                .descriptorType = .UNIFORM_BUFFER,
                .descriptorCount = 1,
                .stageFlags = types.VK_SHADER_STAGE_VERTEX_BIT,
            },
            .{
                .binding = 1,
                .descriptorType = .COMBINED_IMAGE_SAMPLER,
                .descriptorCount = 1,
                .stageFlags = types.VK_SHADER_STAGE_FRAGMENT_BIT,
            },
        };

        const descriptor_set_layout = try descriptor.createDescriptorSetLayout(device, descriptor_bindings[0..]);
        errdefer descriptor.destroyDescriptorSetLayout(device, descriptor_set_layout);

        const pool_sizes = [_]types.VkDescriptorPoolSize{
            .{ .descriptorType = .UNIFORM_BUFFER, .descriptorCount = options.frames_in_flight },
            .{ .descriptorType = .COMBINED_IMAGE_SAMPLER, .descriptorCount = options.frames_in_flight },
        };

        const descriptor_pool = try descriptor.createDescriptorPool(device, .{
            .max_sets = options.frames_in_flight,
            .pool_sizes = pool_sizes[0..],
            .flags = types.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
        });
        errdefer descriptor.destroyDescriptorPool(device, descriptor_pool);

        const layout_handles = try allocator.alloc(types.VkDescriptorSetLayout, frame_count);
        defer allocator.free(layout_handles);
        for (layout_handles) |*slot| slot.* = descriptor_set_layout;

        var descriptor_sets = try descriptor.allocateDescriptorSets(device, descriptor_pool, layout_handles);
        errdefer descriptor_sets.free(device, descriptor_pool) catch {};

        var pipeline_layout = try pipeline.PipelineLayout.init(device, .{ .set_layouts = &.{descriptor_set_layout} });
        errdefer pipeline_layout.deinit();

        var builder = render_pass.RenderPassBuilder.init(allocator);
        defer builder.deinit();
        _ = try builder.addColorAttachment(options.surface_format, types.VkAttachmentLoadOp.LOAD);
        try builder.addDependency(types.VkSubpassDependency{
            .srcSubpass = types.VK_SUBPASS_EXTERNAL,
            .dstSubpass = 0,
            .srcStageMask = types.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .dstStageMask = types.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .srcAccessMask = 0,
            .dstAccessMask = types.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        });

        var render_pass_obj = try render_pass.RenderPass.init(device, &builder);
        errdefer render_pass_obj.deinit();

        var vert_module = try shader.ShaderModule.init(device, text_vert_code);
        defer vert_module.deinit();
        var frag_module = try shader.ShaderModule.init(device, text_frag_code);
        defer frag_module.deinit();

        const shader_stages = [_]types.VkPipelineShaderStageCreateInfo{
            shader.createShaderStage(vert_module.handle.?, .VERTEX_BIT, shader_entry_point.ptr),
            shader.createShaderStage(frag_module.handle.?, .FRAGMENT_BIT, shader_entry_point.ptr),
        };

        var graphics_pipeline = try pipeline.GraphicsPipeline.init(device, .{
            .layout = pipeline_layout.handle.?,
            .render_pass = render_pass_obj.handle.?,
            .shader_stages = shader_stages[0..],
        });
        errdefer graphics_pipeline.deinit();

        var text_sampler = try sampler_mod.Sampler.init(device, .{
            .mag_filter = .LINEAR,
            .min_filter = .LINEAR,
            .mipmap_mode = .LINEAR,
            .address_mode_u = .CLAMP_TO_EDGE,
            .address_mode_v = .CLAMP_TO_EDGE,
            .address_mode_w = .CLAMP_TO_EDGE,
            .max_lod = 0.0,
            .min_lod = 0.0,
        });
        errdefer text_sampler.deinit();

        var atlas = try image.createManagedImage(device, options.memory_props, .{
            .image = .{
                .format = options.atlas_format,
                .extent = types.VkExtent3D{
                    .width = options.atlas_extent.width,
                    .height = options.atlas_extent.height,
                    .depth = 1,
                },
                .usage = types.VK_IMAGE_USAGE_SAMPLED_BIT | types.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
                .initial_layout = types.VkImageLayout.UNDEFINED,
            },
            .aspect_mask = types.VK_IMAGE_ASPECT_COLOR_BIT,
            .view_type = .@"2D",
        });
        errdefer atlas.deinit();

        const float_size = @sizeOf(f32);
        const vertex_stride: types.VkDeviceSize = 2 * float_size;
        const quad_vertex_count: types.VkDeviceSize = 4;
        const vertex_buffer_size = vertex_stride * quad_vertex_count;

        var vertex_buffer = try buffer.createManagedBuffer(device, options.memory_props, vertex_buffer_size, types.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, .{
            .filter = .{
                .required_flags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT,
                .preferred_flags = types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            },
        });
        errdefer vertex_buffer.deinit();

        const quad_vertices = [_]f32{ 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0 };
        try vertex_buffer.write(std.mem.sliceAsBytes(quad_vertices[0..]), 0);

        const instance_stride: types.VkDeviceSize = (2 + 2 + 4 + 4) * float_size;
        const instance_buffer_size = instance_stride * @as(types.VkDeviceSize, options.max_instances);

        var instance_buffer = try buffer.createManagedBuffer(device, options.memory_props, instance_buffer_size, types.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, .{
            .filter = .{
                .required_flags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT,
                .preferred_flags = types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            },
        });
        errdefer instance_buffer.deinit();

        var uniform_buffers = try allocator.alloc(buffer.ManagedBuffer, frame_count);
        var created_uniform_buffers: usize = 0;
        errdefer {
            for (uniform_buffers[0..created_uniform_buffers]) |*buf| buf.deinit();
            allocator.free(uniform_buffers);
        }

        while (created_uniform_buffers < frame_count) : (created_uniform_buffers += 1) {
            uniform_buffers[created_uniform_buffers] = try buffer.createManagedBuffer(device, options.memory_props, options.uniform_buffer_size, types.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, .{
                .filter = .{
                    .required_flags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT,
                    .preferred_flags = types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                },
            });
        }

        const atlas_view = atlas.view orelse return errors.Error.FeatureNotPresent;
        const sampler_handle = text_sampler.handle orelse return errors.Error.FeatureNotPresent;

        for (descriptor_sets.sets, 0..) |set_handle, i| {
            var buffer_info = types.VkDescriptorBufferInfo{
                .buffer = uniform_buffers[i].buffer,
                .offset = 0,
                .range = options.uniform_buffer_size,
            };

            var image_info = types.VkDescriptorImageInfo{
                .sampler = sampler_handle,
                .imageView = atlas_view,
                .imageLayout = types.VkImageLayout.SHADER_READ_ONLY_OPTIMAL,
            };

            var writes = [_]types.VkWriteDescriptorSet{
                .{
                    .dstSet = set_handle,
                    .dstBinding = 0,
                    .descriptorType = .UNIFORM_BUFFER,
                    .descriptorCount = 1,
                    .pBufferInfo = &buffer_info,
                },
                .{
                    .dstSet = set_handle,
                    .dstBinding = 1,
                    .descriptorType = .COMBINED_IMAGE_SAMPLER,
                    .descriptorCount = 1,
                    .pImageInfo = &image_info,
                },
            };

            descriptor.updateDescriptorSets(device, writes[0..], &.{});
        }

        return TextRenderer{
            .allocator = allocator,
            .device = device,
            .memory_props = options.memory_props,
            .extent = options.extent,
            .surface_format = options.surface_format,
            .frames_in_flight = options.frames_in_flight,
            .max_instances = options.max_instances,
            .uniform_buffer_size = options.uniform_buffer_size,
            .render_pass = render_pass_obj,
            .pipeline_layout = pipeline_layout,
            .pipeline = graphics_pipeline,
            .descriptor_pool = descriptor_pool,
            .descriptor_set_layout = descriptor_set_layout,
            .descriptor_sets = descriptor_sets,
            .sampler = text_sampler,
            .atlas = atlas,
            .vertex_buffer = vertex_buffer,
            .instance_buffer = instance_buffer,
            .uniform_buffers = uniform_buffers,
        };
    }

    pub fn deinit(self: *TextRenderer) void {
        for (self.uniform_buffers) |*buf| {
            buf.deinit();
        }
        if (self.uniform_buffers.len > 0) {
            self.allocator.free(self.uniform_buffers);
            self.uniform_buffers = &.{};
        }

        self.instance_buffer.deinit();
        self.vertex_buffer.deinit();

        self.atlas.deinit();
        self.sampler.deinit();

        if (self.descriptor_sets.len() > 0) {
            self.descriptor_sets.free(self.device, self.descriptor_pool) catch {};
        }
        self.descriptor_sets.deinit();
        descriptor.destroyDescriptorPool(self.device, self.descriptor_pool);
        descriptor.destroyDescriptorSetLayout(self.device, self.descriptor_set_layout);

        self.pipeline.deinit();
        self.pipeline_layout.deinit();
        self.render_pass.deinit();
    }
};

const TestCapture = struct {
    pub var descriptor_layout_calls: usize = 0;
    pub var descriptor_pool_calls: usize = 0;
    pub var descriptor_set_count: usize = 0;
    pub var pipeline_layout_calls: usize = 0;
    pub var render_pass_create_calls: usize = 0;
    pub var shader_module_create_calls: usize = 0;
    pub var pipeline_create_calls: usize = 0;
    pub var pipeline_stage_count: u32 = 0;
    pub var sampler_create_calls: usize = 0;
    pub var image_create_calls: usize = 0;
    pub var image_view_create_calls: usize = 0;
    pub var buffer_create_calls: usize = 0;
    pub var update_descriptor_calls: usize = 0;
    pub var free_descriptor_calls: usize = 0;
    pub var destroy_pool_calls: usize = 0;
    pub var destroy_layout_calls: usize = 0;
    pub var destroy_pipeline_calls: usize = 0;
    pub var destroy_pipeline_layout_calls: usize = 0;
    pub var destroy_render_pass_calls: usize = 0;
    pub var destroy_sampler_calls: usize = 0;
    pub var destroy_image_calls: usize = 0;
    pub var destroy_image_view_calls: usize = 0;
    pub var destroy_buffer_calls: usize = 0;
    pub var descriptor_write_uniform_ranges: [8]types.VkDeviceSize = [_]types.VkDeviceSize{0} ** 8;
    pub var descriptor_write_count: usize = 0;
    pub var last_buffer_size: types.VkDeviceSize = 0;
    pub var last_image_extent: types.VkExtent3D = .{ .width = 0, .height = 0, .depth = 0 };

    pub fn reset() void {
        descriptor_layout_calls = 0;
        descriptor_pool_calls = 0;
        descriptor_set_count = 0;
        pipeline_layout_calls = 0;
        render_pass_create_calls = 0;
        shader_module_create_calls = 0;
        pipeline_create_calls = 0;
        pipeline_stage_count = 0;
        sampler_create_calls = 0;
        image_create_calls = 0;
        image_view_create_calls = 0;
        buffer_create_calls = 0;
        update_descriptor_calls = 0;
        free_descriptor_calls = 0;
        destroy_pool_calls = 0;
        destroy_layout_calls = 0;
        destroy_pipeline_calls = 0;
        destroy_pipeline_layout_calls = 0;
        destroy_render_pass_calls = 0;
        destroy_sampler_calls = 0;
        destroy_image_calls = 0;
        destroy_image_view_calls = 0;
        destroy_buffer_calls = 0;
        descriptor_write_uniform_ranges = [_]types.VkDeviceSize{0} ** 8;
        descriptor_write_count = 0;
        last_buffer_size = 0;
        last_image_extent = .{ .width = 0, .height = 0, .depth = 0 };
        test_next_handle = 0x2000;
    }
};

var test_next_handle: usize = 0x2000;
var test_mapped_storage: [8192]u8 = undefined;

fn makeHandle(comptime T: type) T {
    test_next_handle += 0x10;
    return @as(T, @ptrFromInt(test_next_handle));
}

fn stubCreateDescriptorSetLayout(_: types.VkDevice, info: *const types.VkDescriptorSetLayoutCreateInfo, _: ?*const types.VkAllocationCallbacks, layout: *types.VkDescriptorSetLayout) callconv(.C) types.VkResult {
    TestCapture.descriptor_layout_calls += 1;
    std.debug.assert(info.bindingCount == 2);
    layout.* = makeHandle(types.VkDescriptorSetLayout);
    return .SUCCESS;
}

fn stubDestroyDescriptorSetLayout(_: types.VkDevice, _: types.VkDescriptorSetLayout, _: ?*const types.VkAllocationCallbacks) callconv(.C) void {
    TestCapture.destroy_layout_calls += 1;
}

fn stubCreateDescriptorPool(_: types.VkDevice, info: *const types.VkDescriptorPoolCreateInfo, _: ?*const types.VkAllocationCallbacks, pool: *types.VkDescriptorPool) callconv(.C) types.VkResult {
    TestCapture.descriptor_pool_calls += 1;
    std.debug.assert(info.maxSets > 0);
    pool.* = makeHandle(types.VkDescriptorPool);
    return .SUCCESS;
}

fn stubDestroyDescriptorPool(_: types.VkDevice, _: types.VkDescriptorPool, _: ?*const types.VkAllocationCallbacks) callconv(.C) void {
    TestCapture.destroy_pool_calls += 1;
}

fn stubAllocateDescriptorSets(_: types.VkDevice, info: *const types.VkDescriptorSetAllocateInfo, sets: [*]types.VkDescriptorSet) callconv(.C) types.VkResult {
    TestCapture.descriptor_set_count += info.descriptorSetCount;
    var i: usize = 0;
    while (i < info.descriptorSetCount) : (i += 1) {
        sets[i] = makeHandle(types.VkDescriptorSet);
    }
    return .SUCCESS;
}

fn stubFreeDescriptorSets(_: types.VkDevice, _: types.VkDescriptorPool, count: u32, _: [*]const types.VkDescriptorSet) callconv(.C) types.VkResult {
    if (count > 0) TestCapture.free_descriptor_calls += 1;
    return .SUCCESS;
}

fn stubUpdateDescriptorSets(_: types.VkDevice, write_count: u32, writes: ?[*]const types.VkWriteDescriptorSet, _: u32, _: ?[*]const types.VkCopyDescriptorSet) callconv(.C) void {
    if (writes) |ptr| {
        for (ptr[0..write_count], 0..) |write, idx| {
            TestCapture.update_descriptor_calls += 1;
            if (write.descriptorType == .UNIFORM_BUFFER and write.pBufferInfo) |infos| {
                TestCapture.descriptor_write_uniform_ranges[TestCapture.descriptor_write_count + idx] = infos[0].range;
            }
        }
        TestCapture.descriptor_write_count += write_count;
    }
}

fn stubCreatePipelineLayout(_: types.VkDevice, _: *const types.VkPipelineLayoutCreateInfo, _: ?*const types.VkAllocationCallbacks, layout: *types.VkPipelineLayout) callconv(.C) types.VkResult {
    TestCapture.pipeline_layout_calls += 1;
    layout.* = makeHandle(types.VkPipelineLayout);
    return .SUCCESS;
}

fn stubDestroyPipelineLayout(_: types.VkDevice, _: types.VkPipelineLayout, _: ?*const types.VkAllocationCallbacks) callconv(.C) void {
    TestCapture.destroy_pipeline_layout_calls += 1;
}

fn stubCreateRenderPass(_: types.VkDevice, info: *const types.VkRenderPassCreateInfo, _: ?*const types.VkAllocationCallbacks, render_pass_handle: *types.VkRenderPass) callconv(.C) types.VkResult {
    TestCapture.render_pass_create_calls += 1;
    std.debug.assert(info.attachmentCount == 1);
    render_pass_handle.* = makeHandle(types.VkRenderPass);
    return .SUCCESS;
}

fn stubDestroyRenderPass(_: types.VkDevice, _: types.VkRenderPass, _: ?*const types.VkAllocationCallbacks) callconv(.C) void {
    TestCapture.destroy_render_pass_calls += 1;
}

fn stubCreateShaderModule(_: types.VkDevice, info: *const types.VkShaderModuleCreateInfo, _: ?*const types.VkAllocationCallbacks, module: *types.VkShaderModule) callconv(.C) types.VkResult {
    TestCapture.shader_module_create_calls += 1;
    std.debug.assert(info.codeSize > 0);
    module.* = makeHandle(types.VkShaderModule);
    return .SUCCESS;
}

fn stubDestroyShaderModule(_: types.VkDevice, _: types.VkShaderModule, _: ?*const types.VkAllocationCallbacks) callconv(.C) void {}

fn stubCreateGraphicsPipelines(_: types.VkDevice, _: types.VkPipelineCache, count: u32, infos: [*]const types.VkGraphicsPipelineCreateInfo, _: ?*const types.VkAllocationCallbacks, pipelines: [*]types.VkPipeline) callconv(.C) types.VkResult {
    TestCapture.pipeline_create_calls += 1;
    std.debug.assert(count == 1);
    TestCapture.pipeline_stage_count = infos[0].stageCount;
    pipelines[0] = makeHandle(types.VkPipeline);
    return .SUCCESS;
}

fn stubDestroyPipeline(_: types.VkDevice, _: types.VkPipeline, _: ?*const types.VkAllocationCallbacks) callconv(.C) void {
    TestCapture.destroy_pipeline_calls += 1;
}

fn stubCreateSampler(_: types.VkDevice, _: *const types.VkSamplerCreateInfo, _: ?*const types.VkAllocationCallbacks, sampler_handle: *types.VkSampler) callconv(.C) types.VkResult {
    TestCapture.sampler_create_calls += 1;
    sampler_handle.* = makeHandle(types.VkSampler);
    return .SUCCESS;
}

fn stubDestroySampler(_: types.VkDevice, _: types.VkSampler, _: ?*const types.VkAllocationCallbacks) callconv(.C) void {
    TestCapture.destroy_sampler_calls += 1;
}

fn stubCreateImage(_: types.VkDevice, info: *const types.VkImageCreateInfo, _: ?*const types.VkAllocationCallbacks, image_handle: *types.VkImage) callconv(.C) types.VkResult {
    TestCapture.image_create_calls += 1;
    TestCapture.last_image_extent = info.extent;
    image_handle.* = makeHandle(types.VkImage);
    return .SUCCESS;
}

fn stubDestroyImage(_: types.VkDevice, _: types.VkImage, _: ?*const types.VkAllocationCallbacks) callconv(.C) void {
    TestCapture.destroy_image_calls += 1;
}

fn stubGetImageMemoryRequirements(_: types.VkDevice, _: types.VkImage, requirements: *types.VkMemoryRequirements) callconv(.C) void {
    requirements.* = types.VkMemoryRequirements{
        .size = 4096,
        .alignment = 256,
        .memoryTypeBits = 0b11,
    };
}

fn stubBindImageMemory(_: types.VkDevice, _: types.VkImage, _: types.VkDeviceMemory, _: types.VkDeviceSize) callconv(.C) types.VkResult {
    return .SUCCESS;
}

fn stubCreateImageView(_: types.VkDevice, _: *const types.VkImageViewCreateInfo, _: ?*const types.VkAllocationCallbacks, view: *types.VkImageView) callconv(.C) types.VkResult {
    TestCapture.image_view_create_calls += 1;
    view.* = makeHandle(types.VkImageView);
    return .SUCCESS;
}

fn stubDestroyImageView(_: types.VkDevice, _: types.VkImageView, _: ?*const types.VkAllocationCallbacks) callconv(.C) void {
    TestCapture.destroy_image_view_calls += 1;
}

fn stubCreateBuffer(_: types.VkDevice, info: *const types.VkBufferCreateInfo, _: ?*const types.VkAllocationCallbacks, buffer_handle: *types.VkBuffer) callconv(.C) types.VkResult {
    TestCapture.buffer_create_calls += 1;
    TestCapture.last_buffer_size = info.size;
    buffer_handle.* = makeHandle(types.VkBuffer);
    return .SUCCESS;
}

fn stubDestroyBuffer(_: types.VkDevice, _: types.VkBuffer, _: ?*const types.VkAllocationCallbacks) callconv(.C) void {
    TestCapture.destroy_buffer_calls += 1;
}

fn stubGetBufferMemoryRequirements(_: types.VkDevice, _: types.VkBuffer, requirements: *types.VkMemoryRequirements) callconv(.C) void {
    requirements.* = types.VkMemoryRequirements{
        .size = TestCapture.last_buffer_size,
        .alignment = 256,
        .memoryTypeBits = 0b11,
    };
}

fn stubBindBufferMemory(_: types.VkDevice, _: types.VkBuffer, _: types.VkDeviceMemory, _: types.VkDeviceSize) callconv(.C) types.VkResult {
    return .SUCCESS;
}

fn stubAllocateMemory(_: types.VkDevice, info: *const types.VkMemoryAllocateInfo, _: ?*const types.VkAllocationCallbacks, memory: *types.VkDeviceMemory) callconv(.C) types.VkResult {
    memory.* = @as(types.VkDeviceMemory, @ptrFromInt(info.allocationSize));
    return .SUCCESS;
}

fn stubFreeMemory(_: types.VkDevice, _: types.VkDeviceMemory, _: ?*const types.VkAllocationCallbacks) callconv(.C) void {}

fn stubMapMemory(_: types.VkDevice, _: types.VkDeviceMemory, _: types.VkDeviceSize, _: types.VkDeviceSize, _: types.VkMemoryMapFlags, data: *?*anyopaque) callconv(.C) types.VkResult {
    data.* = @as(*anyopaque, @ptrCast(test_mapped_storage[0..].ptr));
    return .SUCCESS;
}

fn stubUnmapMemory(_: types.VkDevice, _: types.VkDeviceMemory) callconv(.C) void {}

fn setupTestDispatch(device: *device_mod.Device) void {
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
    device.dispatch.get_image_memory_requirements = stubGetImageMemoryRequirements;
    device.dispatch.bind_image_memory = stubBindImageMemory;
    device.dispatch.create_image_view = stubCreateImageView;
    device.dispatch.destroy_image_view = stubDestroyImageView;
    device.dispatch.create_buffer = stubCreateBuffer;
    device.dispatch.destroy_buffer = stubDestroyBuffer;
    device.dispatch.get_buffer_memory_requirements = stubGetBufferMemoryRequirements;
    device.dispatch.bind_buffer_memory = stubBindBufferMemory;
    device.dispatch.allocate_memory = stubAllocateMemory;
    device.dispatch.free_memory = stubFreeMemory;
    device.dispatch.map_memory = stubMapMemory;
    device.dispatch.unmap_memory = stubUnmapMemory;
}

test "TextRenderer.init wires core Vulkan objects" {
    const fake_device_handle = @as(types.VkDevice, @ptrFromInt(@as(usize, 0x1000)));

    var device = device_mod.Device{
        .allocator = std.testing.allocator,
        .loader = undefined,
        .dispatch = std.mem.zeroes(loader.DeviceDispatch),
        .handle = fake_device_handle,
        .allocation_callbacks = null,
    };

    setupTestDispatch(&device);
    TestCapture.reset();

    var memory_props = std.mem.zeroes(types.VkPhysicalDeviceMemoryProperties);
    memory_props.memoryTypeCount = 2;
    memory_props.memoryTypes[0] = .{ .propertyFlags = types.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, .heapIndex = 0 };
    memory_props.memoryTypes[1] = .{ .propertyFlags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, .heapIndex = 1 };
    memory_props.memoryHeapCount = 2;
    memory_props.memoryHeaps[0] = .{ .size = 1024 * 1024 * 1024, .flags = types.VK_MEMORY_HEAP_DEVICE_LOCAL_BIT };
    memory_props.memoryHeaps[1] = .{ .size = 512 * 1024 * 1024, .flags = 0 };

    var renderer = try TextRenderer.init(std.testing.allocator, &device, .{
        .extent = .{ .width = 800, .height = 600 },
        .surface_format = .B8G8R8A8_SRGB,
        .memory_props = memory_props,
        .frames_in_flight = 2,
        .max_instances = 128,
        .uniform_buffer_size = 64,
        .atlas_extent = .{ .width = 256, .height = 256 },
        .atlas_format = .R8_UNORM,
    });

    try std.testing.expectEqual(@as(u32, 2), renderer.frames_in_flight);
    try std.testing.expectEqual(@as(usize, 2), renderer.uniform_buffers.len);
    try std.testing.expectEqual(@as(usize, 2), renderer.descriptor_sets.len());
    try std.testing.expectEqual(types.VK_FORMAT_B8G8R8A8_SRGB, renderer.surface_format);

    try std.testing.expectEqual(@as(usize, 1), TestCapture.descriptor_layout_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.descriptor_pool_calls);
    try std.testing.expectEqual(@as(usize, 2), TestCapture.descriptor_set_count);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.pipeline_layout_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.render_pass_create_calls);
    try std.testing.expectEqual(@as(usize, 2), TestCapture.shader_module_create_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.pipeline_create_calls);
    try std.testing.expectEqual(@as(u32, 2), TestCapture.pipeline_stage_count);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.sampler_create_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.image_create_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.image_view_create_calls);
    try std.testing.expectEqual(@as(usize, 4), TestCapture.buffer_create_calls);

    try std.testing.expectEqual(@as(usize, 4), TestCapture.update_descriptor_calls);
    try std.testing.expectEqual(@as(types.VkDeviceSize, 64), TestCapture.descriptor_write_uniform_ranges[0]);

    renderer.deinit();

    try std.testing.expectEqual(@as(usize, 1), TestCapture.free_descriptor_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.destroy_pool_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.destroy_layout_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.destroy_pipeline_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.destroy_pipeline_layout_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.destroy_render_pass_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.destroy_sampler_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.destroy_image_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.destroy_image_view_calls);
    try std.testing.expectEqual(@as(usize, 4), TestCapture.destroy_buffer_calls);
}
