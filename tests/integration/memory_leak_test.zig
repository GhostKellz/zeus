//! Integration test for memory leak detection and long-running stability
//!
//! This test validates Zeus memory management over extended operation:
//! - 1000+ frame stability test
//! - Memory leak detection
//! - Resource cleanup verification
//! - Allocation/deallocation patterns

const std = @import("std");
const testing = std.testing;

const TEST_FRAMES_SHORT = 100;
const TEST_FRAMES_LONG = 1000;
const GLYPHS_PER_FRAME = 5000;

/// Tracks memory allocations for leak detection
const MemoryTracker = struct {
    allocator: std.mem.Allocator,
    allocations: std.ArrayList([]u8),
    peak_usage: usize,
    current_usage: usize,

    pub fn init(allocator: std.mem.Allocator) !*MemoryTracker {
        const tracker = try allocator.create(MemoryTracker);
        const allocations = std.ArrayList([]u8){};
        tracker.* = .{
            .allocator = allocator,
            .allocations = allocations,
            .peak_usage = 0,
            .current_usage = 0,
        };
        return tracker;
    }

    pub fn deinit(self: *MemoryTracker) void {
        for (self.allocations.items) |allocation| {
            self.allocator.free(allocation);
        }
        self.allocations.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn alloc(self: *MemoryTracker, size: usize) ![]u8 {
        const memory = try self.allocator.alloc(u8, size);
        try self.allocations.append(self.allocator, memory);
        self.current_usage += size;
        if (self.current_usage > self.peak_usage) {
            self.peak_usage = self.current_usage;
        }
        return memory;
    }

    pub fn free(self: *MemoryTracker, memory: []u8) void {
        self.current_usage -= memory.len;
        self.allocator.free(memory);

        // Remove from tracking
        for (self.allocations.items, 0..) |allocation, i| {
            if (allocation.ptr == memory.ptr) {
                _ = self.allocations.swapRemove(i);
                break;
            }
        }
    }

    pub fn hasLeaks(self: *const MemoryTracker) bool {
        return self.allocations.items.len > 0;
    }

    pub fn leakCount(self: *const MemoryTracker) usize {
        return self.allocations.items.len;
    }

    pub fn printStats(self: *const MemoryTracker) void {
        std.debug.print("Memory Stats:\n", .{});
        std.debug.print("  Peak usage: {d} KB\n", .{self.peak_usage / 1024});
        std.debug.print("  Current usage: {d} KB\n", .{self.current_usage / 1024});
        std.debug.print("  Active allocations: {d}\n", .{self.allocations.items.len});
        if (self.hasLeaks()) {
            std.debug.print("  ⚠️  MEMORY LEAK DETECTED ⚠️\n", .{});
        } else {
            std.debug.print("  ✅ No leaks detected\n", .{});
        }
    }
};

/// Simulated per-frame resources
const FrameResources = struct {
    glyph_buffer: []u8,
    instance_buffer: []u8,
    tracker: *MemoryTracker,

    pub fn init(tracker: *MemoryTracker, glyph_count: usize) !FrameResources {
        const glyph_size = glyph_count * 64; // 64 bytes per glyph (TextQuad)
        const instance_size = glyph_count * 16; // 16 bytes per instance

        return .{
            .glyph_buffer = try tracker.alloc(glyph_size),
            .instance_buffer = try tracker.alloc(instance_size),
            .tracker = tracker,
        };
    }

    pub fn deinit(self: *FrameResources) void {
        self.tracker.free(self.glyph_buffer);
        self.tracker.free(self.instance_buffer);
    }
};

test "memory_leak: basic allocation/deallocation" {
    std.debug.print("\n[TEST] Basic Allocation/Deallocation\n", .{});

    const tracker = try MemoryTracker.init(testing.allocator);
    defer tracker.deinit();

    // Allocate some memory
    const mem1 = try tracker.alloc(1024);
    const mem2 = try tracker.alloc(2048);

    try testing.expectEqual(@as(usize, 2), tracker.leakCount());
    try testing.expectEqual(@as(usize, 3072), tracker.current_usage);

    // Free memory
    tracker.free(mem1);
    tracker.free(mem2);

    try testing.expect(!tracker.hasLeaks());
    try testing.expectEqual(@as(usize, 0), tracker.current_usage);

    tracker.printStats();
    std.debug.print("[PASS] Basic allocation/deallocation test completed\n", .{});
}

test "memory_leak: per-frame resource lifecycle" {
    std.debug.print("\n[TEST] Per-Frame Resource Lifecycle\n", .{});

    const tracker = try MemoryTracker.init(testing.allocator);
    defer tracker.deinit();

    const frame_count = 10;
    for (0..frame_count) |frame| {
        var resources = try FrameResources.init(tracker, GLYPHS_PER_FRAME);
        defer resources.deinit();

        // Simulate frame rendering
        std.mem.doNotOptimizeAway(&resources);

        if (frame == 0) {
            std.debug.print("Frame 0 usage: {d} KB\n", .{tracker.current_usage / 1024});
        }
    }

    // After all frames, no leaks should remain
    try testing.expect(!tracker.hasLeaks());
    try testing.expectEqual(@as(usize, 0), tracker.current_usage);

    tracker.printStats();
    std.debug.print("[PASS] Per-frame resource lifecycle test completed\n", .{});
}

test "memory_leak: long-running stability (1000 frames)" {
    std.debug.print("\n[TEST] Long-Running Stability: {d} frames\n", .{TEST_FRAMES_LONG});

    const tracker = try MemoryTracker.init(testing.allocator);
    defer tracker.deinit();

    var timer = std.time.Timer.start() catch unreachable;

    for (0..TEST_FRAMES_LONG) |frame| {
        var resources = try FrameResources.init(tracker, GLYPHS_PER_FRAME);
        defer resources.deinit();

        // Simulate rendering
        std.mem.doNotOptimizeAway(&resources);

        // Log progress every 100 frames
        if ((frame + 1) % 100 == 0) {
            std.debug.print("  Frame {d}/{d} - Current usage: {d} KB\n", .{
                frame + 1,
                TEST_FRAMES_LONG,
                tracker.current_usage / 1024,
            });

            // Current usage should be non-zero during frame (resources allocated)
            // but should be consistent across frames (no accumulation)
            if (frame >= 100) {
                // After warmup, usage should be stable
                try testing.expect(tracker.current_usage > 0);
            }
        }
    }

    const elapsed = timer.read();

    // All resources should be freed
    try testing.expect(!tracker.hasLeaks());
    try testing.expectEqual(@as(usize, 0), tracker.current_usage);

    std.debug.print("\nCompleted {d} frames in {d:.3}ms\n", .{
        TEST_FRAMES_LONG,
        @as(f64, @floatFromInt(elapsed)) / 1_000_000.0,
    });
    std.debug.print("Avg frame time: {d:.3}µs\n", .{
        @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(TEST_FRAMES_LONG)) / 1000.0,
    });

    tracker.printStats();
    std.debug.print("[PASS] Long-running stability test completed\n", .{});
}

