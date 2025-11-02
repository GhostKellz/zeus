const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const buffer = @import("buffer.zig");
const commands = @import("commands.zig");
const descriptor = @import("descriptor.zig");
const render_pass = @import("render_pass.zig");
const pipeline = @import("pipeline.zig");
const sampler_mod = @import("sampler.zig");
const glyph_atlas = @import("glyph_atlas.zig");
const shader = @import("shader.zig");
const loader = @import("loader.zig");
const sync = @import("sync.zig");
const system_validation = @import("system_validation.zig");
const pipeline_cache_mod = @import("pipeline_cache.zig");
const physical_device = @import("physical_device.zig");

const test_shaders = struct {
    pub const vert align(@alignOf(u32)) = [_]u8{ 0x03, 0x02, 0x23, 0x07 };
    pub const frag align(@alignOf(u32)) = [_]u8{ 0x03, 0x02, 0x23, 0x07 };
};

const text_vert_spv align(@alignOf(u32)) = if (builtin.is_test)
    test_shaders.vert
else
    @embedFile("../../shaders/text.vert.spv");
const text_frag_spv align(@alignOf(u32)) = if (builtin.is_test)
    test_shaders.frag
else
    @embedFile("../../shaders/text.frag.spv");
const text_vert_code = std.mem.bytesAsSlice(u32, text_vert_spv);
const text_frag_code = std.mem.bytesAsSlice(u32, text_frag_spv);
const shader_entry_point: [:0]const u8 = "main";

comptime {
    std.debug.assert(@intFromPtr(text_vert_spv.ptr) % @alignOf(u32) == 0);
    std.debug.assert(@intFromPtr(text_frag_spv.ptr) % @alignOf(u32) == 0);
}

const has_avx2 = builtin.cpu.arch == .x86_64 and std.Target.x86.featureSetHas(builtin.cpu.features, .avx2);
const simd_width: usize = 8;
const SimdVec = @Vector(simd_width, f32);
const no_frame_index: u32 = std.math.maxInt(u32);

const RenderError = errors.Error || error{
    InvalidFrameIndex,
    NoActiveFrame,
    InstanceOverflow,
    InvalidUniformLength,
};

pub const TextQuad = extern struct {
    position: [2]f32,
    size: [2]f32,
    atlas_rect: [4]f32,
    color: [4]f32,
};

const Instance = extern struct {
    position: [2]f32,
    size: [2]f32,
    atlas_rect: [4]f32,
    color: [4]f32,
};

const InstanceSoA = struct {
    positions: []f32,
    sizes: []f32,
    atlas_rects: []f32,
    colors: []f32,

    pub fn init(allocator: std.mem.Allocator, total_instances: usize) !InstanceSoA {
        const pos = try allocator.alloc(f32, total_instances * 2);
        errdefer allocator.free(pos);
        const size = try allocator.alloc(f32, total_instances * 2);
        errdefer allocator.free(size);
        const atlas = try allocator.alloc(f32, total_instances * 4);
        errdefer allocator.free(atlas);
        const cols = try allocator.alloc(f32, total_instances * 4);
        errdefer allocator.free(cols);
        return InstanceSoA{
            .positions = pos,
            .sizes = size,
            .atlas_rects = atlas,
            .colors = cols,
        };
    }

    pub fn deinit(self: *InstanceSoA, allocator: std.mem.Allocator) void {
        allocator.free(self.positions);
        allocator.free(self.sizes);
        allocator.free(self.atlas_rects);
        allocator.free(self.colors);
        self.positions = &[_]f32{};
        self.sizes = &[_]f32{};
        self.atlas_rects = &[_]f32{};
        self.colors = &[_]f32{};
    }

    pub fn write(self: *InstanceSoA, base: usize, quads: []const TextQuad) void {
        var i: usize = 0;
        var pos_index = base * 2;
        var size_index = base * 2;
        var atlas_index = base * 4;
        var color_index = base * 4;
        while (i < quads.len) : (i += 1) {
            const quad = quads[i];
            self.positions[pos_index] = quad.position[0];
            self.positions[pos_index + 1] = quad.position[1];
            self.sizes[size_index] = quad.size[0];
            self.sizes[size_index + 1] = quad.size[1];
            self.atlas_rects[atlas_index + 0] = quad.atlas_rect[0];
            self.atlas_rects[atlas_index + 1] = quad.atlas_rect[1];
            self.atlas_rects[atlas_index + 2] = quad.atlas_rect[2];
            self.atlas_rects[atlas_index + 3] = quad.atlas_rect[3];
            self.colors[color_index + 0] = quad.color[0];
            self.colors[color_index + 1] = quad.color[1];
            self.colors[color_index + 2] = quad.color[2];
            self.colors[color_index + 3] = quad.color[3];

            pos_index += 2;
            size_index += 2;
            atlas_index += 4;
            color_index += 4;
        }
    }

    pub fn packInto(self: *InstanceSoA, base: usize, dest: []Instance) void {
        var i: usize = 0;
        var pos_index = base * 2;
        var size_index = base * 2;
        var atlas_index = base * 4;
        var color_index = base * 4;
        while (i < dest.len) : (i += 1) {
            dest[i].position = .{ self.positions[pos_index], self.positions[pos_index + 1] };
            dest[i].size = .{ self.sizes[size_index], self.sizes[size_index + 1] };
            dest[i].atlas_rect = .{
                self.atlas_rects[atlas_index + 0],
                self.atlas_rects[atlas_index + 1],
                self.atlas_rects[atlas_index + 2],
                self.atlas_rects[atlas_index + 3],
            };
            dest[i].color = .{
                self.colors[color_index + 0],
                self.colors[color_index + 1],
                self.colors[color_index + 2],
                self.colors[color_index + 3],
            };

            pos_index += 2;
            size_index += 2;
            atlas_index += 4;
            color_index += 4;
        }
    }
};

fn identityMatrix() [16]f32 {
    return .{
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    };
}

comptime {
    if (@sizeOf(TextQuad) != @sizeOf(Instance))
        @compileError("TextQuad and Instance must remain layout-compatible");
    if (@alignOf(TextQuad) != @alignOf(Instance))
        @compileError("TextQuad and Instance must share alignment");
}

pub const FrameTelemetry = struct {
    frame_index: u32 = 0,
    glyph_count: usize = 0,
    draw_count: usize = 0,
    atlas_uploads: usize = 0,
    batch_limit: usize = 0,
    encode_cpu_ns: u64 = 0,
    transfer_cpu_ns: u64 = 0,
    submit_cpu_ns: u64 = 0,
    used_transfer_queue: bool = false,
    glyphs_per_draw: f64 = 0,
};

pub const FrameSyncInfo = struct {
    semaphore: types.VkSemaphore,
    value: u64,
    stage_mask: types.VkPipelineStageFlags,
};

const EncodeJob = struct {
    thread: ?std.Thread = null,
    context: ?*anyopaque = null,
    finalize: ?fn (std.mem.Allocator, *anyopaque) RenderError!void = null,

    fn finish(self: *EncodeJob, allocator: std.mem.Allocator) RenderError!void {
        defer self.clear();
        if (self.thread) |thread| {
            thread.join();
        }
        if (self.finalize) |callback| {
            if (self.context) |ctx| {
                return callback(allocator, ctx);
            }
        }
        return;
    }

    fn clear(self: *EncodeJob) void {
        self.thread = null;
        self.context = null;
        self.finalize = null;
    }
};

const Histogram = struct {
    pub const bucket_limits = [_]u64{
        50_000,
        100_000,
        200_000,
        400_000,
        800_000,
        1_600_000,
        3_200_000,
        6_400_000,
        12_800_000,
        25_600_000,
    };
    pub const bucket_count = bucket_limits.len + 1;

    counts: [bucket_count]u32 = [_]u32{0} ** bucket_count,
    total: u32 = 0,
    max_sample: u64 = 0,

    pub const Summary = struct {
        buckets: [bucket_count]u32,
        samples: u32,
        p50_ns: u64,
        p95_ns: u64,
        p99_ns: u64,
        max_ns: u64,
    };

    fn record(self: *Histogram, sample_ns: u64) void {
        var index: usize = bucket_limits.len;
        for (bucket_limits, 0..) |limit, idx| {
            if (sample_ns <= limit) {
                index = idx;
                break;
            }
        }
        self.counts[index] += 1;
        self.total += 1;
        if (sample_ns > self.max_sample) self.max_sample = sample_ns;
    }

    fn percentile(self: *const Histogram, percentile_value: f64) u64 {
        if (self.total == 0) return 0;
        const as_f64 = @as(f64, @floatFromInt(self.total));
        const rank_f = std.math.ceil(percentile_value * as_f64);
        var rank: u32 = @intFromFloat(rank_f);
        if (rank < 1) rank = 1;
        var cumulative: u32 = 0;
        for (self.counts, 0..) |count, idx| {
            cumulative += count;
            if (cumulative >= rank) {
                if (idx < bucket_limits.len) {
                    return bucket_limits[idx];
                }
                return self.max_sample;
            }
        }
        return self.max_sample;
    }

    fn summary(self: *const Histogram) Summary {
        return Summary{
            .buckets = self.counts,
            .samples = self.total,
            .p50_ns = self.percentile(0.50),
            .p95_ns = self.percentile(0.95),
            .p99_ns = self.percentile(0.99),
            .max_ns = self.max_sample,
        };
    }

    fn reset(self: *Histogram) void {
        self.* = .{};
    }
};

pub const ProfilerSummary = struct {
    frames: usize,
    avg_glyphs: f64,
    avg_draws: f64,
    avg_encode_ns: f64,
    avg_transfer_ns: f64,
    avg_submit_ns: f64,
    glyphs_per_draw: f64,
    max_encode_ns: u64,
    max_submit_ns: u64,
    max_draws: usize,
    encode_hist: Histogram.Summary,
    transfer_hist: Histogram.Summary,
    submit_hist: Histogram.Summary,
};

pub const ProfilerHud = struct {
    frames: usize,
    avg_glyphs: f64,
    avg_draws: f64,
    glyphs_per_draw: f64,
    encode_avg_ms: f64,
    encode_p95_ms: f64,
    transfer_avg_ms: f64,
    transfer_p95_ms: f64,
    submit_avg_ms: f64,
    submit_p95_ms: f64,
    encode_goal_met: bool,

    pub fn writeLine(self: ProfilerHud, writer: anytype) !void {
        const status = if (self.encode_goal_met) "ok" else "slow";
        try writer.print(
            "frames={d} draws={d:.2} glyphs={d:.0} g/d={d:.1} encode_avg={d:.3}ms encode_p95={d:.3}ms({s}) submit_avg={d:.3}ms submit_p95={d:.3}ms transfer_avg={d:.3}ms transfer_p95={d:.3}ms",
            .{
                self.frames,
                self.avg_draws,
                self.avg_glyphs,
                self.glyphs_per_draw,
                self.encode_avg_ms,
                self.encode_p95_ms,
                status,
                self.submit_avg_ms,
                self.submit_p95_ms,
                self.transfer_avg_ms,
                self.transfer_p95_ms,
            },
        );
    }
};

pub const ProfilerLogFn = *const fn (?*anyopaque, ProfilerSummary) void;

pub const ProfilerOptions = struct {
    log_interval: usize = 120,
    log_callback: ?ProfilerLogFn = null,
    log_context: ?*anyopaque = null,
};

pub const StatsCallback = *const fn (?*anyopaque, FrameTelemetry) void;

pub const TransferQueueOptions = struct {
    pool: *commands.CommandPool,
    queue: types.VkQueue,
    wait_stage_mask: types.VkPipelineStageFlags = types.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
    initial_timeline_value: u64 = 0,
};

const TransferContext = struct {
    base_submission: glyph_atlas.TransferSubmission,
    timeline: sync.Semaphore,
    wait_stage_mask: types.VkPipelineStageFlags,
    next_signal_value: u64,
};

fn smoothEma(current: f64, sample: f64, smoothing: f64) f64 {
    if (current == 0) return sample;
    return current + (sample - current) * smoothing;
}

const FrameState = struct {
    instance_cursor: usize = 0,
    instance_count_cached: usize = 0,
    needs_upload_flag: u8 = 0,
    draw_count: usize = 0,
    atlas_uploads: usize = 0,
    sync_wait: ?FrameSyncInfo = null,
    used_transfer_queue: bool = false,
    submit_cpu_ns: u64 = 0,
    telemetry_dirty: bool = false,
    job: EncodeJob = .{},

    fn reset(self: *FrameState, allocator: std.mem.Allocator) RenderError!void {
        try self.job.finish(allocator);
        self.job.clear();
        @atomicStore(usize, &self.instance_cursor, 0, .SeqCst);
        @atomicStore(usize, &self.instance_count_cached, 0, .SeqCst);
        @atomicStore(u8, &self.needs_upload_flag, 0, .SeqCst);
        self.draw_count = 0;
        self.atlas_uploads = 0;
        self.sync_wait = null;
        self.used_transfer_queue = false;
        self.submit_cpu_ns = 0;
        self.telemetry_dirty = false;
    }
};

