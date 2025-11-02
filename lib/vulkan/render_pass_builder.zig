//! Render pass builder with automatic subpass dependency inference

const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");

const log = std.log.scoped(.render_pass_builder);

/// Attachment description with usage tracking
pub const AttachmentBuilder = struct {
    format: types.VkFormat,
    samples: types.VkSampleCountFlagBits,
    load_op: types.VkAttachmentLoadOp,
    store_op: types.VkAttachmentStoreOp,
    stencil_load_op: types.VkAttachmentLoadOp,
    stencil_store_op: types.VkAttachmentStoreOp,
    initial_layout: types.VkImageLayout,
    final_layout: types.VkImageLayout,

    pub fn init(format: types.VkFormat) AttachmentBuilder {
        return .{
            .format = format,
            .samples = .@"1",
            .load_op = .DONT_CARE,
            .store_op = .DONT_CARE,
            .stencil_load_op = .DONT_CARE,
            .stencil_store_op = .DONT_CARE,
            .initial_layout = .UNDEFINED,
            .final_layout = .UNDEFINED,
        };
    }

    pub fn setSamples(self: *AttachmentBuilder, samples: types.VkSampleCountFlagBits) *AttachmentBuilder {
        self.samples = samples;
        return self;
    }

    pub fn setLoadOp(self: *AttachmentBuilder, load: types.VkAttachmentLoadOp, store: types.VkAttachmentStoreOp) *AttachmentBuilder {
        self.load_op = load;
        self.store_op = store;
        return self;
    }

    pub fn setStencilOp(self: *AttachmentBuilder, load: types.VkAttachmentLoadOp, store: types.VkAttachmentStoreOp) *AttachmentBuilder {
        self.stencil_load_op = load;
        self.stencil_store_op = store;
        return self;
    }

    pub fn setLayout(self: *AttachmentBuilder, initial: types.VkImageLayout, final: types.VkImageLayout) *AttachmentBuilder {
        self.initial_layout = initial;
        self.final_layout = final;
        return self;
    }

    pub fn toVulkan(self: AttachmentBuilder) types.VkAttachmentDescription {
        return .{
            .format = self.format,
            .samples = self.samples,
            .loadOp = self.load_op,
            .storeOp = self.store_op,
            .stencilLoadOp = self.stencil_load_op,
            .stencilStoreOp = self.stencil_store_op,
            .initialLayout = self.initial_layout,
            .finalLayout = self.final_layout,
            .flags = 0,
        };
    }
};

/// Subpass description with attachment references
pub const SubpassBuilder = struct {
    allocator: std.mem.Allocator,
    pipeline_bind_point: types.VkPipelineBindPoint,
    input_attachments: std.ArrayList(types.VkAttachmentReference),
    color_attachments: std.ArrayList(types.VkAttachmentReference),
    resolve_attachments: std.ArrayList(types.VkAttachmentReference),
    depth_stencil: ?types.VkAttachmentReference,
    preserve_attachments: std.ArrayList(u32),

    pub fn init(allocator: std.mem.Allocator, bind_point: types.VkPipelineBindPoint) SubpassBuilder {
        return .{
            .allocator = allocator,
            .pipeline_bind_point = bind_point,
            .input_attachments = std.ArrayList(types.VkAttachmentReference).init(allocator),
            .color_attachments = std.ArrayList(types.VkAttachmentReference).init(allocator),
            .resolve_attachments = std.ArrayList(types.VkAttachmentReference).init(allocator),
            .depth_stencil = null,
            .preserve_attachments = std.ArrayList(u32).init(allocator),
        };
    }

    pub fn deinit(self: *SubpassBuilder) void {
        self.input_attachments.deinit();
        self.color_attachments.deinit();
        self.resolve_attachments.deinit();
        self.preserve_attachments.deinit();
    }

    pub fn addInputAttachment(self: *SubpassBuilder, attachment: u32, layout: types.VkImageLayout) !*SubpassBuilder {
        try self.input_attachments.append(.{
            .attachment = attachment,
            .layout = layout,
        });
        return self;
    }

    pub fn addColorAttachment(self: *SubpassBuilder, attachment: u32, layout: types.VkImageLayout) !*SubpassBuilder {
        try self.color_attachments.append(.{
            .attachment = attachment,
            .layout = layout,
        });
        return self;
    }

    pub fn addResolveAttachment(self: *SubpassBuilder, attachment: u32, layout: types.VkImageLayout) !*SubpassBuilder {
        try self.resolve_attachments.append(.{
            .attachment = attachment,
            .layout = layout,
        });
        return self;
    }

    pub fn setDepthStencilAttachment(self: *SubpassBuilder, attachment: u32, layout: types.VkImageLayout) *SubpassBuilder {
        self.depth_stencil = .{
            .attachment = attachment,
            .layout = layout,
        };
        return self;
    }

    pub fn addPreserveAttachment(self: *SubpassBuilder, attachment: u32) !*SubpassBuilder {
        try self.preserve_attachments.append(attachment);
        return self;
    }
};

