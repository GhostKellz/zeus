// Extension types for Vulkan - VK_KHR_*, VK_EXT_*
// These are promotion candidates or commonly-used extensions
const types = @import("types.zig");

//
// VK_EXT_debug_utils - Debug messenger for validation layers
//

pub const VkDebugUtilsMessengerEXT = types.VkNonDispatchableHandle;

pub const VkDebugUtilsMessageSeverityFlagBitsEXT = enum(u32) {
    verbose = 0x00000001,
    info = 0x00000010,
    warning = 0x00000100,
    error_ = 0x00001000,
};

pub const VkDebugUtilsMessageTypeFlagBitsEXT = enum(u32) {
    general = 0x00000001,
    validation = 0x00000002,
    performance = 0x00000004,
};

pub const VkDebugUtilsMessageSeverityFlagsEXT = u32;
pub const VkDebugUtilsMessageTypeFlagsEXT = u32;

pub const VkDebugUtilsMessengerCallbackDataEXT = extern struct {
    s_type: types.VkStructureType = .debug_utils_messenger_callback_data_ext,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    p_message_id_name: ?[*:0]const u8,
    message_id_number: i32,
    p_message: [*:0]const u8,
    queue_label_count: u32 = 0,
    p_queue_labels: ?*const anyopaque = null,
    cmd_buf_label_count: u32 = 0,
    p_cmd_buf_labels: ?*const anyopaque = null,
    object_count: u32 = 0,
    p_objects: ?*const anyopaque = null,
};

pub const PFN_vkDebugUtilsMessengerCallbackEXT = *const fn (
    VkDebugUtilsMessageSeverityFlagsEXT,
    VkDebugUtilsMessageTypeFlagsEXT,
    *const VkDebugUtilsMessengerCallbackDataEXT,
    ?*anyopaque,
) callconv(.c) u32;

pub const VkDebugUtilsMessengerCreateInfoEXT = extern struct {
    s_type: types.VkStructureType = .debug_utils_messenger_create_info_ext,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    message_severity: VkDebugUtilsMessageSeverityFlagsEXT,
    message_type: VkDebugUtilsMessageTypeFlagsEXT,
    pfn_user_callback: PFN_vkDebugUtilsMessengerCallbackEXT,
    p_user_data: ?*anyopaque = null,
};

pub const PFN_vkCreateDebugUtilsMessengerEXT = *const fn (
    types.VkInstance,
    *const VkDebugUtilsMessengerCreateInfoEXT,
    ?*const types.VkAllocationCallbacks,
    *VkDebugUtilsMessengerEXT,
) callconv(.c) types.VkResult;

pub const PFN_vkDestroyDebugUtilsMessengerEXT = *const fn (
    types.VkInstance,
    VkDebugUtilsMessengerEXT,
    ?*const types.VkAllocationCallbacks,
) callconv(.c) void;

//
// VK_KHR_dynamic_rendering (promoted to Vulkan 1.3 core)
//

pub const VkRenderingFlagsKHR = u32;

pub const VkRenderingInfoKHR = extern struct {
    s_type: types.VkStructureType = .rendering_info_khr,
    p_next: ?*const anyopaque = null,
    flags: VkRenderingFlagsKHR = 0,
    render_area: types.VkRect2D,
    layer_count: u32,
    view_mask: u32 = 0,
    color_attachment_count: u32,
    p_color_attachments: [*]const VkRenderingAttachmentInfoKHR,
    p_depth_attachment: ?*const VkRenderingAttachmentInfoKHR = null,
    p_stencil_attachment: ?*const VkRenderingAttachmentInfoKHR = null,
};

pub const VkRenderingAttachmentInfoKHR = extern struct {
    s_type: types.VkStructureType = .rendering_attachment_info_khr,
    p_next: ?*const anyopaque = null,
    image_view: types.VkImageView,
    image_layout: types.VkImageLayout,
    resolve_mode: types.VkResolveModeFlags = 0,
    resolve_image_view: types.VkImageView = .null_handle,
    resolve_image_layout: types.VkImageLayout = .undefined,
    load_op: types.VkAttachmentLoadOp,
    store_op: types.VkAttachmentStoreOp,
    clear_value: types.VkClearValue,
};

pub const PFN_vkCmdBeginRenderingKHR = *const fn (
    types.VkCommandBuffer,
    *const VkRenderingInfoKHR,
) callconv(.c) void;

pub const PFN_vkCmdEndRenderingKHR = *const fn (
    types.VkCommandBuffer,
) callconv(.c) void;

//
// VK_EXT_descriptor_indexing (promoted to Vulkan 1.2 core)
//

pub const VkDescriptorBindingFlagsEXT = u32;

pub const VkDescriptorBindingFlagBitsEXT = enum(u32) {
    update_after_bind = 0x00000001,
    update_unused_while_pending = 0x00000002,
    partially_bound = 0x00000004,
    variable_descriptor_count = 0x00000008,
};

pub const VkDescriptorSetLayoutBindingFlagsCreateInfoEXT = extern struct {
    s_type: types.VkStructureType = .descriptor_set_layout_binding_flags_create_info_ext,
    p_next: ?*const anyopaque = null,
    binding_count: u32,
    p_binding_flags: [*]const VkDescriptorBindingFlagsEXT,
};

//
// VK_KHR_acceleration_structure (Ray Tracing - future)
//

pub const VkAccelerationStructureKHR = types.VkNonDispatchableHandle;

pub const VkAccelerationStructureTypeKHR = enum(u32) {
    top_level = 0,
    bottom_level = 1,
    generic = 2,
};

pub const VkAccelerationStructureBuildTypeKHR = enum(u32) {
    host = 0,
    device = 1,
    host_or_device = 2,
};

//
// VK_KHR_ray_tracing_pipeline (Ray Tracing - future)
//

pub const VkRayTracingShaderGroupTypeKHR = enum(u32) {
    general = 0,
    triangles_hit_group = 1,
    procedural_hit_group = 2,
};

pub const VkShaderGroupShaderKHR = enum(u32) {
    general = 0,
    closest_hit = 1,
    any_hit = 2,
    intersection = 3,
};

//
// Common extension constants
//

pub const VK_EXT_DEBUG_UTILS_EXTENSION_NAME = "VK_EXT_debug_utils";
pub const VK_KHR_DYNAMIC_RENDERING_EXTENSION_NAME = "VK_KHR_dynamic_rendering";
pub const VK_EXT_DESCRIPTOR_INDEXING_EXTENSION_NAME = "VK_EXT_descriptor_indexing";
pub const VK_KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME = "VK_KHR_acceleration_structure";
pub const VK_KHR_RAY_TRACING_PIPELINE_EXTENSION_NAME = "VK_KHR_ray_tracing_pipeline";