pub const InitOptions = struct {
    extent: types.VkExtent2D,
    surface_format: types.VkFormat,
    memory_props: types.VkPhysicalDeviceMemoryProperties,
    frames_in_flight: u32 = 2,
    max_instances: u32 = 1024,
    atlas_extent: types.VkExtent2D = .{ .width = 1024, .height = 1024 },
    atlas_format: types.VkFormat = .R8_UNORM,
    atlas_padding: u32 = 1,
    atlas_growth_callback: ?glyph_atlas.GrowthCallback = null,
    atlas_growth_context: ?*anyopaque = null,
    rasterizer: ?glyph_atlas.RasterCallback = null,
    raster_context: ?*anyopaque = null,
    transfer_queue: ?TransferQueueOptions = null,
    stats_callback: ?StatsCallback = null,
    stats_context: ?*anyopaque = null,
    batch_target: usize = 512,
    batch_min: usize = 128,
    batch_autotune: bool = true,
    batch_autotune_goal_ns: u64 = 1_000_000,
    profiler: ?ProfilerOptions = null,
    pipeline_cache_path: ?[]const u8 = null,
    kernel_validation: bool = false,
    kernel_validation_options: system_validation.KernelValidationOptions = .{},
    lock_free_queueing: bool = true,
    parallel_encode: bool = false,
    use_soa_layout: bool = true,
};

const BatchAutoTuner = struct {
    ema_glyphs: f64 = 0,
    ema_draws: f64 = 0,
    ema_encode_ns: f64 = 0,
    ema_transfer_ns: f64 = 0,
    ema_submit_ns: f64 = 0,
    frames: usize = 0,
    cooldown: usize = 0,

    fn reset(self: *BatchAutoTuner) void {
        self.* = .{};
    }
};

const StatsAccumulator = struct {
    sum_glyphs: f64 = 0,
    sum_draws: f64 = 0,
    sum_encode_ns: f64 = 0,
    sum_transfer_ns: f64 = 0,
    sum_submit_ns: f64 = 0,
    max_encode_ns: u64 = 0,
    max_submit_ns: u64 = 0,
    max_draws: usize = 0,
    samples: usize = 0,
    encode_hist: Histogram = .{},
    transfer_hist: Histogram = .{},
    submit_hist: Histogram = .{},

    fn add(self: *StatsAccumulator, stats: FrameTelemetry) void {
        self.sum_glyphs += @as(f64, @floatFromInt(stats.glyph_count));
        self.sum_draws += @as(f64, @floatFromInt(stats.draw_count));
        self.sum_encode_ns += @as(f64, @floatFromInt(stats.encode_cpu_ns));
        self.sum_transfer_ns += @as(f64, @floatFromInt(stats.transfer_cpu_ns));
        self.sum_submit_ns += @as(f64, @floatFromInt(stats.submit_cpu_ns));
        if (stats.encode_cpu_ns > self.max_encode_ns) self.max_encode_ns = stats.encode_cpu_ns;
        if (stats.submit_cpu_ns > self.max_submit_ns) self.max_submit_ns = stats.submit_cpu_ns;
        if (stats.draw_count > self.max_draws) self.max_draws = stats.draw_count;
        self.samples += 1;
        self.encode_hist.record(stats.encode_cpu_ns);
        self.transfer_hist.record(stats.transfer_cpu_ns);
        self.submit_hist.record(stats.submit_cpu_ns);
    }

    fn summary(self: *const StatsAccumulator) ProfilerSummary {
        const frames = if (self.samples == 0) 1 else self.samples;
        const avg_draws = self.sum_draws / @as(f64, @floatFromInt(frames));
        const avg_glyphs = self.sum_glyphs / @as(f64, @floatFromInt(frames));
        const glyphs_per_draw = if (avg_draws > 0) avg_glyphs / avg_draws else avg_glyphs;
        return ProfilerSummary{
            .frames = frames,
            .avg_glyphs = avg_glyphs,
            .avg_draws = avg_draws,
            .avg_encode_ns = self.sum_encode_ns / @as(f64, @floatFromInt(frames)),
            .avg_transfer_ns = self.sum_transfer_ns / @as(f64, @floatFromInt(frames)),
            .avg_submit_ns = self.sum_submit_ns / @as(f64, @floatFromInt(frames)),
            .glyphs_per_draw = glyphs_per_draw,
            .max_encode_ns = self.max_encode_ns,
            .max_submit_ns = self.max_submit_ns,
            .max_draws = self.max_draws,
            .encode_hist = self.encode_hist.summary(),
            .transfer_hist = self.transfer_hist.summary(),
            .submit_hist = self.submit_hist.summary(),
        };
    }

    fn reset(self: *StatsAccumulator) void {
        self.* = .{};
    }
};

const Profiler = struct {
    log_interval: usize,
    log_callback: ?ProfilerLogFn,
    log_context: ?*anyopaque,
    accumulator: StatsAccumulator = .{},

    fn record(self: *Profiler, stats: FrameTelemetry) ?ProfilerSummary {
        self.accumulator.add(stats);
        if (self.accumulator.samples >= self.log_interval and self.log_interval != 0) {
            const summary = self.accumulator.summary();
            self.accumulator.reset();
            return summary;
        }
        return null;
    }
};

fn defaultProfilerLog(summary: ProfilerSummary) void {
    const avg_draws = summary.avg_draws;
    const avg_glyphs = summary.avg_glyphs;
    const glyphs_per_draw = summary.glyphs_per_draw;
    const avg_encode_ms = summary.avg_encode_ns / 1_000_000.0;
    const avg_transfer_ms = summary.avg_transfer_ns / 1_000_000.0;
    const avg_submit_ms = summary.avg_submit_ns / 1_000_000.0;
    const encode_p95_ms = @as(f64, @floatFromInt(summary.encode_hist.p95_ns)) / 1_000_000.0;
    const transfer_p95_ms = @as(f64, @floatFromInt(summary.transfer_hist.p95_ns)) / 1_000_000.0;
    const submit_p95_ms = @as(f64, @floatFromInt(summary.submit_hist.p95_ns)) / 1_000_000.0;
    std.log.info(
        "text hud: frames={d} avg_draws={d:.2} avg_glyphs={d:.0} glyphs/draw={d:.1} encode_avg={d:.3}ms encode_p95={d:.3}ms transfer_avg={d:.3}ms transfer_p95={d:.3}ms submit_avg={d:.3}ms submit_p95={d:.3}ms max_encode={d}µs max_submit={d}µs max_draws={d}",
        .{
            summary.frames,
            avg_draws,
            avg_glyphs,
            glyphs_per_draw,
            avg_encode_ms,
            encode_p95_ms,
            avg_transfer_ms,
            transfer_p95_ms,
            avg_submit_ms,
            submit_p95_ms,
            summary.max_encode_ns / 1000,
            summary.max_submit_ns / 1000,
            summary.max_draws,
        },
    );
}