/// Render pass builder with automatic dependency inference
pub const RenderPassBuilder = struct {
    allocator: std.mem.Allocator,
    device: *device_mod.Device,
    attachments: std.ArrayList(AttachmentBuilder),
    subpasses: std.ArrayList(SubpassBuilder),
    explicit_dependencies: std.ArrayList(types.VkSubpassDependency),

    pub fn init(allocator: std.mem.Allocator, device: *device_mod.Device) RenderPassBuilder {
        return .{
            .allocator = allocator,
            .device = device,
            .attachments = std.ArrayList(AttachmentBuilder).init(allocator),
            .subpasses = std.ArrayList(SubpassBuilder).init(allocator),
            .explicit_dependencies = std.ArrayList(types.VkSubpassDependency).init(allocator),
        };
    }

    pub fn deinit(self: *RenderPassBuilder) void {
        for (self.subpasses.items) |*subpass| {
            subpass.deinit();
        }
        self.attachments.deinit();
        self.subpasses.deinit();
        self.explicit_dependencies.deinit();
    }

    /// Add attachment and return its index
    pub fn addAttachment(self: *RenderPassBuilder, attachment: AttachmentBuilder) !u32 {
        const index: u32 = @intCast(self.attachments.items.len);
        try self.attachments.append(attachment);
        return index;
    }

    /// Add subpass and return its index
    pub fn addSubpass(self: *RenderPassBuilder, subpass: SubpassBuilder) !u32 {
        const index: u32 = @intCast(self.subpasses.items.len);
        try self.subpasses.append(subpass);
        return index;
    }

    /// Add explicit subpass dependency
    pub fn addDependency(self: *RenderPassBuilder, dependency: types.VkSubpassDependency) !*RenderPassBuilder {
        try self.explicit_dependencies.append(dependency);
        return self;
    }

    /// Infer dependencies between subpasses based on attachment usage
    fn inferDependencies(self: *RenderPassBuilder) ![]types.VkSubpassDependency {
        var dependencies = std.ArrayList(types.VkSubpassDependency).init(self.allocator);

        // Add external -> first subpass dependency
        if (self.subpasses.items.len > 0) {
            const first_subpass = &self.subpasses.items[0];

            // Color attachments
            if (first_subpass.color_attachments.items.len > 0) {
                try dependencies.append(.{
                    .srcSubpass = types.VK_SUBPASS_EXTERNAL,
                    .dstSubpass = 0,
                    .srcStageMask = types.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                    .dstStageMask = types.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                    .srcAccessMask = 0,
                    .dstAccessMask = types.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
                    .dependencyFlags = 0,
                });
            }

            // Depth attachment
            if (first_subpass.depth_stencil != null) {
                try dependencies.append(.{
                    .srcSubpass = types.VK_SUBPASS_EXTERNAL,
                    .dstSubpass = 0,
                    .srcStageMask = types.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT | types.VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
                    .dstStageMask = types.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT | types.VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
                    .srcAccessMask = 0,
                    .dstAccessMask = types.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
                    .dependencyFlags = 0,
                });
            }
        }

        // Infer dependencies between consecutive subpasses
        var i: u32 = 0;
        while (i < self.subpasses.items.len - 1) : (i += 1) {
            const src_subpass = &self.subpasses.items[i];
            const dst_subpass = &self.subpasses.items[i + 1];

            // Check if any attachment written in src is read in dst
            var needs_dependency = false;

            // Check color attachments
            for (src_subpass.color_attachments.items) |src_color| {
                for (dst_subpass.input_attachments.items) |dst_input| {
                    if (src_color.attachment == dst_input.attachment) {
                        needs_dependency = true;
                        break;
                    }
                }
            }

            if (needs_dependency) {
                try dependencies.append(.{
                    .srcSubpass = i,
                    .dstSubpass = i + 1,
                    .srcStageMask = types.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                    .dstStageMask = types.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
                    .srcAccessMask = types.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
                    .dstAccessMask = types.VK_ACCESS_INPUT_ATTACHMENT_READ_BIT,
                    .dependencyFlags = types.VK_DEPENDENCY_BY_REGION_BIT,
                });
            }
        }

        // Add last subpass -> external dependency
        if (self.subpasses.items.len > 0) {
            const last_index: u32 = @intCast(self.subpasses.items.len - 1);
            const last_subpass = &self.subpasses.items[last_index];

            if (last_subpass.color_attachments.items.len > 0) {
                try dependencies.append(.{
                    .srcSubpass = last_index,
                    .dstSubpass = types.VK_SUBPASS_EXTERNAL,
                    .srcStageMask = types.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                    .dstStageMask = types.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
                    .srcAccessMask = types.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
                    .dstAccessMask = 0,
                    .dependencyFlags = 0,
                });
            }
        }

        // Add explicit dependencies
        for (self.explicit_dependencies.items) |dep| {
            try dependencies.append(dep);
        }

        return dependencies.toOwnedSlice();
    }

    /// Build the render pass
    pub fn build(self: *RenderPassBuilder) !types.VkRenderPass {
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;

        // Convert attachments
        var vk_attachments = try self.allocator.alloc(types.VkAttachmentDescription, self.attachments.items.len);
        defer self.allocator.free(vk_attachments);
        for (self.attachments.items, 0..) |attachment, i| {
            vk_attachments[i] = attachment.toVulkan();
        }

        // Convert subpasses
        var vk_subpasses = try self.allocator.alloc(types.VkSubpassDescription, self.subpasses.items.len);
        defer self.allocator.free(vk_subpasses);

        for (self.subpasses.items, 0..) |*subpass, i| {
            vk_subpasses[i] = .{
                .pipelineBindPoint = subpass.pipeline_bind_point,
                .inputAttachmentCount = @intCast(subpass.input_attachments.items.len),
                .pInputAttachments = if (subpass.input_attachments.items.len > 0) subpass.input_attachments.items.ptr else null,
                .colorAttachmentCount = @intCast(subpass.color_attachments.items.len),
                .pColorAttachments = if (subpass.color_attachments.items.len > 0) subpass.color_attachments.items.ptr else null,
                .pResolveAttachments = if (subpass.resolve_attachments.items.len > 0) subpass.resolve_attachments.items.ptr else null,
                .pDepthStencilAttachment = if (subpass.depth_stencil) |*ds| ds else null,
                .preserveAttachmentCount = @intCast(subpass.preserve_attachments.items.len),
                .pPreserveAttachments = if (subpass.preserve_attachments.items.len > 0) subpass.preserve_attachments.items.ptr else null,
                .flags = 0,
            };
        }

        // Infer dependencies
        const dependencies = try self.inferDependencies();
        defer self.allocator.free(dependencies);

        const create_info = types.VkRenderPassCreateInfo{
            .attachmentCount = @intCast(vk_attachments.len),
            .pAttachments = if (vk_attachments.len > 0) vk_attachments.ptr else null,
            .subpassCount = @intCast(vk_subpasses.len),
            .pSubpasses = if (vk_subpasses.len > 0) vk_subpasses.ptr else null,
            .dependencyCount = @intCast(dependencies.len),
            .pDependencies = if (dependencies.len > 0) dependencies.ptr else null,
            .flags = 0,
            .pNext = null,
        };

        var render_pass: types.VkRenderPass = undefined;
        try errors.ensureSuccess(self.device.dispatch.create_render_pass(
            device_handle,
            &create_info,
            self.device.allocation_callbacks,
            &render_pass,
        ));

        log.debug("Created render pass with {} attachments, {} subpasses, {} dependencies", .{
            vk_attachments.len,
            vk_subpasses.len,
            dependencies.len,
        });

        return render_pass;
    }
};

