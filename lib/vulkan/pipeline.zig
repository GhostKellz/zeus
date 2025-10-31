const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const loader = @import("loader.zig");

pub const PipelineLayoutOptions = struct {
    set_layouts: []const types.VkDescriptorSetLayout = &.{},
    push_constants: []const types.VkPushConstantRange = &.{},
    flags: types.VkPipelineLayoutCreateFlags = 0,
};

pub fn createPipelineLayout(device: *device_mod.Device, options: PipelineLayoutOptions) errors.Error!types.VkPipelineLayout {
    const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;

    const layouts_ptr = if (options.set_layouts.len == 0) null else @as([*]const types.VkDescriptorSetLayout, @ptrCast(options.set_layouts.ptr));
    const push_constants_ptr = if (options.push_constants.len == 0) null else @as([*]const types.VkPushConstantRange, @ptrCast(options.push_constants.ptr));

    var create_info = types.VkPipelineLayoutCreateInfo{
        .flags = options.flags,
        .setLayoutCount = @intCast(options.set_layouts.len),
        .pSetLayouts = layouts_ptr,
        .pushConstantRangeCount = @intCast(options.push_constants.len),
        .pPushConstantRanges = push_constants_ptr,
    };

    var layout: types.VkPipelineLayout = undefined;
    try errors.ensureSuccess(device.dispatch.create_pipeline_layout(device_handle, &create_info, device.allocation_callbacks, &layout));
    return layout;
}

pub fn destroyPipelineLayout(device: *device_mod.Device, layout: types.VkPipelineLayout) void {
    const device_handle = device.handle orelse return;
    device.dispatch.destroy_pipeline_layout(device_handle, layout, device.allocation_callbacks);
}

pub const PipelineLayout = struct {
    device: *device_mod.Device,
    handle: ?types.VkPipelineLayout,
    options: PipelineLayoutOptions,

    pub fn init(device: *device_mod.Device, options: PipelineLayoutOptions) errors.Error!PipelineLayout {
        const layout = try createPipelineLayout(device, options);
        return PipelineLayout{
            .device = device,
            .handle = layout,
            .options = options,
        };
    }

    pub fn deinit(self: *PipelineLayout) void {
        if (self.handle) |layout| {
            destroyPipelineLayout(self.device, layout);
            self.handle = null;
        }
    }
};

// Graphics pipeline --------------------------------------------------------

pub const TextVertexLayout = struct {
    pub const vertex_bindings = [_]types.VkVertexInputBindingDescription{
        .{
            .binding = 0,
            .stride = 2 * @sizeOf(f32),
            .inputRate = types.VkVertexInputRate.VERTEX,
        },
        .{
            .binding = 1,
            .stride = (2 + 2 + 4 + 4) * @sizeOf(f32),
            .inputRate = types.VkVertexInputRate.INSTANCE,
        },
    };

    pub const vertex_attributes = [_]types.VkVertexInputAttributeDescription{
        .{ .location = 0, .binding = 0, .format = types.VK_FORMAT_R32G32_SFLOAT, .offset = 0 },
        .{ .location = 1, .binding = 1, .format = types.VK_FORMAT_R32G32_SFLOAT, .offset = 0 },
        .{ .location = 2, .binding = 1, .format = types.VK_FORMAT_R32G32_SFLOAT, .offset = 2 * @sizeOf(f32) },
        .{ .location = 3, .binding = 1, .format = types.VK_FORMAT_R32G32B32A32_SFLOAT, .offset = 4 * @sizeOf(f32) },
        .{ .location = 4, .binding = 1, .format = types.VK_FORMAT_R32G32B32A32_SFLOAT, .offset = 8 * @sizeOf(f32) },
    };
};

const default_dynamic_states = [_]types.VkDynamicState{
    types.VK_DYNAMIC_STATE_VIEWPORT,
    types.VK_DYNAMIC_STATE_SCISSOR,
};