pub const TextRenderer = struct {
    allocator: std.mem.Allocator,
    device: *device_mod.Device,
    memory_props: types.VkPhysicalDeviceMemoryProperties,
    extent: types.VkExtent2D,
    surface_format: types.VkFormat,
    frames_in_flight: u32,
    max_instances: u32,

    render_pass: render_pass.RenderPass,
    pipeline_layout: pipeline.PipelineLayout,
    pipeline: pipeline.GraphicsPipeline,
    pipeline_cache: ?pipeline_cache_mod.PipelineCache,

    descriptor_pool: types.VkDescriptorPool,
    descriptor_set_layout: types.VkDescriptorSetLayout,
    descriptor_cache: descriptor.DescriptorCache,

    sampler: sampler_mod.Sampler,
    glyph_atlas: glyph_atlas.GlyphAtlas,

    vertex_buffer: buffer.ManagedBuffer,
    instance_buffer: buffer.ManagedBuffer,
    staging_instance_buffer: ?buffer.ManagedBuffer,
    frame_states: []FrameState,
    instance_data: []Instance,
    soa_storage: ?InstanceSoA,
    instances_per_frame: usize,
    instance_stride: types.VkDeviceSize,
    active_frame_index: u32,
    command_buffers_dirty_flag: u8,
    use_lock_free_queue: bool,
    use_soa_layout: bool,
    parallel_encode: bool,
    rebar_enabled: bool,
    projection: [16]f32,
    frame_stats: []FrameTelemetry,
    stats_callback: ?StatsCallback,
    stats_context: ?*anyopaque,
    batch_target: usize,
    batch_min: usize,
    batch_limit: usize,
    transfer_context: ?TransferContext,
    batch_autotune_enabled: bool,
    batch_autotune_goal_ns: u64,
    batch_tuner: BatchAutoTuner,
    profiler: ?Profiler,
    last_profiler_summary: ?ProfilerSummary,
    kernel_validation: ?system_validation.KernelValidation,

    pub fn init(allocator: std.mem.Allocator, device: *device_mod.Device, options: InitOptions) errors.Error!TextRenderer {
        std.debug.assert(options.frames_in_flight > 0);
        std.debug.assert(options.max_instances > 0);

        const frame_count: usize = @intCast(options.frames_in_flight);
        const rebar_enabled = physical_device.detectReBAR(options.memory_props);
        const host_visible_required = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT;
        const host_visible_preferred = types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT | (if (rebar_enabled) types.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT else 0);
        const use_staging_upload = !rebar_enabled;

        const descriptor_bindings = [_]types.VkDescriptorSetLayoutBinding{
            .{
                .binding = 0,
                .descriptorType = .COMBINED_IMAGE_SAMPLER,
                .descriptorCount = 1,
                .stageFlags = types.VK_SHADER_STAGE_FRAGMENT_BIT,
            },
        };

        const descriptor_set_layout = try descriptor.createDescriptorSetLayout(device, descriptor_bindings[0..]);
        errdefer descriptor.destroyDescriptorSetLayout(device, descriptor_set_layout);

        const pool_sizes = [_]types.VkDescriptorPoolSize{
            .{ .descriptorType = .COMBINED_IMAGE_SAMPLER, .descriptorCount = options.frames_in_flight },
        };

        const descriptor_pool = try descriptor.createDescriptorPool(device, .{
            .max_sets = options.frames_in_flight,
            .pool_sizes = pool_sizes[0..],
            .flags = types.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
        });
        errdefer descriptor.destroyDescriptorPool(device, descriptor_pool);

        const projection_range = types.VkPushConstantRange{
            .stageFlags = types.VK_SHADER_STAGE_VERTEX_BIT,
            .offset = 0,
            .size = @intCast(16 * @sizeOf(f32)),
        };

        var pipeline_layout = try pipeline.PipelineLayout.init(device, .{ .set_layouts = &.{descriptor_set_layout}, .push_constants = &.{projection_range} });
        errdefer pipeline_layout.deinit();

        var builder = render_pass.RenderPassBuilder.init(allocator);
        defer builder.deinit();
        _ = try builder.addColorAttachment(options.surface_format, types.VkAttachmentLoadOp.LOAD);
        try builder.addDependency(types.VkSubpassDependency{
            .srcSubpass = types.VK_SUBPASS_EXTERNAL,
            .dstSubpass = 0,
            .srcStageMask = types.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .dstStageMask = types.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .srcAccessMask = 0,
            .dstAccessMask = types.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        });

        var render_pass_obj = try render_pass.RenderPass.init(device, &builder);
        errdefer render_pass_obj.deinit();

        var vert_module = try shader.ShaderModule.init(device, text_vert_code);
        defer vert_module.deinit();
        var frag_module = try shader.ShaderModule.init(device, text_frag_code);
        defer frag_module.deinit();

        var pipeline_cache_owned: ?pipeline_cache_mod.PipelineCache = null;
        if (options.pipeline_cache_path) |path| {
            pipeline_cache_owned = try pipeline_cache_mod.PipelineCache.init(allocator, device, .{ .path = path });
        }
        errdefer if (pipeline_cache_owned) |*cache| cache.deinit();

        const shader_stages = [_]types.VkPipelineShaderStageCreateInfo{
            shader.createShaderStage(vert_module.handle.?, .VERTEX_BIT, shader_entry_point.ptr),
            shader.createShaderStage(frag_module.handle.?, .FRAGMENT_BIT, shader_entry_point.ptr),
        };

        var graphics_pipeline = try pipeline.GraphicsPipeline.init(device, .{
            .layout = pipeline_layout.handle.?,
            .render_pass = render_pass_obj.handle.?,
            .shader_stages = shader_stages[0..],
            .cache = if (pipeline_cache_owned) |*cache| cache.handleRef() else null,
        });
        errdefer graphics_pipeline.deinit();

        if (pipeline_cache_owned) |*cache| {
            cache.markDirty();
        }

        var text_sampler = try sampler_mod.Sampler.init(device, .{
            .mag_filter = .LINEAR,
            .min_filter = .LINEAR,
            .mipmap_mode = .LINEAR,
            .address_mode_u = .CLAMP_TO_EDGE,
            .address_mode_v = .CLAMP_TO_EDGE,
            .address_mode_w = .CLAMP_TO_EDGE,
            .max_lod = 0.0,
            .min_lod = 0.0,
        });
        errdefer text_sampler.deinit();

        var glyph_atlas_obj = try glyph_atlas.GlyphAtlas.init(allocator, device, options.memory_props, .{
            .extent = options.atlas_extent,
            .format = options.atlas_format,
            .padding = options.atlas_padding,
            .growth_callback = options.atlas_growth_callback,
            .growth_context = options.atlas_growth_context,
            .rasterizer = options.rasterizer,
            .raster_context = options.raster_context,
        });
        errdefer glyph_atlas_obj.deinit();

        const float_size = @sizeOf(f32);
        const vertex_stride: types.VkDeviceSize = 2 * float_size;
        const quad_vertex_count: types.VkDeviceSize = 4;
        const vertex_buffer_size = vertex_stride * quad_vertex_count;

        var vertex_buffer = try buffer.createManagedBuffer(device, options.memory_props, vertex_buffer_size, types.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, .{
            .filter = .{
                .required_flags = host_visible_required,
                .preferred_flags = host_visible_preferred,
            },
        });
        errdefer vertex_buffer.deinit();

        const quad_vertices = [_]f32{ 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0 };
        try vertex_buffer.write(std.mem.sliceAsBytes(quad_vertices[0..]), 0);

        const instance_stride: types.VkDeviceSize = (2 + 2 + 4 + 4) * float_size;
        const instances_per_frame = @as(usize, @intCast(options.max_instances));
        const total_instances = std.math.mul(usize, instances_per_frame, frame_count) catch return errors.Error.FeatureNotPresent;
        const instance_buffer_size = std.math.mul(types.VkDeviceSize, instance_stride, @as(types.VkDeviceSize, @intCast(total_instances))) catch return errors.Error.FeatureNotPresent;

        const instance_usage: types.VkBufferUsageFlags = if (use_staging_upload)
            types.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | types.VK_BUFFER_USAGE_TRANSFER_DST_BIT
        else
            types.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;

        var instance_buffer = try buffer.createManagedBuffer(device, options.memory_props, instance_buffer_size, instance_usage, .{
            .filter = if (use_staging_upload)
                .{ .required_flags = types.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT }
            else
                .{
                    .required_flags = host_visible_required,
                    .preferred_flags = host_visible_preferred,
                },
        });
        errdefer instance_buffer.deinit();

        var staging_instance_buffer: ?buffer.ManagedBuffer = null;
        errdefer if (staging_instance_buffer) |*buf| buf.deinit();

        if (use_staging_upload) {
            staging_instance_buffer = try buffer.createManagedBuffer(device, options.memory_props, instance_buffer_size, types.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, .{
                .filter = .{
                    .required_flags = host_visible_required,
                    .preferred_flags = host_visible_preferred,
                },
            });
        }

        const instance_data = try allocator.alloc(Instance, total_instances);
        errdefer allocator.free(instance_data);

        const frame_states = try allocator.alloc(FrameState, frame_count);
        errdefer allocator.free(frame_states);
        std.mem.set(FrameState, frame_states, .{});

        const frame_stats = try allocator.alloc(FrameTelemetry, frame_count);
        errdefer allocator.free(frame_stats);
        std.mem.set(FrameTelemetry, frame_stats, .{});

        var soa_storage_opt: ?InstanceSoA = null;
        errdefer if (soa_storage_opt) |*soa| soa.deinit(allocator);
        if (options.use_soa_layout) {
            soa_storage_opt = try InstanceSoA.init(allocator, total_instances);
        }

        var batch_target = if (options.batch_target == 0) @as(usize, 1) else options.batch_target;
        if (batch_target > instances_per_frame) batch_target = instances_per_frame;

        var batch_min = if (options.batch_min == 0) @as(usize, 1) else options.batch_min;
        if (batch_min > batch_target) batch_min = batch_target;

        var transfer_context: ?TransferContext = null;
        if (options.transfer_queue) |transfer_opts| {
            var timeline_sem = try sync.Semaphore.create(device, .{
                .kind = .timeline,
                .initial_value = transfer_opts.initial_timeline_value,
            });
            errdefer timeline_sem.destroy();

            transfer_context = TransferContext{
                .base_submission = .{ .pool = transfer_opts.pool, .queue = transfer_opts.queue },
                .timeline = timeline_sem,
                .wait_stage_mask = transfer_opts.wait_stage_mask,
                .next_signal_value = transfer_opts.initial_timeline_value,
            };
        }

        if (glyph_atlas_obj.managedImage().view == null) return errors.Error.FeatureNotPresent;
        if (text_sampler.handle == null) return errors.Error.FeatureNotPresent;

        var kernel_validation_result: ?system_validation.KernelValidation = null;
        if (options.kernel_validation) {
            const validation = system_validation.validateKernelParameters(options.memory_props, options.kernel_validation_options);
            system_validation.logKernelValidation(validation);
            kernel_validation_result = validation;
            system_validation.logDrmHighRefresh(240);
        }

        return TextRenderer{
            .allocator = allocator,
            .device = device,
            .memory_props = options.memory_props,
            .extent = options.extent,
            .surface_format = options.surface_format,
            .frames_in_flight = options.frames_in_flight,
            .max_instances = options.max_instances,
            .render_pass = render_pass_obj,
            .pipeline_layout = pipeline_layout,
            .pipeline = graphics_pipeline,
            .pipeline_cache = pipeline_cache_owned,
            .descriptor_pool = descriptor_pool,
            .descriptor_set_layout = descriptor_set_layout,
            .descriptor_cache = descriptor.DescriptorCache.init(allocator),
            .sampler = text_sampler,
            .glyph_atlas = glyph_atlas_obj,
            .vertex_buffer = vertex_buffer,
            .instance_buffer = instance_buffer,
            .staging_instance_buffer = staging_instance_buffer,
            .frame_states = frame_states,
            .instance_data = instance_data,
            .soa_storage = soa_storage_opt,
            .instances_per_frame = instances_per_frame,
            .instance_stride = instance_stride,
            .active_frame_index = no_frame_index,
            .command_buffers_dirty_flag = 1,
            .use_lock_free_queue = options.lock_free_queueing,
            .use_soa_layout = options.use_soa_layout,
            .parallel_encode = options.parallel_encode,
            .rebar_enabled = rebar_enabled,
            .projection = identityMatrix(),
            .frame_stats = frame_stats,
            .stats_callback = options.stats_callback,
            .stats_context = options.stats_context,
            .batch_target = batch_target,
            .batch_min = batch_min,
            .batch_limit = batch_target,
            .transfer_context = transfer_context,
            .batch_autotune_enabled = options.batch_autotune,
            .batch_autotune_goal_ns = if (options.batch_autotune_goal_ns == 0) 1_000_000 else options.batch_autotune_goal_ns,
            .batch_tuner = .{},
            .profiler = if (options.profiler) |p| Profiler{
                .log_interval = if (p.log_interval == 0) 120 else p.log_interval,
                .log_callback = p.log_callback,
                .log_context = p.log_context,
            } else null,
            .last_profiler_summary = null,
            .kernel_validation = kernel_validation_result,
        };
    }

    pub fn glyphAtlas(self: *TextRenderer) *glyph_atlas.GlyphAtlas {
        return &self.glyph_atlas;
    }

    pub fn beginFrame(self: *TextRenderer, frame_index: u32) RenderError!void {
        if (frame_index >= self.frames_in_flight) return error.InvalidFrameIndex;
        const idx: usize = @intCast(frame_index);
        var state = &self.frame_states[idx];
        try state.reset(self.allocator);
        self.setActiveFrame(frame_index);
        self.markCommandBuffersDirty();
        self.frame_stats[idx] = .{ .frame_index = frame_index, .batch_limit = self.batch_limit };
    }

    pub fn setProjection(self: *TextRenderer, matrix: []const f32) RenderError!void {
        if (matrix.len != 16) return error.InvalidUniformLength;
        if (self.loadActiveFrame() == null) return error.NoActiveFrame;
        const src_bytes = std.mem.sliceAsBytes(matrix);
        const dest_bytes = std.mem.sliceAsBytes(&self.projection);
        std.mem.copy(u8, dest_bytes, src_bytes);
    }

    pub fn queueQuad(self: *TextRenderer, quad: TextQuad) RenderError!void {
        try self.queueQuads(&.{quad});
    }

    pub fn queueQuads(self: *TextRenderer, quads: []const TextQuad) RenderError!void {
        if (quads.len == 0) return;
        const frame_index = self.loadActiveFrame() orelse return error.NoActiveFrame;
        const idx: usize = @intCast(frame_index);
        var state = &self.frame_states[idx];
        const local_base = try self.reserveInstanceRange(state, quads.len);
        const frame_base = self.baseInstanceIndex(frame_index);
        const global_base = frame_base + local_base;

        if (self.use_soa_layout) {
            if (self.soa_storage) |*storage| {
                storage.write(global_base, quads);
            }
        } else {
            const dest = self.instance_data[global_base .. global_base + quads.len];
            copyInstances(dest, quads);
        }

        state.telemetry_dirty = true;
        self.frameSetNeedsUpload(state);
        self.markCommandBuffersDirty();
    }

    fn setActiveFrame(self: *TextRenderer, frame_index: u32) void {
        @atomicStore(u32, &self.active_frame_index, frame_index, .SeqCst);
    }

    fn clearActiveFrame(self: *TextRenderer) void {
        @atomicStore(u32, &self.active_frame_index, no_frame_index, .SeqCst);
    }

    fn loadActiveFrame(self: *const TextRenderer) ?u32 {
        const value = @atomicLoad(u32, &self.active_frame_index, .SeqCst);
        return if (value == no_frame_index) null else value;
    }

    fn markCommandBuffersDirty(self: *TextRenderer) void {
        @atomicStore(u8, &self.command_buffers_dirty_flag, 1, .SeqCst);
    }

    fn clearCommandBuffersDirty(self: *TextRenderer) void {
        @atomicStore(u8, &self.command_buffers_dirty_flag, 0, .SeqCst);
    }

    pub fn commandBuffersDirty(self: *const TextRenderer) bool {
        return @atomicLoad(u8, &self.command_buffers_dirty_flag, .SeqCst) == 1;
    }

    fn frameNeedsUpload(_: *const TextRenderer, state: *const FrameState) bool {
        return @atomicLoad(u8, &state.needs_upload_flag, .SeqCst) == 1;
    }

    fn frameSetNeedsUpload(_: *TextRenderer, state: *FrameState) void {
        @atomicStore(u8, &state.needs_upload_flag, 1, .SeqCst);
    }

    fn frameClearNeedsUpload(_: *TextRenderer, state: *FrameState) void {
        @atomicStore(u8, &state.needs_upload_flag, 0, .SeqCst);
    }

    fn frameInstanceCount(_: *const TextRenderer, state: *const FrameState) usize {
        return @atomicLoad(usize, &state.instance_count_cached, .SeqCst);
    }

    fn setFrameInstanceCount(_: *TextRenderer, state: *FrameState, value: usize) void {
        @atomicStore(usize, &state.instance_count_cached, value, .SeqCst);
    }

    fn reserveInstanceRange(self: *TextRenderer, state: *FrameState, count: usize) RenderError!usize {
        const previous = @atomicRmw(usize, &state.instance_cursor, .Add, count, .SeqCst);
        const new_total = previous + count;
        if (new_total > self.instances_per_frame) {
            _ = @atomicRmw(usize, &state.instance_cursor, .Sub, count, .SeqCst);
            return error.InstanceOverflow;
        }
        self.setFrameInstanceCount(state, new_total);
        return previous;
    }

    fn instanceUploadBuffer(self: *TextRenderer) *buffer.ManagedBuffer {
        if (self.staging_instance_buffer) |*buf| return buf;
        return &self.instance_buffer;
    }

    fn packInstances(self: *TextRenderer, frame_index: u32, count: usize) void {
        if (!self.use_soa_layout) return;
        if (count == 0) return;
        if (self.soa_storage) |*storage| {
            const base = self.baseInstanceIndex(frame_index);
            storage.packInto(base, self.instance_data[base .. base + count]);
        }
    }

    pub fn encode(self: *TextRenderer, cmd: types.VkCommandBuffer) RenderError!void {
        const frame_index = self.loadActiveFrame() orelse return error.NoActiveFrame;
        const idx: usize = @intCast(frame_index);
        var state = &self.frame_states[idx];
        try state.job.finish(self.allocator);
        state.job.clear();
        try self.encodeFrameInternal(frame_index, cmd);
    }

    pub fn encodeAsync(self: *TextRenderer, cmd: types.VkCommandBuffer) RenderError!void {
        if (!self.parallel_encode) return self.encode(cmd);
        const frame_index = self.loadActiveFrame() orelse return error.NoActiveFrame;
        const idx: usize = @intCast(frame_index);
        var state = &self.frame_states[idx];
        try state.job.finish(self.allocator);
        state.job = try self.spawnEncodeJob(frame_index, cmd);
    }

    fn encodeFrameInternal(self: *TextRenderer, frame_index: u32, cmd: types.VkCommandBuffer) RenderError!void {
        const idx: usize = @intCast(frame_index);
        var state = &self.frame_states[idx];

        const requires_recording = self.commandBuffersDirty() or self.frameNeedsUpload(state);
        if (!requires_recording) return;

        const encode_start = std.time.nanoTimestamp();

        const total_instances = self.frameInstanceCount(state);

        if (total_instances == 0) {
            self.clearCommandBuffersDirty();
            self.frameClearNeedsUpload(state);
            state.draw_count = 0;
            state.atlas_uploads = 0;
            state.used_transfer_queue = false;
            state.submit_cpu_ns = 0;
            state.telemetry_dirty = true;
            self.frame_stats[idx] = FrameTelemetry{
                .frame_index = frame_index,
                .glyph_count = 0,
                .draw_count = 0,
                .atlas_uploads = 0,
                .batch_limit = self.batch_limit,
                .encode_cpu_ns = 0,
                .transfer_cpu_ns = 0,
                .submit_cpu_ns = 0,
                .used_transfer_queue = false,
                .glyphs_per_draw = 0,
            };
            return;
        }

        self.packInstances(frame_index, total_instances);

        if (self.frameNeedsUpload(state)) {
            const base = self.baseInstanceIndex(frame_index);
            const slice = self.instance_data[base .. base + total_instances];
            const bytes = std.mem.sliceAsBytes(slice);
            const upload_buffer = self.instanceUploadBuffer();
            try upload_buffer.write(bytes, self.instanceBufferOffset(frame_index));
            if (self.staging_instance_buffer) |_| {
                const region = types.VkBufferCopy{
                    .srcOffset = self.instanceBufferOffset(frame_index),
                    .dstOffset = self.instanceBufferOffset(frame_index),
                    .size = @as(types.VkDeviceSize, @intCast(bytes.len)),
                };
                self.device.dispatch.cmd_copy_buffer(
                    cmd,
                    upload_buffer.buffer,
                    self.instance_buffer.buffer,
                    1,
                    &region,
                );
                const barrier = types.VkBufferMemoryBarrier{
                    .srcAccessMask = types.VK_ACCESS_TRANSFER_WRITE_BIT,
                    .dstAccessMask = types.VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT,
                    .srcQueueFamilyIndex = types.VK_QUEUE_FAMILY_IGNORED,
                    .dstQueueFamilyIndex = types.VK_QUEUE_FAMILY_IGNORED,
                    .buffer = self.instance_buffer.buffer,
                    .offset = self.instanceBufferOffset(frame_index),
                    .size = region.size,
                };
                self.device.dispatch.cmd_pipeline_barrier(
                    cmd,
                    types.VK_PIPELINE_STAGE_TRANSFER_BIT,
                    types.VK_PIPELINE_STAGE_VERTEX_INPUT_BIT,
                    0,
                    0,
                    null,
                    1,
                    &barrier,
                    0,
                    null,
                );
            }
            self.frameClearNeedsUpload(state);
        }

        var atlas_uploads: usize = 0;
        var transfer_submit_ns: u64 = 0;
        state.sync_wait = null;
        state.used_transfer_queue = false;

        if (self.transfer_context) |*transfer| {
            var submission = transfer.base_submission;
            const timeline_handle = transfer.timeline.handle orelse return errors.Error.FeatureNotPresent;
            const signal_value = transfer.next_signal_value + 1;
            submission.signal_timeline = .{ .semaphore = timeline_handle, .value = signal_value };

            const transfer_start = std.time.nanoTimestamp();
            const uploads = try self.glyph_atlas.flushUploadsTransfer(submission);
            transfer_submit_ns = @as(u64, @intCast(std.time.nanoTimestamp() - transfer_start));

            if (uploads > 0) {
                transfer.next_signal_value = signal_value;
                atlas_uploads = uploads;
                state.sync_wait = .{
                    .semaphore = timeline_handle,
                    .value = signal_value,
                    .stage_mask = transfer.wait_stage_mask,
                };
                state.used_transfer_queue = true;
            } else {
                transfer_submit_ns = 0;
            }
        }

        const atlas_image = self.glyph_atlas.managedImage();
        const atlas_view = atlas_image.view orelse return errors.Error.FeatureNotPresent;
        const sampler_handle = self.sampler.handle orelse return errors.Error.FeatureNotPresent;

        const descriptor_set = try self.descriptor_cache.getOrCreate(
            self.device,
            self.descriptor_pool,
            self.descriptor_set_layout,
            null,
            0,
            atlas_view,
            sampler_handle,
            types.VkImageLayout.SHADER_READ_ONLY_OPTIMAL,
        );

        try commands.beginRecording(self.device, cmd, .reusable, null);

        if (self.transfer_context == null) {
            atlas_uploads += try self.glyph_atlas.flushUploads(cmd);
        }

        const viewport = types.VkViewport{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(self.extent.width),
            .height = @floatFromInt(self.extent.height),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };
        self.device.dispatch.cmd_set_viewport(cmd, 0, 1, &viewport);

        const scissor = types.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.extent,
        };
        self.device.dispatch.cmd_set_scissor(cmd, 0, 1, &scissor);

        const vertex_buffers = [_]types.VkBuffer{ self.vertex_buffer.buffer, self.instance_buffer.buffer };
        const instance_offset = self.instanceBufferOffset(frame_index);
        const offsets = [_]types.VkDeviceSize{ 0, instance_offset };

        self.device.dispatch.cmd_bind_pipeline(cmd, types.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline.handle.?);
        self.device.dispatch.cmd_bind_descriptor_sets(cmd, types.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline_layout.handle.?, 0, 1, &descriptor_set, 0, null);
        const projection_bytes = std.mem.sliceAsBytes(&self.projection);
        self.device.dispatch.cmd_push_constants(
            cmd,
            self.pipeline_layout.handle.?,
            types.VK_SHADER_STAGE_VERTEX_BIT,
            0,
            @intCast(projection_bytes.len),
            @ptrCast(projection_bytes.ptr),
        );
        self.device.dispatch.cmd_bind_vertex_buffers(cmd, 0, @intCast(vertex_buffers.len), vertex_buffers[0..].ptr, offsets[0..].ptr);

        const used_batch_limit = self.batch_limit;
        var remaining = total_instances;
        var first_instance: u32 = 0;
        var draw_calls: usize = 0;
        while (remaining > 0) {
            const current_batch = @min(used_batch_limit, remaining);
            self.device.dispatch.cmd_draw(cmd, 4, @intCast(current_batch), 0, first_instance);
            remaining -= current_batch;
            first_instance += @as(u32, @intCast(current_batch));
            draw_calls += 1;
        }

        try commands.endCommandBuffer(self.device, cmd);

        self.clearCommandBuffersDirty();

        const encode_ns = @as(u64, @intCast(std.time.nanoTimestamp() - encode_start));

        state.draw_count = draw_calls;
        state.atlas_uploads = atlas_uploads;

        const telemetry = FrameTelemetry{
            .frame_index = frame_index,
            .glyph_count = total_instances,
            .draw_count = draw_calls,
            .atlas_uploads = atlas_uploads,
            .batch_limit = used_batch_limit,
            .encode_cpu_ns = encode_ns,
            .transfer_cpu_ns = transfer_submit_ns,
            .submit_cpu_ns = state.submit_cpu_ns,
            .used_transfer_queue = state.used_transfer_queue,
            .glyphs_per_draw = 0,
        };

        state.telemetry_dirty = true;
        self.frame_stats[idx] = telemetry;
    }

    const EncodeContext = struct {
        renderer: *TextRenderer,
        frame_index: u32,
        command_buffer: types.VkCommandBuffer,
        err: ?RenderError = null,
    };

    fn encodeWorker(context: *EncodeContext) void {
        context.err = context.renderer.encodeFrameInternal(context.frame_index, context.command_buffer) catch |err| err;
    }

    fn finalizeEncodeContext(
        allocator: std.mem.Allocator,
        context_ptr: *anyopaque,
    ) RenderError!void {
        const context = @as(*EncodeContext, @ptrCast(@alignCast(context_ptr)));
        defer allocator.destroy(context);
        if (context.err) |err| return err;
        return;
    }

    fn spawnEncodeJob(self: *TextRenderer, frame_index: u32, cmd: types.VkCommandBuffer) RenderError!EncodeJob {
        const context = try self.allocator.create(EncodeContext);
        context.* = .{
            .renderer = self,
            .frame_index = frame_index,
            .command_buffer = cmd,
            .err = null,
        };
        const thread = try std.Thread.spawn(.{}, encodeWorker, .{context});
        return EncodeJob{
            .thread = thread,
            .context = context,
            .finalize = finalizeEncodeContext,
        };
    }

    pub fn endFrame(self: *TextRenderer) void {
        const frame_index = self.loadActiveFrame() orelse return;
        const idx: usize = @intCast(frame_index);
        var state = &self.frame_states[idx];
        state.job.finish(self.allocator) catch |err| {
            std.debug.panic("encode job failed during endFrame: {s}", .{@errorName(err)});
        };
        state.job.clear();
        self.publishTelemetry(idx);
        self.clearActiveFrame();
    }

    pub fn recordSubmitDuration(self: *TextRenderer, frame_index: u32, submit_cpu_ns: u64) RenderError!void {
        if (frame_index >= self.frames_in_flight) return error.InvalidFrameIndex;
        const idx: usize = @intCast(frame_index);
        self.frame_stats[idx].submit_cpu_ns = submit_cpu_ns;
        var state = &self.frame_states[idx];
        state.submit_cpu_ns = submit_cpu_ns;
        state.telemetry_dirty = true;
    }

    fn publishTelemetry(self: *TextRenderer, idx: usize) void {
        if (idx >= self.frame_stats.len) return;
        var state = &self.frame_states[idx];
        if (!state.telemetry_dirty) return;

        var stats = self.frame_stats[idx];
        stats.submit_cpu_ns = state.submit_cpu_ns;
        stats.glyphs_per_draw = if (stats.draw_count == 0)
            (if (stats.glyph_count == 0) 0 else @as(f64, @floatFromInt(stats.glyph_count)))
        else
            @as(f64, @floatFromInt(stats.glyph_count)) / @as(f64, @floatFromInt(stats.draw_count));

        self.frame_stats[idx] = stats;

        if (self.stats_callback) |cb| {
            cb(self.stats_context, stats);
        }
        if (self.profiler) |*prof| {
            if (prof.record(stats)) |summary| {
                self.last_profiler_summary = summary;
                if (prof.log_callback) |cb| {
                    cb(prof.log_context, summary);
                } else {
                    defaultProfilerLog(summary);
                }
            }
        }

        self.updateAutoBatching(stats);
        self.adjustBatchLimit(stats.glyph_count);

        state.telemetry_dirty = false;
    }

    fn adjustBatchLimit(self: *TextRenderer, glyphs: usize) void {
        if (glyphs == 0) return;

        var target = self.batch_target;
        if (target == 0) target = 1;

        var min_batch = self.batch_min;
        if (min_batch == 0) min_batch = 1;

        var desired_draws = (glyphs + target - 1) / target;
        if (desired_draws == 0) desired_draws = 1;

        var recommended = (glyphs + desired_draws - 1) / desired_draws;
        if (recommended < min_batch) recommended = min_batch;
        if (recommended > self.instances_per_frame) recommended = self.instances_per_frame;

        self.batch_limit = recommended;
    }

    fn updateAutoBatching(self: *TextRenderer, stats: FrameTelemetry) void {
        if (!self.batch_autotune_enabled) return;
        if (stats.glyph_count == 0) return;

        var tuner = &self.batch_tuner;
        const smoothing: f64 = 0.2;

        const glyphs = @as(f64, @floatFromInt(stats.glyph_count));
        const draws = if (stats.draw_count == 0) 1.0 else @as(f64, @floatFromInt(stats.draw_count));
        const encode_ns = @as(f64, @floatFromInt(stats.encode_cpu_ns));
        const transfer_ns = @as(f64, @floatFromInt(stats.transfer_cpu_ns));
        const submit_ns = @as(f64, @floatFromInt(stats.submit_cpu_ns));

        tuner.ema_glyphs = smoothEma(tuner.ema_glyphs, glyphs, smoothing);
        tuner.ema_draws = smoothEma(tuner.ema_draws, draws, smoothing);
        tuner.ema_encode_ns = smoothEma(tuner.ema_encode_ns, encode_ns, smoothing);
        tuner.ema_transfer_ns = smoothEma(tuner.ema_transfer_ns, transfer_ns, smoothing);
        tuner.ema_submit_ns = smoothEma(tuner.ema_submit_ns, submit_ns, smoothing);
        tuner.frames += 1;

        if (tuner.cooldown > 0) {
            tuner.cooldown -= 1;
        }

        const avg_draws = if (tuner.ema_draws == 0) draws else tuner.ema_draws;
        const avg_glyphs = if (tuner.ema_glyphs == 0) glyphs else tuner.ema_glyphs;
        const avg_encode_ns = if (tuner.ema_encode_ns == 0) encode_ns else tuner.ema_encode_ns;
        const avg_submit_ns = if (tuner.ema_submit_ns == 0) submit_ns else tuner.ema_submit_ns;
        const glyphs_per_draw = if (avg_draws > 0.01) avg_glyphs / avg_draws else avg_glyphs;

        var changed = false;
        const goal_ns = @as(f64, @floatFromInt(self.batch_autotune_goal_ns));
        const workload_ns = std.math.max(avg_encode_ns, avg_submit_ns);

        if (avg_draws > 1.05 or workload_ns > goal_ns) {
            var needed_for_single_draw = @as(usize, @intFromFloat(std.math.ceil(avg_glyphs)));
            if (needed_for_single_draw < self.batch_min) needed_for_single_draw = self.batch_min;
            if (needed_for_single_draw > self.instances_per_frame) needed_for_single_draw = self.instances_per_frame;

            var stepped_up = self.batch_target + (self.batch_target / 2);
            if (stepped_up < needed_for_single_draw) stepped_up = needed_for_single_draw;
            if (stepped_up > self.instances_per_frame) stepped_up = self.instances_per_frame;
            if (stepped_up > self.batch_target) {
                self.batch_target = stepped_up;
                changed = true;
            }
        } else if (tuner.cooldown == 0 and self.batch_target > self.batch_min) {
            const under_utilized = glyphs_per_draw < @as(f64, @floatFromInt(self.batch_target)) * 0.55;
            const encode_cheap = avg_encode_ns < goal_ns * 0.5;
            const submit_cheap = avg_submit_ns < goal_ns * 0.5;
            if (under_utilized and encode_cheap and submit_cheap) {
                const reduced = std.math.max(self.batch_min, self.batch_target / 2);
                if (reduced < self.batch_target) {
                    self.batch_target = reduced;
                    changed = true;
                }
            }
        }

        if (changed) {
            tuner.cooldown = std.math.min(16, @intCast(4 + tuner.frames / 4));
        }

        if (self.batch_target < self.batch_min) self.batch_target = self.batch_min;
        if (self.batch_target > self.instances_per_frame) self.batch_target = self.instances_per_frame;
    }

    pub fn releaseAtlasUploads(self: *TextRenderer) void {
        self.glyph_atlas.releaseUploads();
    }

    pub fn frameStats(self: *const TextRenderer, frame_index: u32) RenderError!FrameTelemetry {
        if (frame_index >= self.frames_in_flight) return error.InvalidFrameIndex;
        const idx: usize = @intCast(frame_index);
        return self.frame_stats[idx];
    }

    pub fn pendingInstanceCount(self: *const TextRenderer, frame_index: u32) RenderError!usize {
        if (frame_index >= self.frames_in_flight) return error.InvalidFrameIndex;
        const idx: usize = @intCast(frame_index);
        return self.frameInstanceCount(&self.frame_states[idx]);
    }

    pub fn frameSyncInfo(self: *const TextRenderer, frame_index: u32) RenderError!?FrameSyncInfo {
        if (frame_index >= self.frames_in_flight) return error.InvalidFrameIndex;
        const idx: usize = @intCast(frame_index);
        return self.frame_states[idx].sync_wait;
    }

    pub fn profilerSummary(self: *const TextRenderer) ?ProfilerSummary {
        return self.last_profiler_summary;
    }

    pub fn profilerHud(self: *const TextRenderer, target_encode_ns: u64) ?ProfilerHud {
        const summary = self.profilerSummary() orelse return null;
        const encode_p95_ns = summary.encode_hist.p95_ns;
        const submit_p95_ns = summary.submit_hist.p95_ns;
        const worst_p95_ns = std.math.max(encode_p95_ns, submit_p95_ns);
        return ProfilerHud{
            .frames = summary.frames,
            .avg_glyphs = summary.avg_glyphs,
            .avg_draws = summary.avg_draws,
            .glyphs_per_draw = summary.glyphs_per_draw,
            .encode_avg_ms = summary.avg_encode_ns / 1_000_000.0,
            .encode_p95_ms = @as(f64, @floatFromInt(encode_p95_ns)) / 1_000_000.0,
            .transfer_avg_ms = summary.avg_transfer_ns / 1_000_000.0,
            .transfer_p95_ms = @as(f64, @floatFromInt(summary.transfer_hist.p95_ns)) / 1_000_000.0,
            .submit_avg_ms = summary.avg_submit_ns / 1_000_000.0,
            .submit_p95_ms = @as(f64, @floatFromInt(submit_p95_ns)) / 1_000_000.0,
            .encode_goal_met = if (target_encode_ns == 0) true else worst_p95_ns <= target_encode_ns,
        };
    }

    pub fn kernelValidation(self: *const TextRenderer) ?system_validation.KernelValidation {
        return self.kernel_validation;
    }

    pub fn persistPipelineCache(self: *TextRenderer) errors.Error!void {
        if (self.pipeline_cache) |*cache| {
            try cache.persist();
        }
    }

    pub fn quadFromGlyph(info: glyph_atlas.GlyphInfo, origin: [2]f32, color: [4]f32) TextQuad {
        const uv_width = info.uv_max[0] - info.uv_min[0];
        const uv_height = info.uv_max[1] - info.uv_min[1];
        return TextQuad{
            .position = .{
                origin[0] + @as(f32, @floatFromInt(info.bearing.x)),
                origin[1] - @as(f32, @floatFromInt(info.bearing.y)),
            },
            .size = .{
                @as(f32, @floatFromInt(info.rect.size.width)),
                @as(f32, @floatFromInt(info.rect.size.height)),
            },
            .atlas_rect = .{ info.uv_min[0], info.uv_min[1], uv_width, uv_height },
            .color = color,
        };
    }

    fn baseInstanceIndex(self: *const TextRenderer, frame_index: u32) usize {
        return self.instances_per_frame * @as(usize, @intCast(frame_index));
    }

    fn instanceBufferOffset(self: *const TextRenderer, frame_index: u32) types.VkDeviceSize {
        const base = self.baseInstanceIndex(frame_index);
        return self.instance_stride * @as(types.VkDeviceSize, @intCast(base));
    }

    pub fn deinit(self: *TextRenderer) void {
        if (self.transfer_context) |*transfer| {
            transfer.timeline.destroy();
            self.transfer_context = null;
        }

        if (self.pipeline_cache) |*cache| {
            if (cache.persist()) |_| {} else |err| {
                std.log.warn("failed to persist pipeline cache: {s}", .{@errorName(err)});
            }
            cache.deinit();
            self.pipeline_cache = null;
        }

        if (self.instance_data.len > 0) {
            self.allocator.free(self.instance_data);
            self.instance_data = &.{};
        }

        if (self.frame_states.len > 0) {
            for (self.frame_states) |*state| {
                state.job.finish(self.allocator) catch |err| {
                    std.log.warn("encode job cleanup error: {s}", .{@errorName(err)});
                };
            }
            self.allocator.free(self.frame_states);
            self.frame_states = &.{};
        }

        if (self.frame_stats.len > 0) {
            self.allocator.free(self.frame_stats);
            self.frame_stats = &.{};
        }

        if (self.soa_storage) |*storage| {
            storage.deinit(self.allocator);
            self.soa_storage = null;
        }

        if (self.staging_instance_buffer) |*buf| {
            buf.deinit();
            self.staging_instance_buffer = null;
        }

        self.clearActiveFrame();

        self.instance_buffer.deinit();
        self.vertex_buffer.deinit();

        self.glyph_atlas.deinit();
        self.sampler.deinit();

        self.descriptor_cache.deinit();
        descriptor.destroyDescriptorPool(self.device, self.descriptor_pool);
        descriptor.destroyDescriptorSetLayout(self.device, self.descriptor_set_layout);

        self.pipeline.deinit();
        self.pipeline_layout.deinit();
        self.render_pass.deinit();
    }
};

