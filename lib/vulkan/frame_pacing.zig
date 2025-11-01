const std = @import("std");
const types = @import("types.zig");

pub const Clock = struct {
    context: ?*anyopaque = null,
    now: *const fn (?*anyopaque) i128,
    sleep: *const fn (?*anyopaque, u64) void,
};

pub const Options = struct {
    guard_ns: u64 = 200_000,
    clock: ?Clock = null,
};

pub const WaylandFeedback = struct {
    presentation_time_ns: u64,
    refresh_interval_ns: u64,
    flags: u32 = 0,
};

const default_clock = Clock{
    .context = null,
    .now = defaultNow,
    .sleep = defaultSleep,
};

fn defaultNow(_: ?*anyopaque) i128 {
    return std.time.nanoTimestamp();
}

fn defaultSleep(_: ?*anyopaque, ns: u64) void {
    std.time.sleep(ns);
}

pub const FramePacer = struct {
    target_fps: u32,
    target_frame_time_ns: u64,
    frame_times: [60]u64,
    frame_index: usize,
    last_frame_time: i128,
    frame_begin_time: i128,
    clock: Clock,
    sleep_guard_ns: u64,
    last_wayland_feedback: ?WaylandFeedback,

    pub fn init(target_fps: u32) FramePacer {
        return FramePacer.initWithOptions(target_fps, .{});
    }

    pub fn initWithOptions(target_fps: u32, options: Options) FramePacer {
        std.debug.assert(target_fps > 0);
        const clock = options.clock orelse default_clock;
        const now = clock.now(clock.context);
        const target_ns = @divTrunc(1_000_000_000, target_fps);
        const guard = if (options.guard_ns > target_ns) target_ns else options.guard_ns;
        return .{
            .target_fps = target_fps,
            .target_frame_time_ns = target_ns,
            .frame_times = [_]u64{0} ** 60,
            .frame_index = 0,
            .last_frame_time = now,
            .frame_begin_time = now,
            .clock = clock,
            .sleep_guard_ns = guard,
            .last_wayland_feedback = null,
        };
    }

    pub fn beginFrame(self: *FramePacer) u64 {
        const now = self.clock.now(self.clock.context);
        const delta_i128 = now - self.last_frame_time;
        const delta: u64 = if (delta_i128 < 0)
            0
        else
            @as(u64, @intCast(delta_i128));

        self.frame_times[self.frame_index % self.frame_times.len] = delta;
        self.frame_index += 1;
        self.last_frame_time = now;
        self.frame_begin_time = now;

        return delta;
    }

    pub fn getAverageFrameTime(self: *const FramePacer, window: usize) u64 {
        if (window == 0) return 0;
        var valid: usize = @min(window, self.frame_times.len);
        if (self.frame_index < valid) {
            valid = self.frame_index;
        }
        if (valid == 0) return 0;
        var sum: u64 = 0;
        var i: usize = 0;
        while (i < valid) : (i += 1) {
            sum += self.frame_times[(self.frame_index + self.frame_times.len - i - 1) % self.frame_times.len];
        }
        return @divTrunc(sum, @as(u64, @intCast(valid)));
    }

    pub fn getCurrentFPS(self: *const FramePacer) f32 {
        const avg_ns = self.getAverageFrameTime(10);
        if (avg_ns == 0) return 0.0;
        return 1_000_000_000.0 / @as(f32, @floatFromInt(avg_ns));
    }

    pub fn isHittingTarget(self: *const FramePacer) bool {
        const avg = self.getAverageFrameTime(30);
        if (avg == 0) return false;
        const tolerance = self.target_frame_time_ns / 20;
        const lower = self.target_frame_time_ns - tolerance;
        const upper = self.target_frame_time_ns + tolerance;
        return avg >= lower and avg <= upper;
    }

    pub fn throttle(self: *FramePacer) void {
        if (self.target_frame_time_ns == 0) return;

        const start = self.frame_begin_time;
        const now = self.clock.now(self.clock.context);
        const elapsed_i128 = now - start;
        var elapsed: u64 = if (elapsed_i128 <= 0)
            0
        else
            @as(u64, @intCast(elapsed_i128));

        if (elapsed >= self.target_frame_time_ns) return;

        var remaining = self.target_frame_time_ns - elapsed;

        if (remaining > self.sleep_guard_ns) {
            const sleep_ns = remaining - self.sleep_guard_ns;
            if (sleep_ns > 0) {
                self.clock.sleep(self.clock.context, sleep_ns);
            }
            const after = self.clock.now(self.clock.context);
            const after_elapsed_i128 = after - start;
            elapsed = if (after_elapsed_i128 <= 0)
                0
            else
                @as(u64, @intCast(after_elapsed_i128));
            if (elapsed >= self.target_frame_time_ns) return;
            remaining = self.target_frame_time_ns - elapsed;
        }

        if (remaining > 0) {
            self.clock.sleep(self.clock.context, remaining);
        }
    }

    pub fn recordWaylandFeedback(self: *FramePacer, feedback: WaylandFeedback) void {
        self.last_wayland_feedback = feedback;
        if (feedback.refresh_interval_ns != 0) {
            self.target_frame_time_ns = feedback.refresh_interval_ns;
            const fps_candidate_u64 = @divTrunc(1_000_000_000, feedback.refresh_interval_ns);
            const fps_candidate: u32 = @intCast(fps_candidate_u64);
            const new_fps = @max(@as(u32, 1), fps_candidate);
            self.target_fps = new_fps;
            if (self.sleep_guard_ns > self.target_frame_time_ns) {
                self.sleep_guard_ns = self.target_frame_time_ns;
            }
        }
    }

    pub fn reset(self: *FramePacer) void {
        self.frame_times = [_]u64{0} ** 60;
        self.frame_index = 0;
        const now = self.clock.now(self.clock.context);
        self.last_frame_time = now;
        self.frame_begin_time = now;
        self.last_wayland_feedback = null;
    }
};

