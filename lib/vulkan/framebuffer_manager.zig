//! Framebuffer manager with automatic swapchain integration

const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const swapchain_mod = @import("swapchain.zig");
const image_allocator = @import("image_allocator.zig");

const log = std.log.scoped(.framebuffer_manager);

/// Framebuffer attachment configuration
pub const FramebufferAttachment = struct {
    image: types.VkImage,
    view: types.VkImageView,
    format: types.VkFormat,
    owned: bool, // Whether this manager owns the attachment
};

/// Managed framebuffer with metadata
pub const ManagedFramebuffer = struct {
    framebuffer: types.VkFramebuffer,
    attachments: []FramebufferAttachment,
    width: u32,
    height: u32,
    layers: u32,

    pub fn destroy(self: *ManagedFramebuffer, device: *device_mod.Device, allocator: std.mem.Allocator) void {
        const device_handle = device.handle orelse return;
        device.dispatch.destroy_framebuffer(device_handle, self.framebuffer, device.allocation_callbacks);

        // Destroy owned attachments
        for (self.attachments) |attachment| {
            if (attachment.owned) {
                device.dispatch.destroy_image_view(device_handle, attachment.view, device.allocation_callbacks);
            }
        }

        allocator.free(self.attachments);
    }
};

/// Framebuffer configuration
pub const FramebufferConfig = struct {
    width: u32,
    height: u32,
    layers: u32 = 1,
};

