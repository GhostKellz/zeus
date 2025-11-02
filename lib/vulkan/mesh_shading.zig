//! Mesh shading support for VK_EXT_mesh_shader

const std = @import("std");
const types = @import("types.zig");

const log = std.log.scoped(.mesh_shading);

pub const MeshShadingHelper = struct {
    device: types.VkDevice,
    max_mesh_work_group_count: [3]u32,
    max_task_work_group_count: [3]u32,

    pub fn init(device: types.VkDevice) MeshShadingHelper {
        return .{
            .device = device,
            .max_mesh_work_group_count = [3]u32{0, 0, 0},
            .max_task_work_group_count = [3]u32{0, 0, 0},
        };
    }

    pub fn checkMeshShadingSupport(features: anytype) bool {
        _ = features;
        return false; // Would check VkPhysicalDeviceMeshShaderFeaturesEXT
    }

    pub fn printCapabilities(self: *MeshShadingHelper) void {
        _ = self;
        log.info("=== Mesh Shading Capabilities ===", .{});
        log.info("Task shader: check features", .{});
        log.info("Mesh shader: check features", .{});
        log.info("", .{});
    }
};
