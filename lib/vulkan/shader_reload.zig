//! Hot shader reload for development iteration

const std = @import("std");
const types = @import("types.zig");

const log = std.log.scoped(.shader_reload);

pub const ShaderReloader = struct {
    allocator: std.mem.Allocator,
    device: types.VkDevice,
    watch_paths: std.ArrayList([]const u8),
    last_modified: std.StringHashMap(i128),

    pub fn init(allocator: std.mem.Allocator, device: types.VkDevice) ShaderReloader {
        return .{
            .allocator = allocator,
            .device = device,
            .watch_paths = std.ArrayList([]const u8).init(allocator),
            .last_modified = std.StringHashMap(i128).init(allocator),
        };
    }

    pub fn deinit(self: *ShaderReloader) void {
        for (self.watch_paths.items) |path| {
            self.allocator.free(path);
        }
        self.watch_paths.deinit();
        self.last_modified.deinit();
    }

    pub fn watchShader(self: *ShaderReloader, path: []const u8) !void {
        const owned_path = try self.allocator.dupe(u8, path);
        try self.watch_paths.append(owned_path);
        log.info("Watching shader: {s}", .{path});
    }

    pub fn checkForChanges(self: *ShaderReloader) bool {
        _ = self;
        // Would check file modification times
        return false;
    }

    pub fn reloadShaders(self: *ShaderReloader) !void {
        _ = self;
        log.info("Reloading shaders...", .{});
        // Would recompile and recreate pipelines
    }
};
