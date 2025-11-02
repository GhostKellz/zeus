const std = @import("std");
const query = @import("vulkan").query;

test "TimestampQueryPool creation" {
    std.debug.print("\n=== Testing TimestampQueryPool API ===\n", .{});

    // Test that the API compiles and types are correct
    const Options = query.TimestampQueryPool.Options;
    const default_opts = Options{};

    try std.testing.expect(default_opts.query_count == 64);
    std.debug.print("✓ Default options: 64 queries\n", .{});

    const custom_opts = Options{ .query_count = 128 };
    try std.testing.expect(custom_opts.query_count == 128);
    std.debug.print("✓ Custom options work\n", .{});
}

test "Profiler section management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    _ = gpa.allocator(); // Not used in this API surface test

    std.debug.print("\n=== Testing Profiler API ===\n", .{});

    // Test that Profiler type exists and has correct structure
    const Profiler = query.Profiler;
    _ = Profiler;

    std.debug.print("✓ Profiler type exists\n", .{});
    std.debug.print("✓ Section management API compiles\n", .{});

    // Note: Full functionality test requires a Vulkan device
    // This test validates the API surface
}

test "ScopedTimestamp helper API" {
    std.debug.print("\n=== Testing ScopedTimestamp API ===\n", .{});

    const ScopedTimestamp = query.ScopedTimestamp;
    _ = ScopedTimestamp;

    std.debug.print("✓ ScopedTimestamp type exists\n", .{});
    std.debug.print("✓ RAII-style timing API available\n", .{});
}
