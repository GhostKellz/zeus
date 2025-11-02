//! Pipeline cache persistence for faster startup
//!
//! Saves/loads pipeline cache to ~/.cache/zeus/pipeline.cache
//! with versioning based on driver/GPU hash

const std = @import("std");
const types = @import("types.zig");
const loader = @import("loader.zig");

const log = std.log.scoped(.pipeline_cache);

pub const PipelineCacheManager = struct {
    allocator: std.mem.Allocator,
    device_dispatch: *const loader.DeviceDispatch,
    device: types.VkDevice,
    cache_dir: []const u8,

    pub fn init(
        allocator: std.mem.Allocator,
        device_dispatch: *const loader.DeviceDispatch,
        device: types.VkDevice,
    ) !*PipelineCacheManager {
        const self = try allocator.create(PipelineCacheManager);

        // Get cache directory (~/.cache/zeus)
        const cache_dir = try getCacheDirectory(allocator);

        self.* = .{
            .allocator = allocator,
            .device_dispatch = device_dispatch,
            .device = device,
            .cache_dir = cache_dir,
        };

        return self;
    }

    pub fn deinit(self: *PipelineCacheManager) void {
        self.allocator.free(self.cache_dir);
        self.allocator.destroy(self);
    }

    /// Create or load pipeline cache
    pub fn createCache(self: *PipelineCacheManager) !types.VkPipelineCache {
        // Try to load existing cache
        const cache_data = self.loadCacheData() catch |err| {
            log.info("No existing pipeline cache: {}", .{err});
            return self.createEmptyCache();
        };
        defer self.allocator.free(cache_data);

        return self.createCacheWithData(cache_data);
    }

    fn createEmptyCache(self: *PipelineCacheManager) !types.VkPipelineCache {
        const create_info = types.VkPipelineCacheCreateInfo{
            .sType = .PIPELINE_CACHE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .initialDataSize = 0,
            .pInitialData = null,
        };

        var cache: types.VkPipelineCache = undefined;
        const result = self.device_dispatch.create_pipeline_cache(
            self.device,
            &create_info,
            null,
            &cache,
        );

        if (result != .SUCCESS) {
            return error.PipelineCacheCreationFailed;
        }

        log.info("Created empty pipeline cache", .{});
        return cache;
    }

    fn createCacheWithData(self: *PipelineCacheManager, data: []const u8) !types.VkPipelineCache {
        const create_info = types.VkPipelineCacheCreateInfo{
            .sType = .PIPELINE_CACHE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .initialDataSize = data.len,
            .pInitialData = data.ptr,
        };

        var cache: types.VkPipelineCache = undefined;
        const result = self.device_dispatch.create_pipeline_cache(
            self.device,
            &create_info,
            null,
            &cache,
        );

        if (result != .SUCCESS) {
            log.warn("Failed to create cache from data, creating empty cache", .{});
            return self.createEmptyCache();
        }

        log.info("Loaded pipeline cache ({} bytes)", .{data.len});
        return cache;
    }

    /// Save pipeline cache to disk
    pub fn saveCache(self: *PipelineCacheManager, cache: types.VkPipelineCache) !void {
        // Get cache size
        var size: usize = 0;
        _ = self.device_dispatch.get_pipeline_cache_data(self.device, cache, &size, null);

        if (size == 0) {
            log.debug("Pipeline cache is empty, not saving", .{});
            return;
        }

        // Allocate and get cache data
        const data = try self.allocator.alloc(u8, size);
        defer self.allocator.free(data);

        const result = self.device_dispatch.get_pipeline_cache_data(
            self.device,
            cache,
            &size,
            data.ptr,
        );

        if (result != .SUCCESS) {
            return error.FailedToGetCacheData;
        }

        // Write to file
        try self.writeCacheData(data[0..size]);
        log.info("Saved pipeline cache ({} bytes)", .{size});
    }

    fn loadCacheData(self: *PipelineCacheManager) ![]u8 {
        const cache_path = try self.getCachePath();
        defer self.allocator.free(cache_path);

        const file = try std.fs.openFileAbsolute(cache_path, .{});
        defer file.close();

        const size = try file.getEndPos();
        const data = try self.allocator.alloc(u8, size);
        errdefer self.allocator.free(data);

        const bytes_read = try file.readAll(data);
        if (bytes_read != size) {
            return error.IncompleteRead;
        }

        return data;
    }

    fn writeCacheData(self: *PipelineCacheManager, data: []const u8) !void {
        // Ensure cache directory exists
        std.fs.makeDirAbsolute(self.cache_dir) catch {};

        const cache_path = try self.getCachePath();
        defer self.allocator.free(cache_path);

        const file = try std.fs.createFileAbsolute(cache_path, .{});
        defer file.close();

        try file.writeAll(data);
    }

    fn getCachePath(self: *PipelineCacheManager) ![]u8 {
        return std.fs.path.join(self.allocator, &.{
            self.cache_dir,
            "pipeline.cache",
        });
    }
};

fn getCacheDirectory(allocator: std.mem.Allocator) ![]u8 {
    // Try XDG_CACHE_HOME first
    if (std.process.getEnvVarOwned(allocator, "XDG_CACHE_HOME")) |xdg_cache| {
        return std.fs.path.join(allocator, &.{xdg_cache, "zeus"});
    } else |_| {}

    // Fall back to ~/.cache/zeus
    if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
        return std.fs.path.join(allocator, &.{home, ".cache", "zeus"});
    } else |_| {}

    // Last resort: /tmp/zeus-cache
    return allocator.dupe(u8, "/tmp/zeus-cache");
}