const default_color_blend_attachment = types.VkPipelineColorBlendAttachmentState{
    .blendEnable = 1,
    .srcColorBlendFactor = types.VK_BLEND_FACTOR_SRC_ALPHA,
    .dstColorBlendFactor = types.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
    .colorBlendOp = types.VK_BLEND_OP_ADD,
    .srcAlphaBlendFactor = types.VK_BLEND_FACTOR_ONE,
    .dstAlphaBlendFactor = types.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
    .alphaBlendOp = types.VK_BLEND_OP_ADD,
    .colorWriteMask = types.VK_COLOR_COMPONENT_R_BIT |
        types.VK_COLOR_COMPONENT_G_BIT |
        types.VK_COLOR_COMPONENT_B_BIT |
        types.VK_COLOR_COMPONENT_A_BIT,
};

pub const GraphicsPipelineOptions = struct {
    layout: types.VkPipelineLayout,
    render_pass: types.VkRenderPass,
    shader_stages: []const types.VkPipelineShaderStageCreateInfo,
    subpass: u32 = 0,
    vertex_bindings: []const types.VkVertexInputBindingDescription = TextVertexLayout.vertex_bindings[0..],
    vertex_attributes: []const types.VkVertexInputAttributeDescription = TextVertexLayout.vertex_attributes[0..],
    dynamic_states: []const types.VkDynamicState = default_dynamic_states[0..],
    color_blend_attachment: types.VkPipelineColorBlendAttachmentState = default_color_blend_attachment,
    cache: ?types.VkPipelineCache = null,
};

pub fn createGraphicsPipeline(device: *device_mod.Device, options: GraphicsPipelineOptions) errors.Error!types.VkPipeline {
    const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;
    std.debug.assert(options.shader_stages.len > 0);

    const bindings_ptr = if (options.vertex_bindings.len == 0) null else @as([*]const types.VkVertexInputBindingDescription, @ptrCast(options.vertex_bindings.ptr));
    const attributes_ptr = if (options.vertex_attributes.len == 0) null else @as([*]const types.VkVertexInputAttributeDescription, @ptrCast(options.vertex_attributes.ptr));
    const stages_ptr = @as([*]const types.VkPipelineShaderStageCreateInfo, @ptrCast(options.shader_stages.ptr));
    const dynamic_ptr = if (options.dynamic_states.len == 0) null else @as([*]const types.VkDynamicState, @ptrCast(options.dynamic_states.ptr));

    var vertex_input = types.VkPipelineVertexInputStateCreateInfo{
        .vertexBindingDescriptionCount = @intCast(options.vertex_bindings.len),
        .pVertexBindingDescriptions = bindings_ptr,
        .vertexAttributeDescriptionCount = @intCast(options.vertex_attributes.len),
        .pVertexAttributeDescriptions = attributes_ptr,
    };

    var input_assembly = types.VkPipelineInputAssemblyStateCreateInfo{
        .topology = types.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = 0,
    };

    var viewport_state = types.VkPipelineViewportStateCreateInfo{
        .viewportCount = 1,
        .pViewports = null,
        .scissorCount = 1,
        .pScissors = null,
    };

    var rasterization_state = types.VkPipelineRasterizationStateCreateInfo{
        .depthClampEnable = 0,
        .rasterizerDiscardEnable = 0,
        .polygonMode = types.VK_POLYGON_MODE_FILL,
        .cullMode = types.VK_CULL_MODE_NONE,
        .frontFace = types.VK_FRONT_FACE_COUNTER_CLOCKWISE,
        .depthBiasEnable = 0,
        .lineWidth = 1.0,
    };

    var multisample_state = types.VkPipelineMultisampleStateCreateInfo{
        .rasterizationSamples = types.VK_SAMPLE_COUNT_1_BIT,
        .sampleShadingEnable = 0,
    };

    var color_attachment = options.color_blend_attachment;
    var color_blend_state = types.VkPipelineColorBlendStateCreateInfo{
        .logicOpEnable = 0,
        .attachmentCount = 1,
        .pAttachments = &color_attachment,
    };

    var dynamic_state_info = types.VkPipelineDynamicStateCreateInfo{
        .dynamicStateCount = @intCast(options.dynamic_states.len),
        .pDynamicStates = dynamic_ptr,
    };

    const dynamic_state_ptr = if (options.dynamic_states.len == 0) null else &dynamic_state_info;

    var create_info = types.VkGraphicsPipelineCreateInfo{
        .stageCount = @intCast(options.shader_stages.len),
        .pStages = stages_ptr,
        .pVertexInputState = &vertex_input,
        .pInputAssemblyState = &input_assembly,
        .pViewportState = &viewport_state,
        .pRasterizationState = &rasterization_state,
        .pMultisampleState = &multisample_state,
        .pDepthStencilState = null,
        .pColorBlendState = &color_blend_state,
        .pDynamicState = dynamic_state_ptr,
        .layout = options.layout,
        .renderPass = options.render_pass,
        .subpass = options.subpass,
        .basePipelineHandle = null,
        .basePipelineIndex = -1,
    };

    var pipeline: types.VkPipeline = undefined;
    try errors.ensureSuccess(device.dispatch.create_graphics_pipelines(device_handle, options.cache, 1, &create_info, device.allocation_callbacks, &pipeline));
    return pipeline;
}