/// Common render pass configurations

/// Single-pass color + depth render pass
pub fn createSimpleRenderPass(
    allocator: std.mem.Allocator,
    device: *device_mod.Device,
    color_format: types.VkFormat,
    depth_format: types.VkFormat,
    clear: bool,
) !types.VkRenderPass {
    var builder = RenderPassBuilder.init(allocator, device);
    defer builder.deinit();

    // Color attachment
    var color = AttachmentBuilder.init(color_format);
    color.setLoadOp(
        if (clear) .CLEAR else .LOAD,
        .STORE,
    ).setLayout(.UNDEFINED, .PRESENT_SRC_KHR);
    const color_idx = try builder.addAttachment(color);

    // Depth attachment
    var depth = AttachmentBuilder.init(depth_format);
    depth.setLoadOp(
        if (clear) .CLEAR else .LOAD,
        .DONT_CARE,
    ).setLayout(.UNDEFINED, .DEPTH_STENCIL_ATTACHMENT_OPTIMAL);
    const depth_idx = try builder.addAttachment(depth);

    // Subpass
    var subpass = SubpassBuilder.init(allocator, .GRAPHICS);
    _ = try subpass.addColorAttachment(color_idx, .COLOR_ATTACHMENT_OPTIMAL);
    _ = subpass.setDepthStencilAttachment(depth_idx, .DEPTH_STENCIL_ATTACHMENT_OPTIMAL);
    _ = try builder.addSubpass(subpass);

    return builder.build();
}

