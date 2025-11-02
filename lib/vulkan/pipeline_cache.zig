const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");

pub const Options = struct {
    path: ?[]const u8 = null,
};

pub const PipelineCache = struct {
    allocator: std.mem.Allocator,
    device: *device_mod.Device,
    handle: ?types.VkPipelineCache,
    path: ?[]u8,
    dirty: bool = false,

    pub fn init(allocator: std.mem.Allocator, device: *device_mod.Device, options: Options) errors.Error!PipelineCache {
        const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;

        var path_copy: ?[]u8 = null;
        if (options.path) |path| {
            path_copy = try allocator.alloc(u8, path.len);
            std.mem.copyForwards(u8, path_copy.?, path);
        }

        var initial_data: ?[]u8 = null;
        if (options.path) |path| {
            initial_data = try loadExistingCache(allocator, path);
        }
        defer if (initial_data) |data| allocator.free(data);

        const empty_slice = &[_]u8{};
        const data_slice = initial_data orelse empty_slice[0..];

        var create_info = types.VkPipelineCacheCreateInfo{
            .initialDataSize = data_slice.len,
            .pInitialData = if (data_slice.len == 0)
                null
            else
                @as(*const anyopaque, @ptrCast(data_slice.ptr)),
        };

        var cache_handle: types.VkPipelineCache = undefined;
        try errors.ensureSuccess(device.dispatch.create_pipeline_cache(device_handle, &create_info, device.allocation_callbacks, &cache_handle));

        return PipelineCache{
            .allocator = allocator,
            .device = device,
            .handle = cache_handle,
            .path = path_copy,
            .dirty = initial_data == null,
        };
    }

    pub fn deinit(self: *PipelineCache) void {
        if (self.handle) |cache_handle| {
            const device_handle = self.device.handle orelse return;
            self.device.dispatch.destroy_pipeline_cache(device_handle, cache_handle, self.device.allocation_callbacks);
            self.handle = null;
        }
        if (self.path) |path_slice| {
            self.allocator.free(path_slice);
            self.path = null;
        }
    }

    pub fn handleRef(self: *const PipelineCache) ?types.VkPipelineCache {
        return self.handle;
    }

    pub fn markDirty(self: *PipelineCache) void {
        self.dirty = true;
    }

    pub fn persist(self: *PipelineCache) errors.Error!void {
        if (!self.dirty) return;
        if (self.path == null) return;
        const cache_handle = self.handle orelse return;
        const device_handle = self.device.handle orelse return;

        var size: usize = 0;
        try errors.ensureSuccess(self.device.dispatch.get_pipeline_cache_data(device_handle, cache_handle, &size, null));
        if (size == 0) return;

        var data = try self.allocator.alloc(u8, size);
        defer self.allocator.free(data);

        try errors.ensureSuccess(self.device.dispatch.get_pipeline_cache_data(device_handle, cache_handle, &size, @as(*anyopaque, @ptrCast(data.ptr))));

        var file = try std.fs.createFileAbsolute(self.path.?, .{ .truncate = true, .read = false, .mode = 0o644 });
        defer file.close();

        try file.writeAll(data[0..size]);
        self.dirty = false;
    }
};

fn loadExistingCache(allocator: std.mem.Allocator, path: []const u8) !?[]u8 {
    var file = std.fs.openFileAbsolute(path, .{}) catch return null;
    defer file.close();

    const max_read: usize = 16 * 1024 * 1024;
    const data = try file.readToEndAlloc(allocator, max_read);
    return data;
}