pub fn destroyPipeline(device: *device_mod.Device, pipeline: types.VkPipeline) void {
    const device_handle = device.handle orelse return;
    device.dispatch.destroy_pipeline(device_handle, pipeline, device.allocation_callbacks);
}

pub const GraphicsPipeline = struct {
    device: *device_mod.Device,
    handle: ?types.VkPipeline,

    pub fn init(device: *device_mod.Device, options: GraphicsPipelineOptions) errors.Error!GraphicsPipeline {
        const pipeline = try createGraphicsPipeline(device, options);
        return GraphicsPipeline{ .device = device, .handle = pipeline };
    }

    pub fn deinit(self: *GraphicsPipeline) void {
        if (self.handle) |pipeline| {
            destroyPipeline(self.device, pipeline);
            self.handle = null;
        }
    }
};

// Pipeline layout tests -----------------------------------------------------

const fake_layout = @as(types.VkPipelineLayout, @ptrFromInt(@as(usize, 0xFEEDFACE)));

const LayoutCapture = struct {
    pub var layout_info: ?types.VkPipelineLayoutCreateInfo = null;
    pub var destroy_calls: usize = 0;

    pub fn reset() void {
        layout_info = null;
        destroy_calls = 0;
    }

    pub fn stubCreate(_: types.VkDevice, info: *const types.VkPipelineLayoutCreateInfo, _: ?*const types.VkAllocationCallbacks, layout: *types.VkPipelineLayout) callconv(.C) types.VkResult {
        layout_info = info.*;
        layout.* = fake_layout;
        return .SUCCESS;
    }

    pub fn stubDestroy(_: types.VkDevice, _: types.VkPipelineLayout, _: ?*const types.VkAllocationCallbacks) callconv(.C) void {
        destroy_calls += 1;
    }
};

fn makeLayoutDevice() device_mod.Device {
    var device = device_mod.Device{
        .allocator = std.testing.allocator,
        .loader = undefined,
        .dispatch = std.mem.zeroes(loader.DeviceDispatch),
        .handle = @as(types.VkDevice, @ptrFromInt(@as(usize, 0xCAFEBABE))),
        .allocation_callbacks = null,
    };
    device.dispatch.create_pipeline_layout = LayoutCapture.stubCreate;
    device.dispatch.destroy_pipeline_layout = LayoutCapture.stubDestroy;
    return device;
}