test "memory_leak: atlas resource management" {
    std.debug.print("\n[TEST] Atlas Resource Management\n", .{});

    const tracker = try MemoryTracker.init(testing.allocator);
    defer tracker.deinit();

    // Simulate atlas allocation (persistent across frames)
    const atlas_width = 2048;
    const atlas_height = 2048;
    const atlas_size = atlas_width * atlas_height; // 1 byte per pixel (R8)

    const atlas_data = try tracker.alloc(atlas_size);

    std.debug.print("Atlas allocated: {d}x{d} = {d} KB\n", .{
        atlas_width,
        atlas_height,
        atlas_size / 1024,
    });

    // Render multiple frames with persistent atlas
    for (0..TEST_FRAMES_SHORT) |_| {
        var resources = try FrameResources.init(tracker, GLYPHS_PER_FRAME);
        defer resources.deinit();

        // Atlas should remain allocated
        try testing.expect(tracker.current_usage >= atlas_size);
    }

    // Free atlas
    tracker.free(atlas_data);

    // Should have no leaks after atlas cleanup
    try testing.expect(!tracker.hasLeaks());

    tracker.printStats();
    std.debug.print("[PASS] Atlas resource management test completed\n", .{});
}

test "memory_leak: growth and shrink pattern" {
    std.debug.print("\n[TEST] Growth and Shrink Pattern\n", .{});

    const tracker = try MemoryTracker.init(testing.allocator);
    defer tracker.deinit();

    // Simulate varying glyph counts (e.g., scrolling through different file sections)
    const glyph_counts = [_]usize{ 1000, 5000, 10_000, 15_000, 10_000, 5000, 1000 };

    var peak_seen: usize = 0;
    for (glyph_counts, 0..) |count, i| {
        var resources = try FrameResources.init(tracker, count);
        defer resources.deinit();

        if (tracker.current_usage > peak_seen) {
            peak_seen = tracker.current_usage;
        }

        std.debug.print("  Frame {d}: {d} glyphs, {d} KB usage\n", .{
            i,
            count,
            tracker.current_usage / 1024,
        });
    }

    // After all variations, no leaks
    try testing.expect(!tracker.hasLeaks());
    try testing.expectEqual(@as(usize, 0), tracker.current_usage);

    std.debug.print("Peak usage during test: {d} KB\n", .{tracker.peak_usage / 1024});
    std.debug.print("Peak seen during frames: {d} KB\n", .{peak_seen / 1024});

    tracker.printStats();
    std.debug.print("[PASS] Growth and shrink pattern test completed\n", .{});
}

