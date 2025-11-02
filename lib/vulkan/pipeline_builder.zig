//! Advanced pipeline builder with caching and fluent API

const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const shader_mod = @import("shader.zig");
const pipeline_mod = @import("pipeline.zig");

const log = std.log.scoped(.pipeline_builder);

/// Graphics pipeline builder with fluent API
pub const GraphicsPipelineBuilder = struct {
    allocator: std.mem.Allocator,
    device: *device_mod.Device,

    // Shader stages
    stages: std.ArrayList(types.VkPipelineShaderStageCreateInfo),

    // Vertex input
    vertex_bindings: std.ArrayList(types.VkVertexInputBindingDescription),
    vertex_attributes: std.ArrayList(types.VkVertexInputAttributeDescription),

    // Input assembly
    topology: types.VkPrimitiveTopology,
    primitive_restart: bool,

    // Viewport/scissor
    viewports: std.ArrayList(types.VkViewport),
    scissors: std.ArrayList(types.VkRect2D),

    // Rasterization
    depth_clamp: bool,
    rasterizer_discard: bool,
    polygon_mode: types.VkPolygonMode,
    cull_mode: types.VkCullModeFlags,
    front_face: types.VkFrontFace,
    depth_bias_enable: bool,
    line_width: f32,

    // Multisample
    sample_count: types.VkSampleCountFlagBits,
    sample_shading: bool,
    min_sample_shading: f32,

    // Depth/stencil
    depth_test: bool,
    depth_write: bool,
    depth_compare: types.VkCompareOp,
    stencil_test: bool,

    // Color blend
    blend_attachments: std.ArrayList(types.VkPipelineColorBlendAttachmentState),
    blend_logic_op: bool,
    logic_op: types.VkLogicOp,
    blend_constants: [4]f32,

    // Dynamic state
    dynamic_states: std.ArrayList(types.VkDynamicState),

    // Layout
    layout: ?types.VkPipelineLayout,

    // Render pass
    render_pass: ?types.VkRenderPass,
    subpass: u32,

    pub fn init(allocator: std.mem.Allocator, device: *device_mod.Device) GraphicsPipelineBuilder {
        return .{
            .allocator = allocator,
            .device = device,
            .stages = std.ArrayList(types.VkPipelineShaderStageCreateInfo).init(allocator),
            .vertex_bindings = std.ArrayList(types.VkVertexInputBindingDescription).init(allocator),
            .vertex_attributes = std.ArrayList(types.VkVertexInputAttributeDescription).init(allocator),
            .topology = .TRIANGLE_LIST,
            .primitive_restart = false,
            .viewports = std.ArrayList(types.VkViewport).init(allocator),
            .scissors = std.ArrayList(types.VkRect2D).init(allocator),
            .depth_clamp = false,
            .rasterizer_discard = false,
            .polygon_mode = .FILL,
            .cull_mode = types.VK_CULL_MODE_BACK_BIT,
            .front_face = .COUNTER_CLOCKWISE,
            .depth_bias_enable = false,
            .line_width = 1.0,
            .sample_count = .@"1",
            .sample_shading = false,
            .min_sample_shading = 1.0,
            .depth_test = true,
            .depth_write = true,
            .depth_compare = .LESS,
            .stencil_test = false,
            .blend_attachments = std.ArrayList(types.VkPipelineColorBlendAttachmentState).init(allocator),
            .blend_logic_op = false,
            .logic_op = .COPY,
            .blend_constants = [_]f32{ 0.0, 0.0, 0.0, 0.0 },
            .dynamic_states = std.ArrayList(types.VkDynamicState).init(allocator),
            .layout = null,
            .render_pass = null,
            .subpass = 0,
        };
    }

    pub fn deinit(self: *GraphicsPipelineBuilder) void {
        self.stages.deinit();
        self.vertex_bindings.deinit();
        self.vertex_attributes.deinit();
        self.viewports.deinit();
        self.scissors.deinit();
        self.blend_attachments.deinit();
        self.dynamic_states.deinit();
    }

    /// Add shader stage
    pub fn addShader(
        self: *GraphicsPipelineBuilder,
        stage: types.VkShaderStageFlagBits,
        module: types.VkShaderModule,
        entry_point: [:0]const u8,
    ) !*GraphicsPipelineBuilder {
        try self.stages.append(.{
            .stage = stage,
            .module = module,
            .pName = entry_point.ptr,
            .pSpecializationInfo = null,
            .flags = 0,
            .pNext = null,
        });
        return self;
    }

    /// Set vertex binding
    pub fn addVertexBinding(
        self: *GraphicsPipelineBuilder,
        binding: u32,
        stride: u32,
        input_rate: types.VkVertexInputRate,
    ) !*GraphicsPipelineBuilder {
        try self.vertex_bindings.append(.{
            .binding = binding,
            .stride = stride,
            .inputRate = input_rate,
        });
        return self;
    }

    /// Add vertex attribute
    pub fn addVertexAttribute(
        self: *GraphicsPipelineBuilder,
        location: u32,
        binding: u32,
        format: types.VkFormat,
        offset: u32,
    ) !*GraphicsPipelineBuilder {
        try self.vertex_attributes.append(.{
            .location = location,
            .binding = binding,
            .format = format,
            .offset = offset,
        });
        return self;
    }

    /// Set topology
    pub fn setTopology(self: *GraphicsPipelineBuilder, topology: types.VkPrimitiveTopology) *GraphicsPipelineBuilder {
        self.topology = topology;
        return self;
    }

    /// Set polygon mode
    pub fn setPolygonMode(self: *GraphicsPipelineBuilder, mode: types.VkPolygonMode) *GraphicsPipelineBuilder {
        self.polygon_mode = mode;
        return self;
    }

    /// Set cull mode
    pub fn setCullMode(self: *GraphicsPipelineBuilder, mode: types.VkCullModeFlags) *GraphicsPipelineBuilder {
        self.cull_mode = mode;
        return self;
    }

    /// Set front face
    pub fn setFrontFace(self: *GraphicsPipelineBuilder, face: types.VkFrontFace) *GraphicsPipelineBuilder {
        self.front_face = face;
        return self;
    }

    /// Enable depth test
    pub fn enableDepthTest(self: *GraphicsPipelineBuilder, write: bool, compare: types.VkCompareOp) *GraphicsPipelineBuilder {
        self.depth_test = true;
        self.depth_write = write;
        self.depth_compare = compare;
        return self;
    }

    /// Disable depth test
    pub fn disableDepthTest(self: *GraphicsPipelineBuilder) *GraphicsPipelineBuilder {
        self.depth_test = false;
        return self;
    }

    /// Add color blend attachment
    pub fn addColorBlendAttachment(
        self: *GraphicsPipelineBuilder,
        attachment: types.VkPipelineColorBlendAttachmentState,
    ) !*GraphicsPipelineBuilder {
        try self.blend_attachments.append(attachment);
        return self;
    }

    /// Add default alpha blend attachment
    pub fn addDefaultBlendAttachment(self: *GraphicsPipelineBuilder) !*GraphicsPipelineBuilder {
        try self.blend_attachments.append(.{
            .blendEnable = 1,
            .srcColorBlendFactor = .SRC_ALPHA,
            .dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
            .colorBlendOp = .ADD,
            .srcAlphaBlendFactor = .ONE,
            .dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
            .alphaBlendOp = .ADD,
            .colorWriteMask = types.VK_COLOR_COMPONENT_R_BIT |
                types.VK_COLOR_COMPONENT_G_BIT |
                types.VK_COLOR_COMPONENT_B_BIT |
                types.VK_COLOR_COMPONENT_A_BIT,
        });
        return self;
    }

    /// Add dynamic state
    pub fn addDynamicState(self: *GraphicsPipelineBuilder, state: types.VkDynamicState) !*GraphicsPipelineBuilder {
        try self.dynamic_states.append(state);
        return self;
    }

    /// Set pipeline layout
    pub fn setPipelineLayout(self: *GraphicsPipelineBuilder, layout: types.VkPipelineLayout) *GraphicsPipelineBuilder {
        self.layout = layout;
        return self;
    }

    /// Set render pass
    pub fn setRenderPass(self: *GraphicsPipelineBuilder, render_pass: types.VkRenderPass, subpass: u32) *GraphicsPipelineBuilder {
        self.render_pass = render_pass;
        self.subpass = subpass;
        return self;
    }

    /// Build the pipeline
    pub fn build(self: *GraphicsPipelineBuilder) !types.VkPipeline {
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;

        const vertex_input_state = types.VkPipelineVertexInputStateCreateInfo{
            .vertexBindingDescriptionCount = @intCast(self.vertex_bindings.items.len),
            .pVertexBindingDescriptions = if (self.vertex_bindings.items.len > 0) self.vertex_bindings.items.ptr else null,
            .vertexAttributeDescriptionCount = @intCast(self.vertex_attributes.items.len),
            .pVertexAttributeDescriptions = if (self.vertex_attributes.items.len > 0) self.vertex_attributes.items.ptr else null,
            .flags = 0,
            .pNext = null,
        };

        const input_assembly_state = types.VkPipelineInputAssemblyStateCreateInfo{
            .topology = self.topology,
            .primitiveRestartEnable = if (self.primitive_restart) 1 else 0,
            .flags = 0,
            .pNext = null,
        };

        const viewport_state = types.VkPipelineViewportStateCreateInfo{
            .viewportCount = if (self.viewports.items.len > 0) @intCast(self.viewports.items.len) else 1,
            .pViewports = if (self.viewports.items.len > 0) self.viewports.items.ptr else null,
            .scissorCount = if (self.scissors.items.len > 0) @intCast(self.scissors.items.len) else 1,
            .pScissors = if (self.scissors.items.len > 0) self.scissors.items.ptr else null,
            .flags = 0,
            .pNext = null,
        };

        const rasterization_state = types.VkPipelineRasterizationStateCreateInfo{
            .depthClampEnable = if (self.depth_clamp) 1 else 0,
            .rasterizerDiscardEnable = if (self.rasterizer_discard) 1 else 0,
            .polygonMode = self.polygon_mode,
            .cullMode = self.cull_mode,
            .frontFace = self.front_face,
            .depthBiasEnable = if (self.depth_bias_enable) 1 else 0,
            .depthBiasConstantFactor = 0.0,
            .depthBiasClamp = 0.0,
            .depthBiasSlopeFactor = 0.0,
            .lineWidth = self.line_width,
            .flags = 0,
            .pNext = null,
        };

        const multisample_state = types.VkPipelineMultisampleStateCreateInfo{
            .rasterizationSamples = self.sample_count,
            .sampleShadingEnable = if (self.sample_shading) 1 else 0,
            .minSampleShading = self.min_sample_shading,
            .pSampleMask = null,
            .alphaToCoverageEnable = 0,
            .alphaToOneEnable = 0,
            .flags = 0,
            .pNext = null,
        };

        const depth_stencil_state = types.VkPipelineDepthStencilStateCreateInfo{
            .depthTestEnable = if (self.depth_test) 1 else 0,
            .depthWriteEnable = if (self.depth_write) 1 else 0,
            .depthCompareOp = self.depth_compare,
            .depthBoundsTestEnable = 0,
            .stencilTestEnable = if (self.stencil_test) 1 else 0,
            .front = std.mem.zeroes(types.VkStencilOpState),
            .back = std.mem.zeroes(types.VkStencilOpState),
            .minDepthBounds = 0.0,
            .maxDepthBounds = 1.0,
            .flags = 0,
            .pNext = null,
        };

        const color_blend_state = types.VkPipelineColorBlendStateCreateInfo{
            .logicOpEnable = if (self.blend_logic_op) 1 else 0,
            .logicOp = self.logic_op,
            .attachmentCount = @intCast(self.blend_attachments.items.len),
            .pAttachments = if (self.blend_attachments.items.len > 0) self.blend_attachments.items.ptr else null,
            .blendConstants = self.blend_constants,
            .flags = 0,
            .pNext = null,
        };

        const dynamic_state = types.VkPipelineDynamicStateCreateInfo{
            .dynamicStateCount = @intCast(self.dynamic_states.items.len),
            .pDynamicStates = if (self.dynamic_states.items.len > 0) self.dynamic_states.items.ptr else null,
            .flags = 0,
            .pNext = null,
        };

        const create_info = types.VkGraphicsPipelineCreateInfo{
            .stageCount = @intCast(self.stages.items.len),
            .pStages = self.stages.items.ptr,
            .pVertexInputState = &vertex_input_state,
            .pInputAssemblyState = &input_assembly_state,
            .pViewportState = &viewport_state,
            .pRasterizationState = &rasterization_state,
            .pMultisampleState = &multisample_state,
            .pDepthStencilState = &depth_stencil_state,
            .pColorBlendState = &color_blend_state,
            .pDynamicState = if (self.dynamic_states.items.len > 0) &dynamic_state else null,
            .layout = self.layout.?,
            .renderPass = self.render_pass.?,
            .subpass = self.subpass,
            .basePipelineHandle = null,
            .basePipelineIndex = -1,
            .flags = 0,
            .pNext = null,
            .pTessellationState = null,
        };

        var pipeline: types.VkPipeline = undefined;
        try errors.ensureSuccess(self.device.dispatch.create_graphics_pipelines(
            device_handle,
            null,
            1,
            @ptrCast(&create_info),
            self.device.allocation_callbacks,
            @ptrCast(&pipeline),
        ));

        log.debug("Created graphics pipeline", .{});
        return pipeline;
    }
};