/// Deferred rendering render pass (geometry + lighting passes)
pub fn createDeferredRenderPass(
    allocator: std.mem.Allocator,
    device: *device_mod.Device,
    gbuffer_formats: []const types.VkFormat,
    depth_format: types.VkFormat,
    final_format: types.VkFormat,
) !types.VkRenderPass {
    var builder = RenderPassBuilder.init(allocator, device);
    defer builder.deinit();

    // G-buffer attachments (position, normal, albedo, etc.)
    var gbuffer_indices = try allocator.alloc(u32, gbuffer_formats.len);
    defer allocator.free(gbuffer_indices);

    for (gbuffer_formats, 0..) |format, i| {
        var attachment = AttachmentBuilder.init(format);
        attachment.setLoadOp(.CLEAR, .STORE).setLayout(.UNDEFINED, .SHADER_READ_ONLY_OPTIMAL);
        gbuffer_indices[i] = try builder.addAttachment(attachment);
    }

    // Depth attachment
    var depth = AttachmentBuilder.init(depth_format);
    depth.setLoadOp(.CLEAR, .DONT_CARE).setLayout(.UNDEFINED, .DEPTH_STENCIL_ATTACHMENT_OPTIMAL);
    const depth_idx = try builder.addAttachment(depth);

    // Final color attachment
    var final = AttachmentBuilder.init(final_format);
    final.setLoadOp(.CLEAR, .STORE).setLayout(.UNDEFINED, .PRESENT_SRC_KHR);
    const final_idx = try builder.addAttachment(final);

    // Geometry subpass
    var geometry_subpass = SubpassBuilder.init(allocator, .GRAPHICS);
    for (gbuffer_indices) |idx| {
        _ = try geometry_subpass.addColorAttachment(idx, .COLOR_ATTACHMENT_OPTIMAL);
    }
    _ = geometry_subpass.setDepthStencilAttachment(depth_idx, .DEPTH_STENCIL_ATTACHMENT_OPTIMAL);
    _ = try builder.addSubpass(geometry_subpass);

    // Lighting subpass
    var lighting_subpass = SubpassBuilder.init(allocator, .GRAPHICS);
    for (gbuffer_indices) |idx| {
        _ = try lighting_subpass.addInputAttachment(idx, .SHADER_READ_ONLY_OPTIMAL);
    }
    _ = try lighting_subpass.addColorAttachment(final_idx, .COLOR_ATTACHMENT_OPTIMAL);
    _ = try builder.addSubpass(lighting_subpass);

    return builder.build();
}
