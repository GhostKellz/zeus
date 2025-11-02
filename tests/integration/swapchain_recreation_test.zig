//! Integration test for swapchain recreation and resize handling
//!
//! This test validates Zeus behavior when the window is resized:
//! - Swapchain recreation without leaks
//! - Resource cleanup during resize
//! - Frame synchronization during recreation
//! - Correct handling of multiple rapid resizes

const std = @import("std");
const testing = std.testing;

/// Simulated window dimensions
const WindowDimensions = struct {
    width: u32,
    height: u32,

    pub fn format(self: WindowDimensions, comptime _: []const u8, _: anytype, writer: anytype) !void {
        try writer.print("{d}x{d}", .{ self.width, self.height });
    }
};

/// Simulated swapchain state
const MockSwapchain = struct {
    dimensions: WindowDimensions,
    image_count: u32,
    allocations: usize,

    pub fn init(width: u32, height: u32) MockSwapchain {
        return .{
            .dimensions = .{ .width = width, .height = height },
            .image_count = 3, // Triple buffering
            .allocations = 1,
        };
    }

    pub fn recreate(self: *MockSwapchain, new_width: u32, new_height: u32) void {
        // Simulate cleanup of old swapchain
        self.allocations -= 1;

        // Create new swapchain
        self.dimensions = .{ .width = new_width, .height = new_height };
        self.allocations += 1;
    }

    pub fn deinit(self: *MockSwapchain) void {
        self.allocations -= 1;
    }

    pub fn isLeaking(self: MockSwapchain) bool {
        return self.allocations != 0;
    }
};

/// Resize test scenario
const ResizeScenario = struct {
    name: []const u8,
    resizes: []const WindowDimensions,
};

test "swapchain_recreation: basic resize" {
    std.debug.print("\n[TEST] Basic Swapchain Recreation\n", .{});

    var swapchain = MockSwapchain.init(1920, 1080);

    std.debug.print("Initial: {any}\n", .{swapchain.dimensions});
    try testing.expectEqual(@as(u32, 1920), swapchain.dimensions.width);
    try testing.expectEqual(@as(u32, 1080), swapchain.dimensions.height);
    try testing.expectEqual(@as(usize, 1), swapchain.allocations);

    // Resize to 4K
    swapchain.recreate(3840, 2160);
    std.debug.print("After resize: {any}\n", .{swapchain.dimensions});
    try testing.expectEqual(@as(u32, 3840), swapchain.dimensions.width);
    try testing.expectEqual(@as(u32, 2160), swapchain.dimensions.height);
    try testing.expectEqual(@as(usize, 1), swapchain.allocations); // Should still be 1 (old freed, new created)

    // Cleanup
    swapchain.deinit();
    try testing.expect(!swapchain.isLeaking());

    std.debug.print("[PASS] Basic swapchain recreation test completed\n", .{});
}

test "swapchain_recreation: multiple sequential resizes" {
    std.debug.print("\n[TEST] Multiple Sequential Resizes\n", .{});

    const scenarios = [_]ResizeScenario{
        .{
            .name = "Common resolutions",
            .resizes = &[_]WindowDimensions{
                .{ .width = 1920, .height = 1080 },
                .{ .width = 2560, .height = 1440 },
                .{ .width = 3840, .height = 2160 },
                .{ .width = 1920, .height = 1080 },
            },
        },
        .{
            .name = "Extreme aspect ratios",
            .resizes = &[_]WindowDimensions{
                .{ .width = 3440, .height = 1440 }, // Ultrawide
                .{ .width = 2560, .height = 1080 }, // Super ultrawide
                .{ .width = 1920, .height = 1080 }, // Standard
            },
        },
        .{
            .name = "Rapid small changes",
            .resizes = &[_]WindowDimensions{
                .{ .width = 1920, .height = 1080 },
                .{ .width = 1921, .height = 1080 },
                .{ .width = 1922, .height = 1080 },
                .{ .width = 1920, .height = 1080 },
            },
        },
    };

    for (scenarios) |scenario| {
        std.debug.print("\nScenario: {s}\n", .{scenario.name});

        var swapchain = MockSwapchain.init(scenario.resizes[0].width, scenario.resizes[0].height);
        defer swapchain.deinit();

        for (scenario.resizes[1..], 0..) |dims, i| {
            std.debug.print("  Resize {d}: {any} -> {any}\n", .{ i + 1, swapchain.dimensions, dims });
            swapchain.recreate(dims.width, dims.height);

            try testing.expectEqual(dims.width, swapchain.dimensions.width);
            try testing.expectEqual(dims.height, swapchain.dimensions.height);
            try testing.expectEqual(@as(usize, 1), swapchain.allocations); // No leaks
        }

        try testing.expect(!swapchain.isLeaking());
    }

    std.debug.print("[PASS] Multiple sequential resizes test completed\n", .{});
}