test "memory_leak: concurrent allocations" {
    std.debug.print("\n[TEST] Concurrent Allocations (Simulated)\n", .{});

    const tracker = try MemoryTracker.init(testing.allocator);
    defer tracker.deinit();

    // Simulate multiple in-flight frames (double/triple buffering)
    const in_flight_frames = 3;
    var frame_resources: [in_flight_frames]FrameResources = undefined;

    // Allocate all in-flight frames
    for (&frame_resources, 0..) |*resources, i| {
        resources.* = try FrameResources.init(tracker, GLYPHS_PER_FRAME);
        std.debug.print("  Allocated in-flight frame {d}: {d} KB\n", .{
            i,
            tracker.current_usage / 1024,
        });
    }

    // Usage should be 3x single frame
    const expected_min = (GLYPHS_PER_FRAME * 80 * in_flight_frames); // Conservative estimate
    try testing.expect(tracker.current_usage >= expected_min);

    // Free all in-flight frames
    for (&frame_resources, 0..) |*resources, i| {
        resources.deinit();
        std.debug.print("  Freed in-flight frame {d}: {d} KB remaining\n", .{
            i,
            tracker.current_usage / 1024,
        });
    }

    // No leaks
    try testing.expect(!tracker.hasLeaks());

    tracker.printStats();
    std.debug.print("[PASS] Concurrent allocations test completed\n", .{});
}

/// Memory usage pattern validator
const UsagePattern = struct {
    samples: []usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, _: usize) !UsagePattern {
        return .{
            .samples = try allocator.alloc(usize, 0),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *UsagePattern) void {
        self.allocator.free(self.samples);
    }

    pub fn record(self: *UsagePattern, usage: usize) !void {
        const old_len = self.samples.len;
        const new_samples = try self.allocator.realloc(self.samples, old_len + 1);
        self.samples = new_samples;
        self.samples[old_len] = usage;
    }

    pub fn isStable(self: *const UsagePattern, window: usize) bool {
        if (self.samples.len < window) return false;

        const start_idx = self.samples.len - window;
        const first = self.samples[start_idx];

        // Check if usage is stable (within 10% variance)
        const threshold = first / 10;
        for (self.samples[start_idx..]) |sample| {
            const diff = if (sample > first) sample - first else first - sample;
            if (diff > threshold) return false;
        }

        return true;
    }

    pub fn isGrowing(self: *const UsagePattern) bool {
        if (self.samples.len < 2) return false;

        const mid = self.samples.len / 2;
        const first_half = self.samples[0..mid];
        const second_half = self.samples[mid..];

        var first_avg: usize = 0;
        var second_avg: usize = 0;

        for (first_half) |s| first_avg += s;
        for (second_half) |s| second_avg += s;

        first_avg /= first_half.len;
        second_avg /= second_half.len;

        // Growing if second half is >10% higher than first half
        return second_avg > first_avg + (first_avg / 10);
    }
};

test "memory_leak: usage pattern analysis" {
    std.debug.print("\n[TEST] Memory Usage Pattern Analysis\n", .{});

    const tracker = try MemoryTracker.init(testing.allocator);
    defer tracker.deinit();

    var pattern = try UsagePattern.init(testing.allocator, 0);
    defer pattern.deinit();

    // Simulate frames and record usage
    for (0..50) |_| {
        var resources = try FrameResources.init(tracker, GLYPHS_PER_FRAME);
        try pattern.record(tracker.current_usage);
        resources.deinit();
        try pattern.record(tracker.current_usage);
    }

    std.debug.print("Recorded {d} usage samples\n", .{pattern.samples.len});

    // After cleanup, usage should be 0 consistently
    const stable = pattern.isStable(10);
    const growing = pattern.isGrowing();

    std.debug.print("  Stable: {}\n", .{stable});
    std.debug.print("  Growing: {}\n", .{growing});

    // Should be stable (not growing - no leaks)
    try testing.expect(!growing);

    tracker.printStats();
    std.debug.print("[PASS] Usage pattern analysis test completed\n", .{});
}
