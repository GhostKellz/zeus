/// High-level query pool abstraction for timestamp queries and performance profiling
const std = @import("std");
const types = @import("types.zig");
const loader = @import("loader.zig");

/// Query pool for timestamp queries (GPU timing)
pub const TimestampQueryPool = struct {
    device: types.VkDevice,
    device_dispatch: *const loader.DeviceDispatch,
    pool: types.VkQueryPool,
    query_count: u32,
    timestamp_period: f32, // nanoseconds per timestamp unit

    pub const Options = struct {
        query_count: u32 = 64, // Number of timestamp queries to allocate
    };

    /// Create a new timestamp query pool
    pub fn init(
        device: types.VkDevice,
        device_dispatch: *const loader.DeviceDispatch,
        timestamp_period_ns: f32,
        options: Options,
    ) !TimestampQueryPool {
        const create_info = types.VkQueryPoolCreateInfo{
            .query_type = .timestamp,
            .query_count = options.query_count,
        };

        var pool: types.VkQueryPool = undefined;
        const result = device_dispatch.create_query_pool(device, &create_info, null, &pool);
        if (result != .success) return error.QueryPoolCreationFailed;

        return TimestampQueryPool{
            .device = device,
            .device_dispatch = device_dispatch,
            .pool = pool,
            .query_count = options.query_count,
            .timestamp_period = timestamp_period_ns,
        };
    }

    /// Destroy the query pool
    pub fn deinit(self: *TimestampQueryPool) void {
        self.device_dispatch.destroy_query_pool(self.device, self.pool, null);
    }

    /// Reset all queries in the pool
    pub fn reset(self: *TimestampQueryPool, cmd: types.VkCommandBuffer) void {
        self.device_dispatch.cmd_reset_query_pool(cmd, self.pool, 0, self.query_count);
    }

    /// Write a timestamp to the specified query index
    pub fn writeTimestamp(
        self: *TimestampQueryPool,
        cmd: types.VkCommandBuffer,
        stage: types.VkPipelineStageFlags,
        query_index: u32,
    ) void {
        std.debug.assert(query_index < self.query_count);
        self.device_dispatch.cmd_write_timestamp(cmd, stage, self.pool, query_index);
    }

    /// Get timestamp results (returns nanoseconds)
    pub fn getResults(
        self: *TimestampQueryPool,
        first_query: u32,
        query_count: u32,
        allocator: std.mem.Allocator,
    ) ![]u64 {
        std.debug.assert(first_query + query_count <= self.query_count);

        const results = try allocator.alloc(u64, query_count);
        errdefer allocator.free(results);

        const result = self.device_dispatch.get_query_pool_results(
            self.device,
            self.pool,
            first_query,
            query_count,
            query_count * @sizeOf(u64),
            results.ptr,
            @sizeOf(u64),
            @intFromEnum(types.VkQueryResultFlagBits.result_64) |
                @intFromEnum(types.VkQueryResultFlagBits.wait),
        );

        if (result != .success) {
            allocator.free(results);
            return error.QueryResultsFailed;
        }

        return results;
    }

    /// Calculate duration between two query indices (in nanoseconds)
    pub fn calculateDuration(
        self: *TimestampQueryPool,
        start_query: u32,
        _: u32, // end_query - reserved for future use
        allocator: std.mem.Allocator,
    ) !f64 {
        const timestamps = try self.getResults(start_query, 2, allocator);
        defer allocator.free(timestamps);

        const start = timestamps[0];
        const end = timestamps[1];
        const ticks: f64 = @floatFromInt(end - start);
        return ticks * self.timestamp_period;
    }
};