pub fn estimatePresentMode(target_hz: u32) types.VkPresentModeKHR {
    if (target_hz >= 300) {
        return types.VkPresentModeKHR.MAILBOX;
    } else if (target_hz >= 144) {
        return types.VkPresentModeKHR.FIFO_RELAXED;
    } else {
        return types.VkPresentModeKHR.FIFO;
    }
}

// Tests ---------------------------------------------------------------------

fn recordFrame(pacer: *FramePacer, frame_time_ns: u64) void {
    pacer.frame_times[pacer.frame_index % pacer.frame_times.len] = frame_time_ns;
    pacer.frame_index += 1;
}

const FakeClock = struct {
    pub var now_value: i128 = 0;
    pub var sleep_calls: usize = 0;
    pub var total_sleep_ns: u64 = 0;
    pub var last_sleep_ns: u64 = 0;

    pub fn reset(start: i128) void {
        now_value = start;
        sleep_calls = 0;
        total_sleep_ns = 0;
        last_sleep_ns = 0;
    }

    pub fn now(_: ?*anyopaque) i128 {
        return now_value;
    }

    pub fn sleep(_: ?*anyopaque, ns: u64) void {
        sleep_calls += 1;
        last_sleep_ns = ns;
        total_sleep_ns += ns;
        now_value += @as(i128, @intCast(ns));
    }
};

test "FramePacer beginFrame records delta and updates history" {
    var pacer = FramePacer.init(240);
    const now = std.time.nanoTimestamp();
    pacer.last_frame_time = now - 1_000_000; // 1ms
    pacer.frame_begin_time = pacer.last_frame_time;
    const delta = pacer.beginFrame();
    try std.testing.expect(delta >= 1_000_000);
    try std.testing.expect(delta < 20_000_000);
    try std.testing.expectEqual(@as(usize, 1), pacer.frame_index);
    try std.testing.expectEqual(delta, pacer.frame_times[0]);
}

