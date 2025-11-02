//! Debug utilities for object naming, markers, and labels (RenderDoc integration)

const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const instance_mod = @import("instance.zig");

const log = std.log.scoped(.debug_utils);

/// Debug label color
pub const DebugColor = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub const red = DebugColor{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 };
    pub const green = DebugColor{ .r = 0.0, .g = 1.0, .b = 0.0, .a = 1.0 };
    pub const blue = DebugColor{ .r = 0.0, .g = 0.0, .b = 1.0, .a = 1.0 };
    pub const yellow = DebugColor{ .r = 1.0, .g = 1.0, .b = 0.0, .a = 1.0 };
    pub const magenta = DebugColor{ .r = 1.0, .g = 0.0, .b = 1.0, .a = 1.0 };
    pub const cyan = DebugColor{ .r = 0.0, .g = 1.0, .b = 1.0, .a = 1.0 };
    pub const white = DebugColor{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };
    pub const gray = DebugColor{ .r = 0.5, .g = 0.5, .b = 0.5, .a = 1.0 };

    pub fn toArray(self: DebugColor) [4]f32 {
        return [_]f32{ self.r, self.g, self.b, self.a };
    }
};

/// Debug utilities manager
pub const DebugUtils = struct {
    device: *device_mod.Device,
    instance: *instance_mod.Instance,
    enabled: bool,
    has_debug_utils_ext: bool,

    pub fn init(device: *device_mod.Device, instance: *instance_mod.Instance) !*DebugUtils {
        const self = try device.allocator.create(DebugUtils);

        // Check for VK_EXT_debug_utils
        const has_ext = device.hasExtension("VK_EXT_debug_utils");

        self.* = .{
            .device = device,
            .instance = instance,
            .enabled = has_ext,
            .has_debug_utils_ext = has_ext,
        };

        if (has_ext) {
            log.info("VK_EXT_debug_utils available - debug markers enabled", .{});
        } else {
            log.warn("VK_EXT_debug_utils not available - debug markers disabled", .{});
        }

        return self;
    }

    pub fn deinit(self: *DebugUtils) void {
        self.device.allocator.destroy(self);
    }

    /// Set debug name for an object
    pub fn setObjectName(
        self: *DebugUtils,
        object_type: types.VkObjectType,
        object_handle: u64,
        name: [*:0]const u8,
    ) void {
        if (!self.enabled) return;

        const device_handle = self.device.handle orelse return;

        const name_info = types.VkDebugUtilsObjectNameInfoEXT{
            .sType = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
            .pNext = null,
            .objectType = object_type,
            .objectHandle = object_handle,
            .pObjectName = name,
        };

        _ = self.device.dispatch.set_debug_utils_object_name_ext(device_handle, &name_info);
    }

    /// Set debug tag for an object
    pub fn setObjectTag(
        self: *DebugUtils,
        object_type: types.VkObjectType,
        object_handle: u64,
        tag_name: u64,
        tag_data: []const u8,
    ) void {
        if (!self.enabled) return;

        const device_handle = self.device.handle orelse return;

        const tag_info = types.VkDebugUtilsObjectTagInfoEXT{
            .sType = .DEBUG_UTILS_OBJECT_TAG_INFO_EXT,
            .pNext = null,
            .objectType = object_type,
            .objectHandle = object_handle,
            .tagName = tag_name,
            .tagSize = tag_data.len,
            .pTag = tag_data.ptr,
        };

        _ = self.device.dispatch.set_debug_utils_object_tag_ext(device_handle, &tag_info);
    }

    /// Begin command buffer debug label
    pub fn cmdBeginLabel(
        self: *DebugUtils,
        command_buffer: types.VkCommandBuffer,
        name: [*:0]const u8,
        color: DebugColor,
    ) void {
        if (!self.enabled) return;

        const label = types.VkDebugUtilsLabelEXT{
            .sType = .DEBUG_UTILS_LABEL_EXT,
            .pNext = null,
            .pLabelName = name,
            .color = color.toArray(),
        };

        self.device.dispatch.cmd_begin_debug_utils_label_ext(command_buffer, &label);
    }

    /// End command buffer debug label
    pub fn cmdEndLabel(self: *DebugUtils, command_buffer: types.VkCommandBuffer) void {
        if (!self.enabled) return;
        self.device.dispatch.cmd_end_debug_utils_label_ext(command_buffer);
    }

    /// Insert command buffer debug label
    pub fn cmdInsertLabel(
        self: *DebugUtils,
        command_buffer: types.VkCommandBuffer,
        name: [*:0]const u8,
        color: DebugColor,
    ) void {
        if (!self.enabled) return;

        const label = types.VkDebugUtilsLabelEXT{
            .sType = .DEBUG_UTILS_LABEL_EXT,
            .pNext = null,
            .pLabelName = name,
            .color = color.toArray(),
        };

        self.device.dispatch.cmd_insert_debug_utils_label_ext(command_buffer, &label);
    }

    /// Begin queue debug label
    pub fn queueBeginLabel(
        self: *DebugUtils,
        queue: types.VkQueue,
        name: [*:0]const u8,
        color: DebugColor,
    ) void {
        if (!self.enabled) return;

        const label = types.VkDebugUtilsLabelEXT{
            .sType = .DEBUG_UTILS_LABEL_EXT,
            .pNext = null,
            .pLabelName = name,
            .color = color.toArray(),
        };

        self.device.dispatch.queue_begin_debug_utils_label_ext(queue, &label);
    }

    /// End queue debug label
    pub fn queueEndLabel(self: *DebugUtils, queue: types.VkQueue) void {
        if (!self.enabled) return;
        self.device.dispatch.queue_end_debug_utils_label_ext(queue);
    }

    /// Convenience: Name common Vulkan objects
    pub fn nameBuffer(self: *DebugUtils, buffer: types.VkBuffer, name: [*:0]const u8) void {
        self.setObjectName(.BUFFER, @intFromEnum(buffer), name);
    }

    pub fn nameImage(self: *DebugUtils, image: types.VkImage, name: [*:0]const u8) void {
        self.setObjectName(.IMAGE, @intFromEnum(image), name);
    }

    pub fn nameImageView(self: *DebugUtils, view: types.VkImageView, name: [*:0]const u8) void {
        self.setObjectName(.IMAGE_VIEW, @intFromEnum(view), name);
    }

    pub fn nameSampler(self: *DebugUtils, sampler: types.VkSampler, name: [*:0]const u8) void {
        self.setObjectName(.SAMPLER, @intFromEnum(sampler), name);
    }

    pub fn nameDescriptorSet(self: *DebugUtils, set: types.VkDescriptorSet, name: [*:0]const u8) void {
        self.setObjectName(.DESCRIPTOR_SET, @intFromEnum(set), name);
    }

    pub fn namePipeline(self: *DebugUtils, pipeline: types.VkPipeline, name: [*:0]const u8) void {
        self.setObjectName(.PIPELINE, @intFromEnum(pipeline), name);
    }

    pub fn namePipelineLayout(self: *DebugUtils, layout: types.VkPipelineLayout, name: [*:0]const u8) void {
        self.setObjectName(.PIPELINE_LAYOUT, @intFromEnum(layout), name);
    }

    pub fn nameRenderPass(self: *DebugUtils, render_pass: types.VkRenderPass, name: [*:0]const u8) void {
        self.setObjectName(.RENDER_PASS, @intFromEnum(render_pass), name);
    }

    pub fn nameFramebuffer(self: *DebugUtils, framebuffer: types.VkFramebuffer, name: [*:0]const u8) void {
        self.setObjectName(.FRAMEBUFFER, @intFromEnum(framebuffer), name);
    }

    pub fn nameCommandBuffer(self: *DebugUtils, command_buffer: types.VkCommandBuffer, name: [*:0]const u8) void {
        self.setObjectName(.COMMAND_BUFFER, @intFromEnum(command_buffer), name);
    }

    pub fn nameQueue(self: *DebugUtils, queue: types.VkQueue, name: [*:0]const u8) void {
        self.setObjectName(.QUEUE, @intFromEnum(queue), name);
    }

    pub fn nameSemaphore(self: *DebugUtils, semaphore: types.VkSemaphore, name: [*:0]const u8) void {
        self.setObjectName(.SEMAPHORE, @intFromEnum(semaphore), name);
    }

    pub fn nameFence(self: *DebugUtils, fence: types.VkFence, name: [*:0]const u8) void {
        self.setObjectName(.FENCE, @intFromEnum(fence), name);
    }

    pub fn nameDeviceMemory(self: *DebugUtils, memory: types.VkDeviceMemory, name: [*:0]const u8) void {
        self.setObjectName(.DEVICE_MEMORY, @intFromEnum(memory), name);
    }

    pub fn nameShaderModule(self: *DebugUtils, shader: types.VkShaderModule, name: [*:0]const u8) void {
        self.setObjectName(.SHADER_MODULE, @intFromEnum(shader), name);
    }
};