/// Scoped timestamp measurement helper
pub const ScopedTimestamp = struct {
    pool: *TimestampQueryPool,
    cmd: types.VkCommandBuffer,
    start_index: u32,
    end_index: u32,

    /// Begin a scoped timestamp measurement
    pub fn begin(
        pool: *TimestampQueryPool,
        cmd: types.VkCommandBuffer,
        start_index: u32,
        end_index: u32,
    ) ScopedTimestamp {
        pool.writeTimestamp(cmd, @intFromEnum(types.VkPipelineStageFlagBits.top_of_pipe), start_index);
        return ScopedTimestamp{
            .pool = pool,
            .cmd = cmd,
            .start_index = start_index,
            .end_index = end_index,
        };
    }

    /// End the scoped timestamp measurement
    pub fn end(self: *ScopedTimestamp) void {
        self.pool.writeTimestamp(self.cmd, @intFromEnum(types.VkPipelineStageFlagBits.bottom_of_pipe), self.end_index);
    }

    /// Retrieve the duration in nanoseconds
    pub fn getDuration(self: *ScopedTimestamp, allocator: std.mem.Allocator) !f64 {
        return self.pool.calculateDuration(self.start_index, self.end_index, allocator);
    }
};

/// Performance profiler with named sections
pub const Profiler = struct {
    pool: TimestampQueryPool,
    sections: std.StringHashMap(Section),
    allocator: std.mem.Allocator,
    next_query: u32 = 0,

    const Section = struct {
        start_query: u32,
        end_query: u32,
        last_duration_ns: f64 = 0.0,
    };

    pub fn init(
        device: types.VkDevice,
        device_dispatch: *const loader.DeviceDispatch,
        timestamp_period_ns: f32,
        allocator: std.mem.Allocator,
        max_queries: u32,
    ) !Profiler {
        const pool = try TimestampQueryPool.init(device, device_dispatch, timestamp_period_ns, .{
            .query_count = max_queries,
        });

        return Profiler{
            .pool = pool,
            .sections = std.StringHashMap(Section).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Profiler) void {
        self.sections.deinit();
        self.pool.deinit();
    }

    /// Reset all queries for a new frame
    pub fn reset(self: *Profiler, cmd: types.VkCommandBuffer) void {
        self.pool.reset(cmd);
        self.next_query = 0;
    }

    /// Begin timing a named section
    pub fn beginSection(self: *Profiler, cmd: types.VkCommandBuffer, name: []const u8) !void {
        const start_query = self.next_query;
        self.next_query += 2; // Reserve start and end

        if (self.next_query > self.pool.query_count) return error.QueryPoolExhausted;

        self.pool.writeTimestamp(cmd, @intFromEnum(types.VkPipelineStageFlagBits.top_of_pipe), start_query);

        try self.sections.put(name, Section{
            .start_query = start_query,
            .end_query = start_query + 1,
        });
    }

    /// End timing a named section
    pub fn endSection(self: *Profiler, cmd: types.VkCommandBuffer, name: []const u8) !void {
        const section = self.sections.get(name) orelse return error.SectionNotFound;
        self.pool.writeTimestamp(cmd, @intFromEnum(types.VkPipelineStageFlagBits.bottom_of_pipe), section.end_query);
    }

    /// Retrieve results for all sections
    pub fn collectResults(self: *Profiler) !void {
        var it = self.sections.iterator();
        while (it.next()) |entry| {
            const duration = try self.pool.calculateDuration(
                entry.value_ptr.start_query,
                entry.value_ptr.end_query,
                self.allocator,
            );
            entry.value_ptr.last_duration_ns = duration;
        }
    }

    /// Get the last duration for a named section (in milliseconds)
    pub fn getSectionDurationMs(self: *Profiler, name: []const u8) ?f64 {
        const section = self.sections.get(name) orelse return null;
        return section.last_duration_ns / 1_000_000.0; // ns to ms
    }

    /// Print all section timings
    pub fn printResults(self: *Profiler) void {
        std.debug.print("\n=== GPU Profiler Results ===\n", .{});
        var it = self.sections.iterator();
        while (it.next()) |entry| {
            const ms = entry.value_ptr.last_duration_ns / 1_000_000.0;
            std.debug.print("  {s}: {d:.3} ms\n", .{ entry.key_ptr.*, ms });
        }
        std.debug.print("\n", .{});
    }
};
