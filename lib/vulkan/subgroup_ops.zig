//! Subgroup operations helpers for optimized compute/fragment work

const std = @import("std");
const types = @import("types.zig");

const log = std.log.scoped(.subgroup_ops);

pub const SubgroupInfo = struct {
    subgroup_size: u32,
    supported_stages: u32,
    supported_operations: u32,
    quad_operations_in_all_stages: bool,

    pub fn init() SubgroupInfo {
        return .{
            .subgroup_size = 0,
            .supported_stages = 0,
            .supported_operations = 0,
            .quad_operations_in_all_stages = false,
        };
    }

    pub fn printCapabilities(self: *SubgroupInfo) void {
        log.info("=== Subgroup Capabilities ===", .{});
        log.info("Subgroup size: {}", .{self.subgroup_size});
        log.info("Quad operations: {}", .{self.quad_operations_in_all_stages});
        log.info("", .{});
    }
};