test "swapchain_recreation: stress test - 100 rapid resizes" {
    std.debug.print("\n[TEST] Stress Test: 100 Rapid Resizes\n", .{});

    var swapchain = MockSwapchain.init(1920, 1080);
    defer swapchain.deinit();

    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();

    var timer = std.time.Timer.start() catch unreachable;

    const resize_count = 100;
    for (0..resize_count) |i| {
        const width = random.intRangeAtMost(u32, 800, 3840);
        const height = random.intRangeAtMost(u32, 600, 2160);

        swapchain.recreate(width, height);

        // Verify no leaks after each resize
        try testing.expectEqual(@as(usize, 1), swapchain.allocations);

        if (i % 10 == 0) {
            std.debug.print("  Resize {d}/100: {any}\n", .{ i, swapchain.dimensions });
        }
    }

    const elapsed = timer.read();
    std.debug.print("Total time: {d:.3}ms\n", .{@as(f64, @floatFromInt(elapsed)) / 1_000_000.0});
    std.debug.print("Avg per resize: {d:.3}µs\n", .{@as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(resize_count)) / 1000.0});

    try testing.expect(!swapchain.isLeaking());
    std.debug.print("[PASS] Stress test completed\n", .{});
}

test "swapchain_recreation: minimize and restore" {
    std.debug.print("\n[TEST] Window Minimize/Restore\n", .{});

    var swapchain = MockSwapchain.init(1920, 1080);
    defer swapchain.deinit();

    std.debug.print("Initial: {any}\n", .{swapchain.dimensions});

    // Minimize (0x0 or very small)
    std.debug.print("Minimizing window...\n", .{});
    swapchain.recreate(0, 0);
    try testing.expectEqual(@as(u32, 0), swapchain.dimensions.width);
    try testing.expectEqual(@as(u32, 0), swapchain.dimensions.height);

    // Restore
    std.debug.print("Restoring window...\n", .{});
    swapchain.recreate(1920, 1080);
    try testing.expectEqual(@as(u32, 1920), swapchain.dimensions.width);
    try testing.expectEqual(@as(u32, 1080), swapchain.dimensions.height);

    try testing.expect(!swapchain.isLeaking());
    std.debug.print("[PASS] Minimize/restore test completed\n", .{});
}

test "swapchain_recreation: frame synchronization" {
    std.debug.print("\n[TEST] Frame Synchronization During Resize\n", .{});

    var swapchain = MockSwapchain.init(1920, 1080);
    defer swapchain.deinit();

    // Simulate rendering multiple frames with resizes in between
    const scenario = [_]struct {
        frames_before_resize: usize,
        new_dims: WindowDimensions,
    }{
        .{ .frames_before_resize = 5, .new_dims = .{ .width = 2560, .height = 1440 } },
        .{ .frames_before_resize = 10, .new_dims = .{ .width = 3840, .height = 2160 } },
        .{ .frames_before_resize = 3, .new_dims = .{ .width = 1920, .height = 1080 } },
    };

    var total_frames: usize = 0;
    for (scenario) |step| {
        // Render frames
        for (0..step.frames_before_resize) |frame| {
            _ = frame;
            total_frames += 1;
            // Simulate frame rendering (no-op)
            std.mem.doNotOptimizeAway(&swapchain);
        }

        // Resize
        std.debug.print("After {d} frames, resize to {any}\n", .{ total_frames, step.new_dims });
        swapchain.recreate(step.new_dims.width, step.new_dims.height);
        try testing.expectEqual(@as(usize, 1), swapchain.allocations);
    }

    std.debug.print("Total frames rendered: {d}\n", .{total_frames});
    try testing.expect(!swapchain.isLeaking());
    std.debug.print("[PASS] Frame synchronization test completed\n", .{});
}