fn copyInstances(dest: []Instance, quads: []const TextQuad) void {
    std.debug.assert(dest.len == quads.len);
    if (dest.len == 0) return;
    if (has_avx2) {
        copyInstancesAvx2(dest, quads);
    } else {
        copyInstancesScalar(dest, quads);
    }
}

fn copyInstancesScalar(dest: []Instance, quads: []const TextQuad) void {
    const src_ptr = @as([*]const Instance, @ptrCast(quads.ptr));
    const src_slice = src_ptr[0..quads.len];
    std.mem.copy(Instance, dest, src_slice);
}

fn copyInstancesAvx2(dest: []Instance, quads: []const TextQuad) void {
    const floats_per_instance: usize = @divExact(@sizeOf(Instance), @sizeOf(f32));
    const total_floats: usize = floats_per_instance * quads.len;
    const src_ptr = @as([*]const f32, @ptrCast(quads.ptr));
    const dst_ptr = @as([*]f32, @ptrCast(dest.ptr));

    var i: usize = 0;
    while (i + simd_width <= total_floats) : (i += simd_width) {
        const src_chunk_ptr = @as(*const [simd_width]f32, @ptrCast(src_ptr + i));
        const vec: SimdVec = @bitCast(src_chunk_ptr.*);
        const dst_chunk_ptr = @as(*[simd_width]f32, @ptrCast(dst_ptr + i));
        dst_chunk_ptr.* = @bitCast(vec);
    }

    while (i < total_floats) : (i += 1) {
        dst_ptr[i] = src_ptr[i];
    }
}