test "createPipelineLayout forwards layouts and push constants" {
    LayoutCapture.reset();
    var device = makeLayoutDevice();

    const set_layouts = [_]types.VkDescriptorSetLayout{
        @as(types.VkDescriptorSetLayout, @ptrFromInt(@as(usize, 0x1000))),
    };

    const push_ranges = [_]types.VkPushConstantRange{
        .{ .stageFlags = types.VK_SHADER_STAGE_VERTEX_BIT, .offset = 0, .size = 64 },
    };

    const layout = try createPipelineLayout(&device, .{
        .set_layouts = set_layouts[0..],
        .push_constants = push_ranges[0..],
        .flags = 0,
    });
    try std.testing.expectEqual(fake_layout, layout);

    const info = LayoutCapture.layout_info orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(u32, 1), info.setLayoutCount);
    try std.testing.expectEqual(@as(u32, 1), info.pushConstantRangeCount);
    try std.testing.expect(info.pSetLayouts != null);
    try std.testing.expect(info.pPushConstantRanges != null);
}

test "PipelineLayout.deinit destroys handle once" {
    LayoutCapture.reset();
    var device = makeLayoutDevice();
    var layout = try PipelineLayout.init(&device, .{});
    try std.testing.expectEqual(fake_layout, layout.handle.?);
    layout.deinit();
    try std.testing.expectEqual(@as(usize, 1), LayoutCapture.destroy_calls);
    layout.deinit();
    try std.testing.expectEqual(@as(usize, 1), LayoutCapture.destroy_calls);
}

// Graphics pipeline tests --------------------------------------------------

const fake_pipeline = @as(types.VkPipeline, @ptrFromInt(@as(usize, 0xACEDBEEF)));
const fake_render_pass = @as(types.VkRenderPass, @ptrFromInt(@as(usize, 0x11112222)));

const PipelineCapture = struct {
    pub var create_info: ?types.VkGraphicsPipelineCreateInfo = null;
    pub var vertex_bindings: [4]types.VkVertexInputBindingDescription = undefined;
    pub var vertex_binding_count: usize = 0;
    pub var vertex_attributes: [6]types.VkVertexInputAttributeDescription = undefined;
    pub var vertex_attribute_count: usize = 0;
    pub var dynamic_states: [4]types.VkDynamicState = undefined;
    pub var dynamic_state_count: usize = 0;
    pub var color_attachment: ?types.VkPipelineColorBlendAttachmentState = null;
    pub var destroy_calls: usize = 0;

    pub fn reset() void {
        create_info = null;
        vertex_binding_count = 0;
        vertex_attribute_count = 0;
        dynamic_state_count = 0;
        color_attachment = null;
        destroy_calls = 0;
    }

    pub fn stubCreate(_: types.VkDevice, _: types.VkPipelineCache, count: u32, infos: [*]const types.VkGraphicsPipelineCreateInfo, _: ?*const types.VkAllocationCallbacks, pipelines: [*]types.VkPipeline) callconv(.C) types.VkResult {
        std.debug.assert(count == 1);
        const info = infos[0];
        create_info = info;

        const vertex_input = info.pVertexInputState.*;
        vertex_binding_count = vertex_input.vertexBindingDescriptionCount;
        if (vertex_input.pVertexBindingDescriptions) |ptr| {
            for (0..vertex_binding_count) |idx| {
                PipelineCapture.vertex_bindings[idx] = ptr[idx];
            }
        }

        vertex_attribute_count = vertex_input.vertexAttributeDescriptionCount;
        if (vertex_input.pVertexAttributeDescriptions) |ptr| {
            for (0..vertex_attribute_count) |idx| {
                PipelineCapture.vertex_attributes[idx] = ptr[idx];
            }
        }

        if (info.pDynamicState) |dynamic_state| {
            dynamic_state_count = dynamic_state.dynamicStateCount;
            if (dynamic_state.pDynamicStates) |ptr| {
                for (0..dynamic_state_count) |idx| {
                    PipelineCapture.dynamic_states[idx] = ptr[idx];
                }
            }
        }

        if (info.pColorBlendState) |blend_state| {
            std.debug.assert(blend_state.attachmentCount == 1);
            if (blend_state.pAttachments) |ptr| {
                color_attachment = ptr[0];
            }
        }

        pipelines[0] = fake_pipeline;
        return .SUCCESS;
    }

    pub fn stubDestroy(_: types.VkDevice, _: types.VkPipeline, _: ?*const types.VkAllocationCallbacks) callconv(.C) void {
        destroy_calls += 1;
    }
};