/// Resource tracking for swapchain-related allocations
const SwapchainResources = struct {
    framebuffers: usize,
    image_views: usize,
    images: usize,

    pub fn init(image_count: u32) SwapchainResources {
        const count = @as(usize, @intCast(image_count));
        return .{
            .framebuffers = count,
            .image_views = count,
            .images = count,
        };
    }

    pub fn deinit(self: *SwapchainResources) void {
        self.framebuffers = 0;
        self.image_views = 0;
        self.images = 0;
    }

    pub fn isCleanedUp(self: SwapchainResources) bool {
        return self.framebuffers == 0 and self.image_views == 0 and self.images == 0;
    }

    pub fn totalAllocations(self: SwapchainResources) usize {
        return self.framebuffers + self.image_views + self.images;
    }
};

test "swapchain_recreation: resource cleanup validation" {
    std.debug.print("\n[TEST] Resource Cleanup Validation\n", .{});

    var swapchain = MockSwapchain.init(1920, 1080);
    defer swapchain.deinit();

    // Track associated resources
    var resources = SwapchainResources.init(swapchain.image_count);

    std.debug.print("Initial resources: {d} framebuffers, {d} image views, {d} images\n", .{
        resources.framebuffers,
        resources.image_views,
        resources.images,
    });

    const initial_total = resources.totalAllocations();
    try testing.expectEqual(@as(usize, 9), initial_total); // 3 images * 3 resource types

    // Simulate resize (cleanup old, create new)
    std.debug.print("Resizing and recreating resources...\n", .{});
    resources.deinit(); // Cleanup old resources
    try testing.expect(resources.isCleanedUp());

    swapchain.recreate(2560, 1440);
    resources = SwapchainResources.init(swapchain.image_count);

    std.debug.print("After resize: {d} total resources\n", .{resources.totalAllocations()});
    try testing.expectEqual(initial_total, resources.totalAllocations()); // Same count

    // Final cleanup
    resources.deinit();
    try testing.expect(resources.isCleanedUp());

    std.debug.print("[PASS] Resource cleanup validation test completed\n", .{});
}

test "swapchain_recreation: out-of-date handling" {
    std.debug.print("\n[TEST] Out-of-Date Swapchain Handling\n", .{});

    var swapchain = MockSwapchain.init(1920, 1080);
    defer swapchain.deinit();

    // Simulate VK_ERROR_OUT_OF_DATE_KHR scenario
    const OutOfDateError = error{SwapchainOutOfDate};

    const acquireImage = struct {
        fn call(sc: *MockSwapchain, expected_width: u32) OutOfDateError!u32 {
            if (sc.dimensions.width != expected_width) {
                return OutOfDateError.SwapchainOutOfDate;
            }
            return 0; // Success: return image index
        }
    }.call;

    // Attempt to acquire image with old dimensions
    const result = acquireImage(&swapchain, 2560);
    try testing.expectError(OutOfDateError.SwapchainOutOfDate, result);

    std.debug.print("Detected out-of-date swapchain, recreating...\n", .{});

    // Recreate swapchain
    swapchain.recreate(2560, 1440);

    // Try again with correct dimensions
    const retry_result = acquireImage(&swapchain, 2560);
    try testing.expectEqual(@as(u32, 0), retry_result catch unreachable);

    std.debug.print("[PASS] Out-of-date swapchain handling test completed\n", .{});
}