/// Compute pipeline builder
pub const ComputePipelineBuilder = struct {
    allocator: std.mem.Allocator,
    device: *device_mod.Device,
    shader_module: ?types.VkShaderModule,
    entry_point: [:0]const u8,
    layout: ?types.VkPipelineLayout,

    pub fn init(allocator: std.mem.Allocator, device: *device_mod.Device) ComputePipelineBuilder {
        return .{
            .allocator = allocator,
            .device = device,
            .shader_module = null,
            .entry_point = "main",
            .layout = null,
        };
    }

    pub fn setShader(self: *ComputePipelineBuilder, module: types.VkShaderModule, entry_point: [:0]const u8) *ComputePipelineBuilder {
        self.shader_module = module;
        self.entry_point = entry_point;
        return self;
    }

    pub fn setPipelineLayout(self: *ComputePipelineBuilder, layout: types.VkPipelineLayout) *ComputePipelineBuilder {
        self.layout = layout;
        return self;
    }

    pub fn build(self: *ComputePipelineBuilder) !types.VkPipeline {
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;

        const stage = types.VkPipelineShaderStageCreateInfo{
            .stage = .COMPUTE,
            .module = self.shader_module.?,
            .pName = self.entry_point.ptr,
            .pSpecializationInfo = null,
            .flags = 0,
            .pNext = null,
        };

        const create_info = types.VkComputePipelineCreateInfo{
            .stage = stage,
            .layout = self.layout.?,
            .basePipelineHandle = null,
            .basePipelineIndex = -1,
            .flags = 0,
            .pNext = null,
        };

        var pipeline: types.VkPipeline = undefined;
        try errors.ensureSuccess(self.device.dispatch.create_compute_pipelines(
            device_handle,
            null,
            1,
            @ptrCast(&create_info),
            self.device.allocation_callbacks,
            @ptrCast(&pipeline),
        ));

        log.debug("Created compute pipeline", .{});
        return pipeline;
    }
};
