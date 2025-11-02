const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const loader = @import("loader.zig");

pub const RenderPassBuilder = struct {
    allocator: std.mem.Allocator,
    attachments: std.ArrayList(types.VkAttachmentDescription),
    color_refs: std.ArrayList(types.VkAttachmentReference),
    dependencies: std.ArrayList(types.VkSubpassDependency),

    pub fn init(allocator: std.mem.Allocator) RenderPassBuilder {
        return RenderPassBuilder{
            .allocator = allocator,
            .attachments = std.ArrayList(types.VkAttachmentDescription).init(allocator),
            .color_refs = std.ArrayList(types.VkAttachmentReference).init(allocator),
            .dependencies = std.ArrayList(types.VkSubpassDependency).init(allocator),
        };
    }

    pub fn deinit(self: *RenderPassBuilder) void {
        self.attachments.deinit();
        self.color_refs.deinit();
        self.dependencies.deinit();
    }

    pub fn addColorAttachment(self: *RenderPassBuilder, format: types.VkFormat, load_op: types.VkAttachmentLoadOp, final_layout: types.VkImageLayout) !u32 {
        const attachment = types.VkAttachmentDescription{
            .format = format,
            .samples = types.VK_SAMPLE_COUNT_1_BIT,
            .loadOp = load_op,
            .storeOp = types.VkAttachmentStoreOp.STORE,
            .stencilLoadOp = types.VkAttachmentLoadOp.DONT_CARE,
            .stencilStoreOp = types.VkAttachmentStoreOp.DONT_CARE,
            .initialLayout = types.VkImageLayout.UNDEFINED,
            .finalLayout = final_layout,
        };
        try self.attachments.append(attachment);

        const index: u32 = @intCast(self.attachments.items.len - 1);
        const reference = types.VkAttachmentReference{
            .attachment = index,
            .layout = types.VkImageLayout.COLOR_ATTACHMENT_OPTIMAL,
        };
        try self.color_refs.append(reference);
        return index;
    }

    pub fn addDependency(self: *RenderPassBuilder, dependency: types.VkSubpassDependency) !void {
        try self.dependencies.append(dependency);
    }

    pub fn build(self: *RenderPassBuilder, device: *device_mod.Device) errors.Error!types.VkRenderPass {
        const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;
        std.debug.assert(self.attachments.items.len > 0);

        var subpass = types.VkSubpassDescription{
            .pipelineBindPoint = types.VK_PIPELINE_BIND_POINT_GRAPHICS,
            .colorAttachmentCount = @intCast(self.color_refs.items.len),
            .pColorAttachments = if (self.color_refs.items.len == 0) null else self.color_refs.items.ptr,
        };

        var create_info = types.VkRenderPassCreateInfo{
            .attachmentCount = @intCast(self.attachments.items.len),
            .pAttachments = self.attachments.items.ptr,
            .subpassCount = 1,
            .pSubpasses = &subpass,
            .dependencyCount = @intCast(self.dependencies.items.len),
            .pDependencies = if (self.dependencies.items.len == 0) null else self.dependencies.items.ptr,
        };

        var render_pass: types.VkRenderPass = undefined;
        try errors.ensureSuccess(device.dispatch.create_render_pass(device_handle, &create_info, device.allocation_callbacks, &render_pass));
        return render_pass;
    }
};

pub fn destroyRenderPass(device: *device_mod.Device, render_pass: types.VkRenderPass) void {
    const device_handle = device.handle orelse return;
    device.dispatch.destroy_render_pass(device_handle, render_pass, device.allocation_callbacks);
}

pub const RenderPass = struct {
    device: *device_mod.Device,
    handle: ?types.VkRenderPass,

    pub fn init(device: *device_mod.Device, builder: *RenderPassBuilder) errors.Error!RenderPass {
        const render_pass = try builder.build(device);
        return RenderPass{ .device = device, .handle = render_pass };
    }

    pub fn deinit(self: *RenderPass) void {
        if (self.handle) |handle| {
            destroyRenderPass(self.device, handle);
            self.handle = null;
        }
    }
};

// Tests ---------------------------------------------------------------------

const fake_render_pass = @as(types.VkRenderPass, @ptrFromInt(@as(usize, 0xCAFED00D)));

const Capture = struct {
    pub var create_info: ?types.VkRenderPassCreateInfo = null;
    pub var destroy_calls: usize = 0;

    pub fn reset() void {
        create_info = null;
        destroy_calls = 0;
    }

    pub fn stubCreate(_: types.VkDevice, info: *const types.VkRenderPassCreateInfo, _: ?*const types.VkAllocationCallbacks, render_pass: *types.VkRenderPass) callconv(.c) types.VkResult {
        create_info = info.*;
        render_pass.* = fake_render_pass;
        return .SUCCESS;
    }

    pub fn stubDestroy(_: types.VkDevice, _: types.VkRenderPass, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {
        destroy_calls += 1;
    }
};

fn makeDevice() device_mod.Device {
    var device = device_mod.Device{
        .allocator = std.testing.allocator,
        .loader = undefined,
        .dispatch = undefined,
        .handle = @as(types.VkDevice, @ptrFromInt(@as(usize, 0xA55A5AAA))),
        .allocation_callbacks = null,
    };
    device.dispatch.create_render_pass = Capture.stubCreate;
    device.dispatch.destroy_render_pass = Capture.stubDestroy;
    return device;
}

test "RenderPassBuilder builds single color attachment" {
    Capture.reset();
    var device = makeDevice();
    var builder = RenderPassBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.addColorAttachment(.R8G8B8A8_UNORM, types.VkAttachmentLoadOp.CLEAR, types.VkImageLayout.PRESENT_SRC_KHR);
    const render_pass = try builder.build(&device);
    try std.testing.expectEqual(fake_render_pass, render_pass);

    const info = Capture.create_info orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(u32, 1), info.attachmentCount);
    try std.testing.expectEqual(@as(u32, 1), info.subpassCount);
    try std.testing.expect(info.pAttachments != null);
    try std.testing.expect(info.pSubpasses != null);
    const subpass = info.pSubpasses.*;
    try std.testing.expectEqual(@as(u32, 1), subpass.colorAttachmentCount);
}

test "RenderPass.deinit destroys once" {
    Capture.reset();
    var device = makeDevice();
    var builder = RenderPassBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addColorAttachment(.B8G8R8A8_SRGB, types.VkAttachmentLoadOp.CLEAR, types.VkImageLayout.PRESENT_SRC_KHR);

    var render_pass = try RenderPass.init(&device, &builder);
    try std.testing.expectEqual(fake_render_pass, render_pass.handle.?);
    render_pass.deinit();
    try std.testing.expectEqual(@as(usize, 1), Capture.destroy_calls);
    render_pass.deinit();
    try std.testing.expectEqual(@as(usize, 1), Capture.destroy_calls);
}