const TestCapture = struct {
    pub var descriptor_layout_calls: usize = 0;
    pub var descriptor_pool_calls: usize = 0;
    pub var descriptor_set_count: usize = 0;
    pub var pipeline_layout_calls: usize = 0;
    pub var render_pass_create_calls: usize = 0;
    pub var shader_module_create_calls: usize = 0;
    pub var pipeline_create_calls: usize = 0;
    pub var pipeline_stage_count: u32 = 0;
    pub var sampler_create_calls: usize = 0;
    pub var image_create_calls: usize = 0;
    pub var image_view_create_calls: usize = 0;
    pub var buffer_create_calls: usize = 0;
    pub var framebuffer_create_calls: usize = 0;
    pub var update_descriptor_calls: usize = 0;
    pub var free_descriptor_calls: usize = 0;
    pub var destroy_pool_calls: usize = 0;
    pub var destroy_layout_calls: usize = 0;
    pub var destroy_pipeline_calls: usize = 0;
    pub var destroy_pipeline_layout_calls: usize = 0;
    pub var destroy_render_pass_calls: usize = 0;
    pub var destroy_sampler_calls: usize = 0;
    pub var destroy_image_calls: usize = 0;
    pub var destroy_image_view_calls: usize = 0;
    pub var destroy_buffer_calls: usize = 0;
    pub var destroy_framebuffer_calls: usize = 0;
    pub var descriptor_write_count: usize = 0;
    pub var last_buffer_size: types.VkDeviceSize = 0;
    pub var last_image_extent: types.VkExtent3D = .{ .width = 0, .height = 0, .depth = 0 };
    pub var bind_pipeline_calls: usize = 0;
    pub var bind_descriptor_calls: usize = 0;
    pub var bind_vertex_calls: usize = 0;
    pub var draw_calls: usize = 0;
    pub var set_viewport_calls: usize = 0;
    pub var set_scissor_calls: usize = 0;
    pub var begin_render_pass_calls: usize = 0;
    pub var end_render_pass_calls: usize = 0;
    pub var last_clear_value_count: u32 = 0;
    pub var last_render_area: ?types.VkRect2D = null;
    pub var last_subpass_contents: types.VkSubpassContents = types.VK_SUBPASS_CONTENTS_INLINE;
    pub var last_render_pass: ?types.VkRenderPass = null;
    pub var last_framebuffer: ?types.VkFramebuffer = null;
    pub var begin_command_calls: usize = 0;
    pub var end_command_calls: usize = 0;
    pub var push_constant_calls: usize = 0;
    pub var last_push_size: u32 = 0;
    pub var last_begin_flags: ?types.VkCommandBufferUsageFlags = null;
    pub var last_draw_vertex_count: u32 = 0;
    pub var last_draw_instance_count: u32 = 0;
    pub var last_instance_offset: types.VkDeviceSize = 0;
    pub var last_descriptor_set: ?types.VkDescriptorSet = null;
    pub var last_pipeline: ?types.VkPipeline = null;
    pub var last_viewport: ?types.VkViewport = null;
    pub var last_scissor: ?types.VkRect2D = null;

    pub fn reset() void {
        descriptor_layout_calls = 0;
        descriptor_pool_calls = 0;
        descriptor_set_count = 0;
        pipeline_layout_calls = 0;
        render_pass_create_calls = 0;
        shader_module_create_calls = 0;
        pipeline_create_calls = 0;
        pipeline_stage_count = 0;
        sampler_create_calls = 0;
        image_create_calls = 0;
        image_view_create_calls = 0;
        buffer_create_calls = 0;
        framebuffer_create_calls = 0;
        update_descriptor_calls = 0;
        free_descriptor_calls = 0;
        destroy_pool_calls = 0;
        destroy_layout_calls = 0;
        destroy_pipeline_calls = 0;
        destroy_pipeline_layout_calls = 0;
        destroy_render_pass_calls = 0;
        destroy_sampler_calls = 0;
        destroy_image_calls = 0;
        destroy_image_view_calls = 0;
        destroy_buffer_calls = 0;
        destroy_framebuffer_calls = 0;
        descriptor_write_count = 0;
        last_buffer_size = 0;
        last_image_extent = .{ .width = 0, .height = 0, .depth = 0 };
        test_next_handle = 0x2000;
        bind_pipeline_calls = 0;
        bind_descriptor_calls = 0;
        bind_vertex_calls = 0;
        draw_calls = 0;
        set_viewport_calls = 0;
        set_scissor_calls = 0;
        begin_render_pass_calls = 0;
        end_render_pass_calls = 0;
        last_clear_value_count = 0;
        last_render_area = null;
        last_subpass_contents = types.VK_SUBPASS_CONTENTS_INLINE;
        last_render_pass = null;
        last_framebuffer = null;
        begin_command_calls = 0;
        end_command_calls = 0;
        push_constant_calls = 0;
        last_push_size = 0;
        last_begin_flags = null;
        last_draw_vertex_count = 0;
        last_draw_instance_count = 0;
        last_instance_offset = 0;
        last_descriptor_set = null;
        last_pipeline = null;
        last_viewport = null;
        last_scissor = null;
    }
};

var test_next_handle: usize = 0x2000;
var test_mapped_storage: [8192]u8 = undefined;

