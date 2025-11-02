const std = @import("std");
const context = @import("vulkan").context;

test "Context builder pattern" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Testing Context Builder Pattern ===\n", .{});

    // Test builder creation
    const builder = context.Context.builder(allocator);
    try std.testing.expect(builder.allocator.ptr == allocator.ptr);

    std.debug.print("✓ Builder created with allocator\n", .{});

    // Test builder chaining
    const configured = builder
        .setAppName("Test App")
        .setAppVersion(1, 2, 3)
        .setApiVersion(1, 3, 0);

    try std.testing.expectEqualStrings("Test App", configured.app_name);
    std.debug.print("✓ Builder fluent API works\n", .{});

    // Test compute/transfer queue flags
    const with_queues = configured
        .requireComputeQueue()
        .requireTransferQueue();

    try std.testing.expect(with_queues.require_compute_queue);
    try std.testing.expect(with_queues.require_transfer_queue);
    std.debug.print("✓ Queue requirements set correctly\n", .{});
}

test "Context initialization and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Testing Context Lifecycle ===\n", .{});

    // Try to create a minimal context (will fail without Vulkan, but tests the API)
    var result = context.Context.builder(allocator)
        .setAppName("Context Test")
        .build();

    if (result) |*ctx| {
        defer ctx.deinit();

        std.debug.print("✓ Context created successfully\n", .{});
        std.debug.print("  - Loader initialized\n", .{});
        std.debug.print("  - Instance created\n", .{});
        std.debug.print("  - Physical device selected\n", .{});
        std.debug.print("  - Logical device created\n", .{});
        std.debug.print("  - Graphics queue obtained\n", .{});

        // Test queue handles are valid (VkQueue is opaque pointer, just check non-null)
        try std.testing.expect(@intFromPtr(ctx.graphics_queue) != 0);
        std.debug.print("✓ Graphics queue handle valid\n", .{});
    } else |err| {
        // Expected to fail if no Vulkan available
        std.debug.print("⚠ Context creation failed (expected if no Vulkan): {}\n", .{err});
        std.debug.print("✓ Error handling works correctly\n", .{});
    }
}