/// Framebuffer manager for render pass framebuffers
pub const FramebufferManager = struct {
    allocator: std.mem.Allocator,
    device: *device_mod.Device,
    framebuffers: std.ArrayList(*ManagedFramebuffer),

    pub fn init(allocator: std.mem.Allocator, device: *device_mod.Device) !*FramebufferManager {
        const self = try allocator.create(FramebufferManager);
        self.* = .{
            .allocator = allocator,
            .device = device,
            .framebuffers = std.ArrayList(*ManagedFramebuffer).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *FramebufferManager) void {
        for (self.framebuffers.items) |fb| {
            fb.destroy(self.device, self.allocator);
            self.allocator.destroy(fb);
        }
        self.framebuffers.deinit();
        self.allocator.destroy(self);
    }

    /// Create framebuffer from explicit attachments
    pub fn createFramebuffer(
        self: *FramebufferManager,
        render_pass: types.VkRenderPass,
        attachments: []const FramebufferAttachment,
        config: FramebufferConfig,
    ) !*ManagedFramebuffer {
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;

        // Collect attachment views
        var views = try self.allocator.alloc(types.VkImageView, attachments.len);
        defer self.allocator.free(views);

        for (attachments, 0..) |attachment, i| {
            views[i] = attachment.view;
        }

        const create_info = types.VkFramebufferCreateInfo{
            .renderPass = render_pass,
            .attachmentCount = @intCast(attachments.len),
            .pAttachments = views.ptr,
            .width = config.width,
            .height = config.height,
            .layers = config.layers,
            .flags = 0,
            .pNext = null,
        };

        var framebuffer: types.VkFramebuffer = undefined;
        try errors.ensureSuccess(self.device.dispatch.create_framebuffer(
            device_handle,
            &create_info,
            self.device.allocation_callbacks,
            &framebuffer,
        ));

        // Copy attachments
        const attachment_copy = try self.allocator.alloc(FramebufferAttachment, attachments.len);
        @memcpy(attachment_copy, attachments);

        const managed = try self.allocator.create(ManagedFramebuffer);
        managed.* = .{
            .framebuffer = framebuffer,
            .attachments = attachment_copy,
            .width = config.width,
            .height = config.height,
            .layers = config.layers,
        };

        try self.framebuffers.append(managed);

        log.debug("Created framebuffer {}x{} with {} attachments", .{ config.width, config.height, attachments.len });

        return managed;
    }

    /// Destroy specific framebuffer
    pub fn destroyFramebuffer(self: *FramebufferManager, framebuffer: *ManagedFramebuffer) void {
        for (self.framebuffers.items, 0..) |fb, i| {
            if (fb == framebuffer) {
                _ = self.framebuffers.swapRemove(i);
                fb.destroy(self.device, self.allocator);
                self.allocator.destroy(fb);
                return;
            }
        }
    }
};

/// Swapchain framebuffer manager for presentation
pub const SwapchainFramebufferManager = struct {
    allocator: std.mem.Allocator,
    device: *device_mod.Device,
    swapchain: *swapchain_mod.Swapchain,
    render_pass: types.VkRenderPass,
    framebuffers: std.ArrayList(types.VkFramebuffer),
    depth_attachment: ?*image_allocator.AllocatedImage,

    pub fn init(
        allocator: std.mem.Allocator,
        device: *device_mod.Device,
        swapchain: *swapchain_mod.Swapchain,
        render_pass: types.VkRenderPass,
    ) !*SwapchainFramebufferManager {
        const self = try allocator.create(SwapchainFramebufferManager);
        self.* = .{
            .allocator = allocator,
            .device = device,
            .swapchain = swapchain,
            .render_pass = render_pass,
            .framebuffers = std.ArrayList(types.VkFramebuffer).init(allocator),
            .depth_attachment = null,
        };
        return self;
    }

    pub fn deinit(self: *SwapchainFramebufferManager) void {
        self.destroyFramebuffers();
        self.framebuffers.deinit();
        self.allocator.destroy(self);
    }

    /// Create depth attachment for swapchain framebuffers
    pub fn createDepthAttachment(
        self: *SwapchainFramebufferManager,
        img_allocator: *image_allocator.ImageAllocator,
        depth_format: types.VkFormat,
    ) !void {
        const extent = self.swapchain.extent;

        const depth_image = try img_allocator.createImage(.{
            .extent = .{
                .width = extent.width,
                .height = extent.height,
                .depth = 1,
            },
            .format = depth_format,
            .usage = types.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
            .tiling = .OPTIMAL,
            .initial_layout = .UNDEFINED,
            .samples = .@"1",
            .mip_levels = 1,
            .array_layers = 1,
        });

        self.depth_attachment = depth_image;

        log.debug("Created depth attachment {}x{} for swapchain", .{ extent.width, extent.height });
    }

    /// Create framebuffers for all swapchain images
    pub fn createFramebuffers(self: *SwapchainFramebufferManager) !void {
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;
        const extent = self.swapchain.extent;

        try self.framebuffers.ensureTotalCapacity(self.swapchain.image_views.items.len);

        for (self.swapchain.image_views.items) |view| {
            var attachments: [2]types.VkImageView = undefined;
            var attachment_count: u32 = 1;

            attachments[0] = view;

            // Add depth attachment if present
            if (self.depth_attachment) |depth| {
                attachments[1] = depth.view.?;
                attachment_count = 2;
            }

            const create_info = types.VkFramebufferCreateInfo{
                .renderPass = self.render_pass,
                .attachmentCount = attachment_count,
                .pAttachments = &attachments,
                .width = extent.width,
                .height = extent.height,
                .layers = 1,
                .flags = 0,
                .pNext = null,
            };

            var framebuffer: types.VkFramebuffer = undefined;
            try errors.ensureSuccess(self.device.dispatch.create_framebuffer(
                device_handle,
                &create_info,
                self.device.allocation_callbacks,
                &framebuffer,
            ));

            self.framebuffers.appendAssumeCapacity(framebuffer);
        }

        log.debug("Created {} framebuffers for swapchain", .{self.framebuffers.items.len});
    }

    /// Destroy all framebuffers
    pub fn destroyFramebuffers(self: *SwapchainFramebufferManager) void {
        const device_handle = self.device.handle orelse return;

        for (self.framebuffers.items) |fb| {
            self.device.dispatch.destroy_framebuffer(device_handle, fb, self.device.allocation_callbacks);
        }

        self.framebuffers.clearRetainingCapacity();

        log.debug("Destroyed swapchain framebuffers", .{});
    }

    /// Recreate framebuffers (e.g., after swapchain recreation)
    pub fn recreate(self: *SwapchainFramebufferManager) !void {
        self.destroyFramebuffers();
        try self.createFramebuffers();
    }

    /// Get framebuffer for swapchain image index
    pub fn getFramebuffer(self: *SwapchainFramebufferManager, image_index: u32) !types.VkFramebuffer {
        if (image_index >= self.framebuffers.items.len) {
            return errors.Error.InvalidImageIndex;
        }
        return self.framebuffers.items[image_index];
    }
};

/// Builder for framebuffer attachments
pub const FramebufferAttachmentBuilder = struct {
    allocator: std.mem.Allocator,
    device: *device_mod.Device,
    attachments: std.ArrayList(FramebufferAttachment),

    pub fn init(allocator: std.mem.Allocator, device: *device_mod.Device) FramebufferAttachmentBuilder {
        return .{
            .allocator = allocator,
            .device = device,
            .attachments = std.ArrayList(FramebufferAttachment).init(allocator),
        };
    }

    pub fn deinit(self: *FramebufferAttachmentBuilder) void {
        self.attachments.deinit();
    }

    /// Add attachment from existing image view (not owned)
    pub fn addAttachment(
        self: *FramebufferAttachmentBuilder,
        image: types.VkImage,
        view: types.VkImageView,
        format: types.VkFormat,
    ) !*FramebufferAttachmentBuilder {
        try self.attachments.append(.{
            .image = image,
            .view = view,
            .format = format,
            .owned = false,
        });
        return self;
    }

    /// Add attachment from allocated image (not owned)
    pub fn addAllocatedImage(
        self: *FramebufferAttachmentBuilder,
        allocated_image: *image_allocator.AllocatedImage,
    ) !*FramebufferAttachmentBuilder {
        try self.attachments.append(.{
            .image = allocated_image.image,
            .view = allocated_image.view.?,
            .format = allocated_image.format,
            .owned = false,
        });
        return self;
    }

    /// Create owned color attachment
    pub fn createColorAttachment(
        self: *FramebufferAttachmentBuilder,
        img_allocator: *image_allocator.ImageAllocator,
        width: u32,
        height: u32,
        format: types.VkFormat,
    ) !*FramebufferAttachmentBuilder {
        const image = try img_allocator.createImage(.{
            .extent = .{ .width = width, .height = height, .depth = 1 },
            .format = format,
            .usage = types.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | types.VK_IMAGE_USAGE_SAMPLED_BIT,
            .tiling = .OPTIMAL,
            .initial_layout = .UNDEFINED,
            .samples = .@"1",
            .mip_levels = 1,
            .array_layers = 1,
        });

        try self.attachments.append(.{
            .image = image.image,
            .view = image.view.?,
            .format = format,
            .owned = true,
        });

        return self;
    }

    /// Create owned depth attachment
    pub fn createDepthAttachment(
        self: *FramebufferAttachmentBuilder,
        img_allocator: *image_allocator.ImageAllocator,
        width: u32,
        height: u32,
        format: types.VkFormat,
    ) !*FramebufferAttachmentBuilder {
        const image = try img_allocator.createImage(.{
            .extent = .{ .width = width, .height = height, .depth = 1 },
            .format = format,
            .usage = types.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
            .tiling = .OPTIMAL,
            .initial_layout = .UNDEFINED,
            .samples = .@"1",
            .mip_levels = 1,
            .array_layers = 1,
        });

        try self.attachments.append(.{
            .image = image.image,
            .view = image.view.?,
            .format = format,
            .owned = true,
        });

        return self;
    }

    /// Build and return attachments
    pub fn build(self: *FramebufferAttachmentBuilder) []const FramebufferAttachment {
        return self.attachments.items;
    }
};