test "FramePacer averages and FPS reflect recorded values" {
    var pacer = FramePacer.init(240);
    pacer.frame_times = [_]u64{0} ** 60;
    pacer.frame_index = 0;

    recordFrame(&pacer, 4_000_000);
    recordFrame(&pacer, 4_200_000);
    recordFrame(&pacer, 4_400_000);

    const avg = pacer.getAverageFrameTime(3);
    const expected_avg: u64 = @divTrunc(4_000_000 + 4_200_000 + 4_400_000, 3);
    try std.testing.expectEqual(expected_avg, avg);

    const fps = pacer.getCurrentFPS();
    const expected_fps = 1_000_000_000.0 / @as(f32, @floatFromInt(expected_avg));
    try std.testing.expect(std.math.approxEqAbs(f32, expected_fps, fps, 0.1));
}

test "FramePacer target check uses 5 percent tolerance" {
    var pacer = FramePacer.init(360);
    pacer.frame_times = [_]u64{0} ** 60;
    pacer.frame_index = 0;

    const target = pacer.target_frame_time_ns;
    const below = target - @divTrunc(target, 50); // 2% faster
    const above = target + @divTrunc(target, 100); // 1% slower

    recordFrame(&pacer, below);
    recordFrame(&pacer, target);
    recordFrame(&pacer, above);

    try std.testing.expect(pacer.isHittingTarget());

    recordFrame(&pacer, target + @divTrunc(target, 4)); // 25% slow
    try std.testing.expect(!pacer.isHittingTarget());
}

test "FramePacer throttle enforces frame budget" {
    FakeClock.reset(0);
    var pacer = FramePacer.initWithOptions(120, .{
        .clock = Clock{ .context = null, .now = FakeClock.now, .sleep = FakeClock.sleep },
        .guard_ns = 200_000,
    });

    _ = pacer.beginFrame();
    FakeClock.now_value += 4_000_000;
    pacer.throttle();

    const expected_total_sleep = pacer.target_frame_time_ns - 4_000_000;
    try std.testing.expectEqual(expected_total_sleep, FakeClock.total_sleep_ns);
    try std.testing.expectEqual(@as(usize, 2), FakeClock.sleep_calls);
    try std.testing.expectEqual(@as(i128, @intCast(pacer.target_frame_time_ns)), FakeClock.now_value);
}

test "FramePacer records Wayland feedback" {
    var pacer = FramePacer.init(144);
    const feedback = WaylandFeedback{
        .presentation_time_ns = 1_000_000,
        .refresh_interval_ns = 5_000_000,
        .flags = 1,
    };
    pacer.recordWaylandFeedback(feedback);
    try std.testing.expectEqual(feedback.refresh_interval_ns, pacer.target_frame_time_ns);
    try std.testing.expectEqual(@as(u32, 200), pacer.target_fps);
    try std.testing.expect(pacer.last_wayland_feedback != null);
    try std.testing.expectEqual(feedback.refresh_interval_ns, pacer.last_wayland_feedback.?.refresh_interval_ns);
}

test "FramePacer feedback clamps guard" {
    FakeClock.reset(0);
    var pacer = FramePacer.initWithOptions(60, .{
        .clock = Clock{ .context = null, .now = FakeClock.now, .sleep = FakeClock.sleep },
        .guard_ns = 10_000_000,
    });
    const feedback = WaylandFeedback{
        .presentation_time_ns = 500_000,
        .refresh_interval_ns = 2_000_000,
        .flags = 0,
    };
    pacer.recordWaylandFeedback(feedback);
    try std.testing.expectEqual(@as(u64, 2_000_000), pacer.sleep_guard_ns);
    try std.testing.expectEqual(@as(u32, 500), pacer.target_fps);
}

test "estimatePresentMode suggests mailbox for high refresh rates" {
    try std.testing.expectEqual(types.VkPresentModeKHR.MAILBOX, estimatePresentMode(360));
    try std.testing.expectEqual(types.VkPresentModeKHR.FIFO_RELAXED, estimatePresentMode(240));
    try std.testing.expectEqual(types.VkPresentModeKHR.FIFO_RELAXED, estimatePresentMode(144));
}