/// RAII debug label for command buffers
pub const ScopedDebugLabel = struct {
    debug_utils: *DebugUtils,
    command_buffer: types.VkCommandBuffer,

    pub fn begin(
        debug_utils: *DebugUtils,
        command_buffer: types.VkCommandBuffer,
        name: [*:0]const u8,
        color: DebugColor,
    ) ScopedDebugLabel {
        debug_utils.cmdBeginLabel(command_buffer, name, color);
        return .{
            .debug_utils = debug_utils,
            .command_buffer = command_buffer,
        };
    }

    pub fn end(self: *ScopedDebugLabel) void {
        self.debug_utils.cmdEndLabel(self.command_buffer);
    }
};

/// RAII debug label for queues
pub const ScopedQueueLabel = struct {
    debug_utils: *DebugUtils,
    queue: types.VkQueue,

    pub fn begin(
        debug_utils: *DebugUtils,
        queue: types.VkQueue,
        name: [*:0]const u8,
        color: DebugColor,
    ) ScopedQueueLabel {
        debug_utils.queueBeginLabel(queue, name, color);
        return .{
            .debug_utils = debug_utils,
            .queue = queue,
        };
    }

    pub fn end(self: *ScopedQueueLabel) void {
        self.debug_utils.queueEndLabel(self.queue);
    }
};

/// Common debug label presets
pub const DebugLabels = struct {
    pub const geometry_pass = struct {
        pub const name: [:0]const u8 = "Geometry Pass";
        pub const color = DebugColor.blue;
    };

    pub const lighting_pass = struct {
        pub const name: [:0]const u8 = "Lighting Pass";
        pub const color = DebugColor.yellow;
    };

    pub const shadow_pass = struct {
        pub const name: [:0]const u8 = "Shadow Pass";
        pub const color = DebugColor.gray;
    };

    pub const post_processing = struct {
        pub const name: [:0]const u8 = "Post Processing";
        pub const color = DebugColor.magenta;
    };

    pub const compute_pass = struct {
        pub const name: [:0]const u8 = "Compute Pass";
        pub const color = DebugColor.green;
    };

    pub const transfer_pass = struct {
        pub const name: [:0]const u8 = "Transfer Pass";
        pub const color = DebugColor.cyan;
    };

    pub const ui_pass = struct {
        pub const name: [:0]const u8 = "UI Pass";
        pub const color = DebugColor.white;
    };

    pub const present_pass = struct {
        pub const name: [:0]const u8 = "Present";
        pub const color = DebugColor.red;
    };
};