fn makePipelineDevice() device_mod.Device {
    var device = device_mod.Device{
        .allocator = std.testing.allocator,
        .loader = undefined,
        .dispatch = std.mem.zeroes(loader.DeviceDispatch),
        .handle = @as(types.VkDevice, @ptrFromInt(@as(usize, 0x43214321))),
        .allocation_callbacks = null,
    };
    device.dispatch.create_graphics_pipelines = PipelineCapture.stubCreate;
    device.dispatch.destroy_pipeline = PipelineCapture.stubDestroy;
    return device;
}

fn makeStage(stage: types.VkShaderStageFlagBits, module_value: usize) types.VkPipelineShaderStageCreateInfo {
    const entry: [:0]const u8 = "main";
    return types.VkPipelineShaderStageCreateInfo{
        .stage = stage,
        .module = @as(types.VkShaderModule, @ptrFromInt(module_value)),
        .pName = entry.ptr,
    };
}

test "createGraphicsPipeline configures text pipeline state" {
    PipelineCapture.reset();
    var device = makePipelineDevice();

    const stages = [_]types.VkPipelineShaderStageCreateInfo{
        makeStage(.VERTEX_BIT, 0xAAAA5555),
        makeStage(.FRAGMENT_BIT, 0xBBBB6666),
    };

    const pipeline = try createGraphicsPipeline(&device, .{
        .layout = fake_layout,
        .render_pass = fake_render_pass,
        .shader_stages = stages[0..],
    });
    try std.testing.expectEqual(fake_pipeline, pipeline);

    const info = PipelineCapture.create_info orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(fake_layout, info.layout);
    try std.testing.expectEqual(fake_render_pass, info.renderPass);
    try std.testing.expectEqual(@as(u32, 2), info.stageCount);
    try std.testing.expect(info.pDynamicState != null);

    try std.testing.expectEqual(@as(usize, 2), PipelineCapture.vertex_binding_count);
    try std.testing.expectEqual(@as(usize, 5), PipelineCapture.vertex_attribute_count);
    try std.testing.expectEqual(types.VK_FORMAT_R32G32_SFLOAT, PipelineCapture.vertex_attributes[0].format);
    try std.testing.expectEqual(types.VkVertexInputRate.VERTEX, PipelineCapture.vertex_bindings[0].inputRate);
    try std.testing.expectEqual(types.VkVertexInputRate.INSTANCE, PipelineCapture.vertex_bindings[1].inputRate);

    try std.testing.expectEqual(@as(usize, 2), PipelineCapture.dynamic_state_count);
    try std.testing.expectEqual(types.VK_DYNAMIC_STATE_VIEWPORT, PipelineCapture.dynamic_states[0]);
    try std.testing.expectEqual(types.VK_DYNAMIC_STATE_SCISSOR, PipelineCapture.dynamic_states[1]);

    const attachment = PipelineCapture.color_attachment orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(types.VkBool32, 1), attachment.blendEnable);
    try std.testing.expectEqual(types.VK_BLEND_FACTOR_SRC_ALPHA, attachment.srcColorBlendFactor);
}

test "GraphicsPipeline.deinit destroys handle once" {
    PipelineCapture.reset();
    var device = makePipelineDevice();

    const stages = [_]types.VkPipelineShaderStageCreateInfo{
        makeStage(.VERTEX_BIT, 0x11112222),
    };

    var pipeline = try GraphicsPipeline.init(&device, .{
        .layout = fake_layout,
        .render_pass = fake_render_pass,
        .shader_stages = stages[0..],
    });
    try std.testing.expectEqual(fake_pipeline, pipeline.handle.?);
    pipeline.deinit();
    try std.testing.expectEqual(@as(usize, 1), PipelineCapture.destroy_calls);
    pipeline.deinit();
    try std.testing.expectEqual(@as(usize, 1), PipelineCapture.destroy_calls);
}