fn makeHandle(comptime T: type) T {
    test_next_handle += 0x10;
    return @as(T, @ptrFromInt(test_next_handle));
}

fn stubCreateDescriptorSetLayout(_: types.VkDevice, info: *const types.VkDescriptorSetLayoutCreateInfo, _: ?*const types.VkAllocationCallbacks, layout: *types.VkDescriptorSetLayout) callconv(.c) types.VkResult {
    TestCapture.descriptor_layout_calls += 1;
    std.debug.assert(info.bindingCount == 1);
    layout.* = makeHandle(types.VkDescriptorSetLayout);
    return .SUCCESS;
}

fn stubDestroyDescriptorSetLayout(_: types.VkDevice, _: types.VkDescriptorSetLayout, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {
    TestCapture.destroy_layout_calls += 1;
}

fn stubCreateDescriptorPool(_: types.VkDevice, info: *const types.VkDescriptorPoolCreateInfo, _: ?*const types.VkAllocationCallbacks, pool: *types.VkDescriptorPool) callconv(.c) types.VkResult {
    TestCapture.descriptor_pool_calls += 1;
    std.debug.assert(info.maxSets > 0);
    pool.* = makeHandle(types.VkDescriptorPool);
    return .SUCCESS;
}

fn stubDestroyDescriptorPool(_: types.VkDevice, _: types.VkDescriptorPool, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {
    TestCapture.destroy_pool_calls += 1;
}

fn stubAllocateDescriptorSets(_: types.VkDevice, info: *const types.VkDescriptorSetAllocateInfo, sets: [*]types.VkDescriptorSet) callconv(.c) types.VkResult {
    TestCapture.descriptor_set_count += info.descriptorSetCount;
    var i: usize = 0;
    while (i < info.descriptorSetCount) : (i += 1) {
        sets[i] = makeHandle(types.VkDescriptorSet);
    }
    return .SUCCESS;
}

fn stubFreeDescriptorSets(_: types.VkDevice, _: types.VkDescriptorPool, count: u32, _: [*]const types.VkDescriptorSet) callconv(.c) types.VkResult {
    if (count > 0) TestCapture.free_descriptor_calls += 1;
    return .SUCCESS;
}

fn stubUpdateDescriptorSets(_: types.VkDevice, write_count: u32, writes: ?[*]const types.VkWriteDescriptorSet, _: u32, _: ?[*]const types.VkCopyDescriptorSet) callconv(.c) void {
    if (writes) |ptr| {
        for (ptr[0..write_count]) |_| {
            TestCapture.update_descriptor_calls += 1;
        }
        TestCapture.descriptor_write_count += write_count;
    }
}

fn stubCreatePipelineLayout(_: types.VkDevice, _: *const types.VkPipelineLayoutCreateInfo, _: ?*const types.VkAllocationCallbacks, layout: *types.VkPipelineLayout) callconv(.c) types.VkResult {
    TestCapture.pipeline_layout_calls += 1;
    layout.* = makeHandle(types.VkPipelineLayout);
    return .SUCCESS;
}

fn stubDestroyPipelineLayout(_: types.VkDevice, _: types.VkPipelineLayout, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {
    TestCapture.destroy_pipeline_layout_calls += 1;
}

fn stubCreateRenderPass(_: types.VkDevice, info: *const types.VkRenderPassCreateInfo, _: ?*const types.VkAllocationCallbacks, render_pass_handle: *types.VkRenderPass) callconv(.c) types.VkResult {
    TestCapture.render_pass_create_calls += 1;
    std.debug.assert(info.attachmentCount == 1);
    render_pass_handle.* = makeHandle(types.VkRenderPass);
    return .SUCCESS;
}

fn stubDestroyRenderPass(_: types.VkDevice, _: types.VkRenderPass, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {
    TestCapture.destroy_render_pass_calls += 1;
}

fn stubCreatePipelineCache(_: types.VkDevice, _: *const types.VkPipelineCacheCreateInfo, _: ?*const types.VkAllocationCallbacks, cache: *types.VkPipelineCache) callconv(.c) types.VkResult {
    cache.* = makeHandle(types.VkPipelineCache);
    return .SUCCESS;
}

fn stubDestroyPipelineCache(_: types.VkDevice, _: types.VkPipelineCache, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {}

fn stubGetPipelineCacheData(_: types.VkDevice, _: types.VkPipelineCache, size: *usize, data: ?*anyopaque) callconv(.c) types.VkResult {
    if (data == null) {
        size.* = 128;
        return .SUCCESS;
    }
    const out_len = size.*;
    if (out_len == 0) return .SUCCESS;
    const bytes = @as([*]u8, @ptrCast(data.?))[0..out_len];
    std.mem.set(u8, bytes, 0xAB);
    return .SUCCESS;
}

fn stubCreateShaderModule(_: types.VkDevice, info: *const types.VkShaderModuleCreateInfo, _: ?*const types.VkAllocationCallbacks, module: *types.VkShaderModule) callconv(.c) types.VkResult {
    TestCapture.shader_module_create_calls += 1;
    std.debug.assert(info.codeSize > 0);
    module.* = makeHandle(types.VkShaderModule);
    return .SUCCESS;
}

fn stubDestroyShaderModule(_: types.VkDevice, _: types.VkShaderModule, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {}

fn stubCreateGraphicsPipelines(_: types.VkDevice, _: types.VkPipelineCache, count: u32, infos: [*]const types.VkGraphicsPipelineCreateInfo, _: ?*const types.VkAllocationCallbacks, pipelines: [*]types.VkPipeline) callconv(.c) types.VkResult {
    TestCapture.pipeline_create_calls += 1;
    std.debug.assert(count == 1);
    TestCapture.pipeline_stage_count = infos[0].stageCount;
    pipelines[0] = makeHandle(types.VkPipeline);
    return .SUCCESS;
}

fn stubDestroyPipeline(_: types.VkDevice, _: types.VkPipeline, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {
    TestCapture.destroy_pipeline_calls += 1;
}

fn stubCreateSampler(_: types.VkDevice, _: *const types.VkSamplerCreateInfo, _: ?*const types.VkAllocationCallbacks, sampler_handle: *types.VkSampler) callconv(.c) types.VkResult {
    TestCapture.sampler_create_calls += 1;
    sampler_handle.* = makeHandle(types.VkSampler);
    return .SUCCESS;
}

fn stubDestroySampler(_: types.VkDevice, _: types.VkSampler, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {
    TestCapture.destroy_sampler_calls += 1;
}

fn stubCreateImage(_: types.VkDevice, info: *const types.VkImageCreateInfo, _: ?*const types.VkAllocationCallbacks, image_handle: *types.VkImage) callconv(.c) types.VkResult {
    TestCapture.image_create_calls += 1;
    TestCapture.last_image_extent = info.extent;
    image_handle.* = makeHandle(types.VkImage);
    return .SUCCESS;
}

fn stubDestroyImage(_: types.VkDevice, _: types.VkImage, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {
    TestCapture.destroy_image_calls += 1;
}

fn stubGetImageMemoryRequirements(_: types.VkDevice, _: types.VkImage, requirements: *types.VkMemoryRequirements) callconv(.c) void {
    requirements.* = types.VkMemoryRequirements{
        .size = 4096,
        .alignment = 256,
        .memoryTypeBits = 0b11,
    };
}

fn stubBindImageMemory(_: types.VkDevice, _: types.VkImage, _: types.VkDeviceMemory, _: types.VkDeviceSize) callconv(.c) types.VkResult {
    return .SUCCESS;
}

fn stubCreateImageView(_: types.VkDevice, _: *const types.VkImageViewCreateInfo, _: ?*const types.VkAllocationCallbacks, view: *types.VkImageView) callconv(.c) types.VkResult {
    TestCapture.image_view_create_calls += 1;
    view.* = makeHandle(types.VkImageView);
    return .SUCCESS;
}

fn stubDestroyImageView(_: types.VkDevice, _: types.VkImageView, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {
    TestCapture.destroy_image_view_calls += 1;
}

fn stubCreateFramebuffer(_: types.VkDevice, _: *const types.VkFramebufferCreateInfo, _: ?*const types.VkAllocationCallbacks, framebuffer: *types.VkFramebuffer) callconv(.c) types.VkResult {
    TestCapture.framebuffer_create_calls += 1;
    framebuffer.* = makeHandle(types.VkFramebuffer);
    return .SUCCESS;
}

fn stubDestroyFramebuffer(_: types.VkDevice, _: types.VkFramebuffer, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {
    TestCapture.destroy_framebuffer_calls += 1;
}

fn stubCreateBuffer(_: types.VkDevice, info: *const types.VkBufferCreateInfo, _: ?*const types.VkAllocationCallbacks, buffer_handle: *types.VkBuffer) callconv(.c) types.VkResult {
    TestCapture.buffer_create_calls += 1;
    TestCapture.last_buffer_size = info.size;
    buffer_handle.* = makeHandle(types.VkBuffer);
    return .SUCCESS;
}

fn stubDestroyBuffer(_: types.VkDevice, _: types.VkBuffer, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {
    TestCapture.destroy_buffer_calls += 1;
}

fn stubGetBufferMemoryRequirements(_: types.VkDevice, _: types.VkBuffer, requirements: *types.VkMemoryRequirements) callconv(.c) void {
    requirements.* = types.VkMemoryRequirements{
        .size = TestCapture.last_buffer_size,
        .alignment = 256,
        .memoryTypeBits = 0b11,
    };
}

fn stubBindBufferMemory(_: types.VkDevice, _: types.VkBuffer, _: types.VkDeviceMemory, _: types.VkDeviceSize) callconv(.c) types.VkResult {
    return .SUCCESS;
}

fn stubAllocateMemory(_: types.VkDevice, info: *const types.VkMemoryAllocateInfo, _: ?*const types.VkAllocationCallbacks, memory: *types.VkDeviceMemory) callconv(.c) types.VkResult {
    memory.* = @as(types.VkDeviceMemory, @ptrFromInt(info.allocationSize));
    return .SUCCESS;
}

fn stubFreeMemory(_: types.VkDevice, _: types.VkDeviceMemory, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {}

fn stubMapMemory(_: types.VkDevice, _: types.VkDeviceMemory, _: types.VkDeviceSize, _: types.VkDeviceSize, _: types.VkMemoryMapFlags, data: *?*anyopaque) callconv(.c) types.VkResult {
    data.* = @as(*anyopaque, @ptrCast(test_mapped_storage[0..].ptr));
    return .SUCCESS;
}

fn stubUnmapMemory(_: types.VkDevice, _: types.VkDeviceMemory) callconv(.c) void {}

fn stubCmdBindPipeline(_: types.VkCommandBuffer, bind_point: types.VkPipelineBindPoint, pipeline_handle: types.VkPipeline) callconv(.c) void {
    std.debug.assert(bind_point == types.VK_PIPELINE_BIND_POINT_GRAPHICS);
    TestCapture.bind_pipeline_calls += 1;
    TestCapture.last_pipeline = pipeline_handle;
}

fn stubCmdBindDescriptorSets(_: types.VkCommandBuffer, bind_point: types.VkPipelineBindPoint, _: types.VkPipelineLayout, first_set: u32, set_count: u32, descriptor_sets: *const types.VkDescriptorSet, dynamic_offset_count: u32, dynamic_offsets: ?[*]const u32) callconv(.c) void {
    _ = dynamic_offsets;
    std.debug.assert(bind_point == types.VK_PIPELINE_BIND_POINT_GRAPHICS);
    std.debug.assert(first_set == 0);
    std.debug.assert(set_count == 1);
    std.debug.assert(dynamic_offset_count == 0);
    TestCapture.bind_descriptor_calls += 1;
    TestCapture.last_descriptor_set = descriptor_sets[0];
}

fn stubCmdBindVertexBuffers(_: types.VkCommandBuffer, first_binding: u32, binding_count: u32, buffers: *const types.VkBuffer, offsets: *const types.VkDeviceSize) callconv(.c) void {
    std.debug.assert(first_binding == 0);
    std.debug.assert(binding_count == 2);
    _ = buffers;
    TestCapture.bind_vertex_calls += 1;
    TestCapture.last_instance_offset = offsets[1];
}

fn stubCmdDraw(_: types.VkCommandBuffer, vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) callconv(.c) void {
    std.debug.assert(first_vertex == 0);
    std.debug.assert(first_instance == 0);
    TestCapture.draw_calls += 1;
    TestCapture.last_draw_vertex_count = vertex_count;
    TestCapture.last_draw_instance_count = instance_count;
}

fn stubCmdSetViewport(_: types.VkCommandBuffer, first_viewport: u32, viewport_count: u32, viewports: *const types.VkViewport) callconv(.c) void {
    std.debug.assert(first_viewport == 0);
    std.debug.assert(viewport_count == 1);
    TestCapture.set_viewport_calls += 1;
    TestCapture.last_viewport = viewports[0];
}

fn stubCmdSetScissor(_: types.VkCommandBuffer, first_scissor: u32, scissor_count: u32, scissors: *const types.VkRect2D) callconv(.c) void {
    std.debug.assert(first_scissor == 0);
    std.debug.assert(scissor_count == 1);
    TestCapture.set_scissor_calls += 1;
    TestCapture.last_scissor = scissors[0];
}

fn stubCmdBeginRenderPass(_: types.VkCommandBuffer, info: *const types.VkRenderPassBeginInfo, contents: types.VkSubpassContents) callconv(.c) void {
    TestCapture.begin_render_pass_calls += 1;
    TestCapture.last_clear_value_count = info.clearValueCount;
    TestCapture.last_render_area = info.renderArea;
    TestCapture.last_subpass_contents = contents;
    TestCapture.last_render_pass = info.renderPass;
    TestCapture.last_framebuffer = info.framebuffer;
}

fn stubCmdEndRenderPass(_: types.VkCommandBuffer) callconv(.c) void {
    TestCapture.end_render_pass_calls += 1;
}

fn stubCmdPushConstants(_: types.VkCommandBuffer, _: types.VkPipelineLayout, stage_flags: types.VkShaderStageFlags, offset: u32, size: u32, _: ?*const anyopaque) callconv(.c) void {
    TestCapture.push_constant_calls += 1;
    TestCapture.last_push_size = size;
    std.debug.assert(stage_flags == types.VK_SHADER_STAGE_VERTEX_BIT);
    std.debug.assert(offset == 0);
}

fn stubBeginCommandBuffer(_: types.VkCommandBuffer, info: *const types.VkCommandBufferBeginInfo) callconv(.c) types.VkResult {
    TestCapture.begin_command_calls += 1;
    TestCapture.last_begin_flags = info.flags;
    return .SUCCESS;
}

fn stubEndCommandBuffer(_: types.VkCommandBuffer) callconv(.c) types.VkResult {
    TestCapture.end_command_calls += 1;
    return .SUCCESS;
}

fn setupTestDispatch(device: *device_mod.Device) void {
    device.dispatch.create_descriptor_set_layout = stubCreateDescriptorSetLayout;
    device.dispatch.destroy_descriptor_set_layout = stubDestroyDescriptorSetLayout;
    device.dispatch.create_descriptor_pool = stubCreateDescriptorPool;
    device.dispatch.destroy_descriptor_pool = stubDestroyDescriptorPool;
    device.dispatch.allocate_descriptor_sets = stubAllocateDescriptorSets;
    device.dispatch.free_descriptor_sets = stubFreeDescriptorSets;
    device.dispatch.update_descriptor_sets = stubUpdateDescriptorSets;
    device.dispatch.create_pipeline_layout = stubCreatePipelineLayout;
    device.dispatch.destroy_pipeline_layout = stubDestroyPipelineLayout;
    device.dispatch.create_render_pass = stubCreateRenderPass;
    device.dispatch.destroy_render_pass = stubDestroyRenderPass;
    device.dispatch.create_pipeline_cache = stubCreatePipelineCache;
    device.dispatch.destroy_pipeline_cache = stubDestroyPipelineCache;
    device.dispatch.get_pipeline_cache_data = stubGetPipelineCacheData;
    device.dispatch.create_shader_module = stubCreateShaderModule;
    device.dispatch.destroy_shader_module = stubDestroyShaderModule;
    device.dispatch.create_graphics_pipelines = stubCreateGraphicsPipelines;
    device.dispatch.destroy_pipeline = stubDestroyPipeline;
    device.dispatch.create_sampler = stubCreateSampler;
    device.dispatch.destroy_sampler = stubDestroySampler;
    device.dispatch.create_image = stubCreateImage;
    device.dispatch.destroy_image = stubDestroyImage;
    device.dispatch.get_image_memory_requirements = stubGetImageMemoryRequirements;
    device.dispatch.bind_image_memory = stubBindImageMemory;
    device.dispatch.create_image_view = stubCreateImageView;
    device.dispatch.destroy_image_view = stubDestroyImageView;
    device.dispatch.create_framebuffer = stubCreateFramebuffer;
    device.dispatch.destroy_framebuffer = stubDestroyFramebuffer;
    device.dispatch.create_buffer = stubCreateBuffer;
    device.dispatch.destroy_buffer = stubDestroyBuffer;
    device.dispatch.get_buffer_memory_requirements = stubGetBufferMemoryRequirements;
    device.dispatch.bind_buffer_memory = stubBindBufferMemory;
    device.dispatch.allocate_memory = stubAllocateMemory;
    device.dispatch.free_memory = stubFreeMemory;
    device.dispatch.map_memory = stubMapMemory;
    device.dispatch.unmap_memory = stubUnmapMemory;
    device.dispatch.cmd_bind_pipeline = stubCmdBindPipeline;
    device.dispatch.cmd_bind_descriptor_sets = stubCmdBindDescriptorSets;
    device.dispatch.cmd_bind_vertex_buffers = stubCmdBindVertexBuffers;
    device.dispatch.cmd_push_constants = stubCmdPushConstants;
    device.dispatch.cmd_draw = stubCmdDraw;
    device.dispatch.cmd_set_viewport = stubCmdSetViewport;
    device.dispatch.cmd_set_scissor = stubCmdSetScissor;
    device.dispatch.cmd_begin_render_pass = stubCmdBeginRenderPass;
    device.dispatch.cmd_end_render_pass = stubCmdEndRenderPass;
    device.dispatch.begin_command_buffer = stubBeginCommandBuffer;
    device.dispatch.end_command_buffer = stubEndCommandBuffer;
}

test "TextRenderer.init wires core Vulkan objects" {
    const fake_device_handle = @as(types.VkDevice, @ptrFromInt(@as(usize, 0x1000)));

    var device = device_mod.Device{
        .allocator = std.testing.allocator,
        .loader = undefined,
        .dispatch = std.mem.zeroes(loader.DeviceDispatch),
        .handle = fake_device_handle,
        .allocation_callbacks = null,
    };

    setupTestDispatch(&device);
    TestCapture.reset();

    var memory_props = std.mem.zeroes(types.VkPhysicalDeviceMemoryProperties);
    memory_props.memoryTypeCount = 2;
    memory_props.memoryTypes[0] = .{ .propertyFlags = types.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, .heapIndex = 0 };
    memory_props.memoryTypes[1] = .{ .propertyFlags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, .heapIndex = 1 };
    memory_props.memoryHeapCount = 2;
    memory_props.memoryHeaps[0] = .{ .size = 1024 * 1024 * 1024, .flags = types.VK_MEMORY_HEAP_DEVICE_LOCAL_BIT };
    memory_props.memoryHeaps[1] = .{ .size = 512 * 1024 * 1024, .flags = 0 };

    var renderer = try TextRenderer.init(std.testing.allocator, &device, .{
        .extent = .{ .width = 800, .height = 600 },
        .surface_format = .B8G8R8A8_SRGB,
        .memory_props = memory_props,
        .frames_in_flight = 2,
        .max_instances = 128,
        .atlas_extent = .{ .width = 256, .height = 256 },
        .atlas_format = .R8_UNORM,
    });

    try std.testing.expectEqual(@as(u32, 2), renderer.frames_in_flight);
    try std.testing.expectEqual(types.VK_FORMAT_B8G8R8A8_SRGB, renderer.surface_format);
    try std.testing.expect(renderer.commandBuffersDirty());

    try std.testing.expectEqual(@as(usize, 1), TestCapture.descriptor_layout_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.descriptor_pool_calls);
    try std.testing.expectEqual(@as(usize, 0), TestCapture.descriptor_set_count);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.pipeline_layout_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.render_pass_create_calls);
    try std.testing.expectEqual(@as(usize, 2), TestCapture.shader_module_create_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.pipeline_create_calls);
    try std.testing.expectEqual(@as(u32, 2), TestCapture.pipeline_stage_count);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.sampler_create_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.image_create_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.image_view_create_calls);
    try std.testing.expectEqual(@as(usize, 4), TestCapture.buffer_create_calls);

    try std.testing.expectEqual(@as(usize, 0), TestCapture.update_descriptor_calls);

    renderer.deinit();

    try std.testing.expectEqual(@as(usize, 0), TestCapture.free_descriptor_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.destroy_pool_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.destroy_layout_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.destroy_pipeline_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.destroy_pipeline_layout_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.destroy_render_pass_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.destroy_sampler_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.destroy_image_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.destroy_image_view_calls);
    try std.testing.expectEqual(@as(usize, 4), TestCapture.destroy_buffer_calls);
}

test "TextRenderer.queueQuads batches glyph data" {
    const fake_device_handle = @as(types.VkDevice, @ptrFromInt(@as(usize, 0x2500)));

    var device = device_mod.Device{
        .allocator = std.testing.allocator,
        .loader = undefined,
        .dispatch = std.mem.zeroes(loader.DeviceDispatch),
        .handle = fake_device_handle,
        .allocation_callbacks = null,
    };

    setupTestDispatch(&device);
    TestCapture.reset();

    var memory_props = std.mem.zeroes(types.VkPhysicalDeviceMemoryProperties);
    memory_props.memoryTypeCount = 2;
    memory_props.memoryTypes[0] = .{ .propertyFlags = types.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, .heapIndex = 0 };
    memory_props.memoryTypes[1] = .{ .propertyFlags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, .heapIndex = 1 };
    memory_props.memoryHeapCount = 2;
    memory_props.memoryHeaps[0] = .{ .size = 1024 * 1024 * 1024, .flags = types.VK_MEMORY_HEAP_DEVICE_LOCAL_BIT };
    memory_props.memoryHeaps[1] = .{ .size = 512 * 1024 * 1024, .flags = 0 };

    var renderer = try TextRenderer.init(std.testing.allocator, &device, .{
        .extent = .{ .width = 1920, .height = 1080 },
        .surface_format = .B8G8R8A8_SRGB,
        .memory_props = memory_props,
        .frames_in_flight = 2,
        .max_instances = 16,
        .atlas_extent = .{ .width = 128, .height = 128 },
        .atlas_format = .R8_UNORM,
    });
    defer renderer.deinit();

    try renderer.beginFrame(0);

    const quads = [_]TextQuad{
        .{ .position = .{ 0.0, 0.0 }, .size = .{ 8.0, 16.0 }, .atlas_rect = .{ 0.0, 0.0, 0.25, 0.25 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
        .{ .position = .{ 32.0, 48.0 }, .size = .{ 12.0, 18.0 }, .atlas_rect = .{ 0.25, 0.25, 0.5, 0.5 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } },
        .{ .position = .{ 64.0, 96.0 }, .size = .{ 10.0, 20.0 }, .atlas_rect = .{ 0.5, 0.5, 0.25, 0.25 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } },
    };

    try renderer.queueQuads(quads[0..]);
    try std.testing.expectEqual(quads.len, try renderer.pendingInstanceCount(0));

    const stored_bytes = std.mem.sliceAsBytes(renderer.instance_data[0..quads.len]);
    const stored_quads = std.mem.bytesAsSlice(TextQuad, stored_bytes);
    try std.testing.expectEqualSlices(TextQuad, quads[0..], stored_quads);

    const command_buffer = @as(types.VkCommandBuffer, @ptrFromInt(@as(usize, 0x2600)));
    try renderer.encode(command_buffer);
    renderer.endFrame();

    try std.testing.expectEqual(@as(u32, @intCast(quads.len)), TestCapture.last_draw_instance_count);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.begin_command_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.end_command_calls);
    const begin_flags = TestCapture.last_begin_flags orelse @as(types.VkCommandBufferUsageFlags, 0xFFFF_FFFF);
    try std.testing.expectEqual(@as(types.VkCommandBufferUsageFlags, 0), begin_flags);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.descriptor_set_count);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.update_descriptor_calls);

    const stats = renderer.descriptor_cache.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.misses);
    try std.testing.expectEqual(@as(usize, 0), stats.hits);
    try std.testing.expectEqual(@as(f32, 0.0), stats.hit_rate);

    try std.testing.expectEqual(@as(usize, 0), TestCapture.begin_render_pass_calls);
    try std.testing.expectEqual(@as(usize, 0), TestCapture.end_render_pass_calls);

    const telemetry = try renderer.frameStats(0);
    try std.testing.expectEqual(@as(u32, 0), telemetry.frame_index);
    try std.testing.expectEqual(@as(usize, quads.len), telemetry.glyph_count);
    try std.testing.expectEqual(@as(usize, 1), telemetry.draw_count);
    try std.testing.expectEqual(@as(usize, 0), telemetry.atlas_uploads);
    try std.testing.expect(!telemetry.used_transfer_queue);
    try std.testing.expectEqual(@as(u64, 0), telemetry.submit_cpu_ns);
    try std.testing.expectApproxEqAbs(@as(f64, @floatFromInt(quads.len)), telemetry.glyphs_per_draw, 0.0001);

    const sync_info = try renderer.frameSyncInfo(0);
    try std.testing.expect(sync_info == null);

    try std.testing.expect(!renderer.commandBuffersDirty());
}

test "TextRenderer.beginFrame queues quads and encodes draw call" {
    const fake_device_handle = @as(types.VkDevice, @ptrFromInt(@as(usize, 0x2000)));

    var device = device_mod.Device{
        .allocator = std.testing.allocator,
        .loader = undefined,
        .dispatch = std.mem.zeroes(loader.DeviceDispatch),
        .handle = fake_device_handle,
        .allocation_callbacks = null,
    };

    setupTestDispatch(&device);
    TestCapture.reset();

    var memory_props = std.mem.zeroes(types.VkPhysicalDeviceMemoryProperties);
    memory_props.memoryTypeCount = 2;
    memory_props.memoryTypes[0] = .{ .propertyFlags = types.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, .heapIndex = 0 };
    memory_props.memoryTypes[1] = .{ .propertyFlags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, .heapIndex = 1 };
    memory_props.memoryHeapCount = 2;
    memory_props.memoryHeaps[0] = .{ .size = 1024 * 1024 * 1024, .flags = types.VK_MEMORY_HEAP_DEVICE_LOCAL_BIT };
    memory_props.memoryHeaps[1] = .{ .size = 512 * 1024 * 1024, .flags = 0 };

    var renderer = try TextRenderer.init(std.testing.allocator, &device, .{
        .extent = .{ .width = 640, .height = 480 },
        .surface_format = .B8G8R8A8_SRGB,
        .memory_props = memory_props,
        .frames_in_flight = 2,
        .max_instances = 8,
        .atlas_extent = .{ .width = 128, .height = 128 },
        .atlas_format = .R8_UNORM,
    });
    defer renderer.deinit();

    try renderer.beginFrame(0);

    const projection = [_]f32{
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    };
    try renderer.setProjection(projection[0..]);

    const quad = TextQuad{
        .position = .{ 10.0, 20.0 },
        .size = .{ 8.0, 12.0 },
        .atlas_rect = .{ 0.1, 0.2, 0.3, 0.4 },
        .color = .{ 1.0, 1.0, 1.0, 1.0 },
    };

    try renderer.queueQuad(quad);
    try std.testing.expectEqual(@as(usize, 1), try renderer.pendingInstanceCount(0));

    const command_buffer = @as(types.VkCommandBuffer, @ptrFromInt(@as(usize, 0x3000)));
    try renderer.encode(command_buffer);
    renderer.endFrame();

    try std.testing.expectEqual(@as(usize, 1), TestCapture.bind_pipeline_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.bind_descriptor_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.bind_vertex_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.draw_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.set_viewport_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.set_scissor_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.begin_command_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.end_command_calls);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.push_constant_calls);
    try std.testing.expectEqual(@as(u32, 64), TestCapture.last_push_size);
    try std.testing.expectEqual(@as(u32, 4), TestCapture.last_draw_vertex_count);
    try std.testing.expectEqual(@as(u32, 1), TestCapture.last_draw_instance_count);
    try std.testing.expectEqual(@as(types.VkDeviceSize, 0), TestCapture.last_instance_offset);
    try std.testing.expect(TestCapture.last_descriptor_set != null);
    try std.testing.expect(TestCapture.last_pipeline != null);

    try std.testing.expectEqual(@as(usize, 1), TestCapture.descriptor_set_count);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.update_descriptor_calls);

    const stats = renderer.descriptor_cache.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.misses);
    try std.testing.expectEqual(@as(usize, 0), stats.hits);

    const viewport = TestCapture.last_viewport orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(f32, 640.0), viewport.width);
    try std.testing.expectEqual(@as(f32, 480.0), viewport.height);

    const scissor = TestCapture.last_scissor orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(i32, 0), scissor.offset.x);
    try std.testing.expectEqual(@as(i32, 0), scissor.offset.y);
    try std.testing.expectEqual(@as(u32, 640), scissor.extent.width);
    try std.testing.expectEqual(@as(u32, 480), scissor.extent.height);

    try std.testing.expectEqual(@as(usize, 0), TestCapture.begin_render_pass_calls);
    try std.testing.expectEqual(@as(usize, 0), TestCapture.end_render_pass_calls);

    const telemetry = try renderer.frameStats(0);
    try std.testing.expectEqual(@as(u32, 0), telemetry.frame_index);
    try std.testing.expectEqual(@as(usize, 1), telemetry.glyph_count);
    try std.testing.expectEqual(@as(usize, 1), telemetry.draw_count);
    try std.testing.expectEqual(@as(usize, 0), telemetry.atlas_uploads);
    try std.testing.expect(!telemetry.used_transfer_queue);
    try std.testing.expectEqual(@as(u64, 0), telemetry.submit_cpu_ns);
    try std.testing.expectApproxEqAbs(1.0, telemetry.glyphs_per_draw, 0.0001);

    const sync_info = try renderer.frameSyncInfo(0);
    try std.testing.expect(sync_info == null);

    try std.testing.expect(!renderer.commandBuffersDirty());
}

test "TextRenderer adjusts batch limit based on glyph load" {
    const fake_device_handle = @as(types.VkDevice, @ptrFromInt(@as(usize, 0x3500)));

    var device = device_mod.Device{
        .allocator = std.testing.allocator,
        .loader = undefined,
        .dispatch = std.mem.zeroes(loader.DeviceDispatch),
        .handle = fake_device_handle,
        .allocation_callbacks = null,
    };

    setupTestDispatch(&device);
    TestCapture.reset();

    var memory_props = std.mem.zeroes(types.VkPhysicalDeviceMemoryProperties);
    memory_props.memoryTypeCount = 2;
    memory_props.memoryTypes[0] = .{ .propertyFlags = types.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, .heapIndex = 0 };
    memory_props.memoryTypes[1] = .{ .propertyFlags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, .heapIndex = 1 };
    memory_props.memoryHeapCount = 2;
    memory_props.memoryHeaps[0] = .{ .size = 1024 * 1024 * 1024, .flags = types.VK_MEMORY_HEAP_DEVICE_LOCAL_BIT };
    memory_props.memoryHeaps[1] = .{ .size = 512 * 1024 * 1024, .flags = 0 };

    const count: usize = 900;

    var renderer = try TextRenderer.init(std.testing.allocator, &device, .{
        .extent = .{ .width = 800, .height = 600 },
        .surface_format = .B8G8R8A8_SRGB,
        .memory_props = memory_props,
        .frames_in_flight = 2,
        .max_instances = 1024,
        .atlas_extent = .{ .width = 256, .height = 256 },
        .atlas_format = .R8_UNORM,
        .batch_target = 512,
        .batch_min = 128,
    });
    defer renderer.deinit();

    try renderer.beginFrame(0);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const quads = try alloc.alloc(TextQuad, count);
    for (quads, 0..) |*quad, i| {
        const offset = @as(f32, @floatFromInt(i));
        quad.* = TextQuad{
            .position = .{ offset, offset },
            .size = .{ 8.0, 16.0 },
            .atlas_rect = .{ 0.0, 0.0, 0.25, 0.25 },
            .color = .{ 1.0, 1.0, 1.0, 1.0 },
        };
    }

    try renderer.queueQuads(quads);

    const command_buffer = @as(types.VkCommandBuffer, @ptrFromInt(@as(usize, 0x3600)));
    try renderer.encode(command_buffer);
    renderer.endFrame();

    const telemetry = try renderer.frameStats(0);
    try std.testing.expectEqual(@as(usize, count), telemetry.glyph_count);
    try std.testing.expectEqual(@as(usize, 2), telemetry.draw_count);
    try std.testing.expectEqual(@as(usize, 512), telemetry.batch_limit);
    try std.testing.expectEqual(@as(u64, 0), telemetry.submit_cpu_ns);
    try std.testing.expectApproxEqAbs(@as(f64, 450.0), telemetry.glyphs_per_draw, 0.001);

    try std.testing.expectEqual(@as(usize, 900), renderer.batch_limit);
    try std.testing.expectEqual(@as(usize, 900), renderer.batch_target);
}

test "TextRenderer profiler aggregates frame telemetry" {
    const fake_device_handle = @as(types.VkDevice, @ptrFromInt(@as(usize, 0x3700)));

    var device = device_mod.Device{
        .allocator = std.testing.allocator,
        .loader = undefined,
        .dispatch = std.mem.zeroes(loader.DeviceDispatch),
        .handle = fake_device_handle,
        .allocation_callbacks = null,
    };

    setupTestDispatch(&device);
    TestCapture.reset();

    var memory_props = std.mem.zeroes(types.VkPhysicalDeviceMemoryProperties);
    memory_props.memoryTypeCount = 2;
    memory_props.memoryTypes[0] = .{ .propertyFlags = types.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, .heapIndex = 0 };
    memory_props.memoryTypes[1] = .{ .propertyFlags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, .heapIndex = 1 };
    memory_props.memoryHeapCount = 2;
    memory_props.memoryHeaps[0] = .{ .size = 1024 * 1024 * 1024, .flags = types.VK_MEMORY_HEAP_DEVICE_LOCAL_BIT };
    memory_props.memoryHeaps[1] = .{ .size = 512 * 1024 * 1024, .flags = 0 };

    const Capture = struct {
        pub var call_count: usize = 0;
        pub var last_summary: ?ProfilerSummary = null;

        pub fn reset() void {
            call_count = 0;
            last_summary = null;
        }

        pub fn log(_: ?*anyopaque, summary: ProfilerSummary) void {
            call_count += 1;
            last_summary = summary;
        }
    };

    Capture.reset();

    var renderer = try TextRenderer.init(std.testing.allocator, &device, .{
        .extent = .{ .width = 640, .height = 480 },
        .surface_format = .B8G8R8A8_SRGB,
        .memory_props = memory_props,
        .frames_in_flight = 2,
        .max_instances = 32,
        .atlas_extent = .{ .width = 128, .height = 128 },
        .atlas_format = .R8_UNORM,
        .profiler = .{ .log_interval = 2, .log_callback = Capture.log, .log_context = null },
    });
    defer renderer.deinit();

    const quads = [_]TextQuad{
        .{ .position = .{ 0.0, 0.0 }, .size = .{ 8.0, 16.0 }, .atlas_rect = .{ 0.0, 0.0, 0.25, 0.25 }, .color = .{ 1.0, 1.0, 1.0, 1.0 } },
        .{ .position = .{ 12.0, 24.0 }, .size = .{ 8.0, 16.0 }, .atlas_rect = .{ 0.25, 0.25, 0.25, 0.25 }, .color = .{ 1.0, 0.8, 0.3, 1.0 } },
    };

    for (0..2) |frame_index| {
        try renderer.beginFrame(@intCast(frame_index));
        try renderer.queueQuads(quads[0..]);
        const command_buffer = @as(types.VkCommandBuffer, @ptrFromInt(@as(usize, 0x3800 + frame_index)));
        try renderer.encode(command_buffer);
        try renderer.recordSubmitDuration(@intCast(frame_index), 150_000);
        renderer.endFrame();
    }

    try std.testing.expectEqual(@as(usize, 1), Capture.call_count);
    const summary = renderer.profilerSummary() orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 2), summary.frames);
    try std.testing.expect(summary.avg_glyphs >= 2.0);
    try std.testing.expect(summary.avg_draws >= 1.0);
    try std.testing.expect(summary.max_draws >= 1);
    try std.testing.expectEqual(summary.avg_transfer_ns, 0.0);
    try std.testing.expect(summary.avg_submit_ns > 0.0);
    try std.testing.expect(summary.encode_hist.samples >= 2);
    try std.testing.expect(summary.encode_hist.p95_ns > 0);
    try std.testing.expect(summary.submit_hist.samples >= 2);

    const frame0_stats = try renderer.frameStats(0);
    try std.testing.expectEqual(@as(u64, 150_000), frame0_stats.submit_cpu_ns);

    const hud = renderer.profilerHud(5_000_000) orelse return error.TestExpectedEqual;
    try std.testing.expect(hud.encode_goal_met);
    try std.testing.expect(hud.submit_avg_ms > 0.0);

    var hud_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer hud_buffer.deinit();
    try hud.writeLine(hud_buffer.writer());
    try std.testing.expect(hud_buffer.items.len > 0);
}

test "TextRenderer persists pipeline cache when enabled" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_root);
    const path_str = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "cache.bin" });
    defer std.testing.allocator.free(path_str);

    const fake_device_handle = @as(types.VkDevice, @ptrFromInt(@as(usize, 0x3900)));

    var device = device_mod.Device{
        .allocator = std.testing.allocator,
        .loader = undefined,
        .dispatch = std.mem.zeroes(loader.DeviceDispatch),
        .handle = fake_device_handle,
        .allocation_callbacks = null,
    };

    setupTestDispatch(&device);
    TestCapture.reset();

    var memory_props = std.mem.zeroes(types.VkPhysicalDeviceMemoryProperties);
    memory_props.memoryTypeCount = 2;
    memory_props.memoryTypes[0] = .{ .propertyFlags = types.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, .heapIndex = 0 };
    memory_props.memoryTypes[1] = .{ .propertyFlags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, .heapIndex = 1 };
    memory_props.memoryHeapCount = 2;
    memory_props.memoryHeaps[0] = .{ .size = 1024 * 1024 * 1024, .flags = types.VK_MEMORY_HEAP_DEVICE_LOCAL_BIT };
    memory_props.memoryHeaps[1] = .{ .size = 512 * 1024 * 1024, .flags = 0 };

    var renderer = try TextRenderer.init(std.testing.allocator, &device, .{
        .extent = .{ .width = 640, .height = 480 },
        .surface_format = .B8G8R8A8_SRGB,
        .memory_props = memory_props,
        .frames_in_flight = 2,
        .max_instances = 16,
        .atlas_extent = .{ .width = 128, .height = 128 },
        .atlas_format = .R8_UNORM,
        .pipeline_cache_path = path_str,
    });
    defer renderer.deinit();

    try renderer.persistPipelineCache();

    const stat = tmp.dir.statFile("cache.bin") catch return error.TestUnexpectedResult;
    try std.testing.expect(stat.size > 0);
}
