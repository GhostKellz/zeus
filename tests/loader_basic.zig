const std = @import("std");
const vk = @import("vulkan");

test "loader can initialize and load Vulkan library" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Testing Vulkan Loader Initialization ===\n", .{});

    var loader = vk.loader.Loader.init(allocator, .{}) catch |err| {
        std.debug.print("FAILED to init loader: {}\n", .{err});
        return err;
    };
    defer loader.deinit();

    std.debug.print("✓ Loader initialized successfully\n", .{});

    // Verify library was loaded
    try std.testing.expect(loader.lib != null);
    std.debug.print("✓ Vulkan library loaded\n", .{});

    // Verify get proc addresses are populated
    try std.testing.expect(loader.get_instance_proc != null);
    try std.testing.expect(loader.get_device_proc != null);
    std.debug.print("✓ vkGetInstanceProcAddr and vkGetDeviceProcAddr loaded\n", .{});
}

test "loader can obtain global dispatch table" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Testing Global Dispatch Table ===\n", .{});

    var loader = vk.loader.Loader.init(allocator, .{}) catch |err| {
        std.debug.print("FAILED to init loader: {}\n", .{err});
        return err;
    };
    defer loader.deinit();

    const global = loader.global() catch |err| {
        std.debug.print("FAILED to get global dispatch: {}\n", .{err});
        return err;
    };

    std.debug.print("✓ Global dispatch table obtained\n", .{});

    // Verify all global function pointers are non-null
    try std.testing.expect(global.create_instance != null);
    try std.testing.expect(global.enumerate_instance_extension_properties != null);
    try std.testing.expect(global.enumerate_instance_layer_properties != null);

    std.debug.print("✓ All global function pointers valid:\n", .{});
    std.debug.print("  - vkCreateInstance: {*}\n", .{global.create_instance});
    std.debug.print("  - vkEnumerateInstanceExtensionProperties: {*}\n", .{global.enumerate_instance_extension_properties});
    std.debug.print("  - vkEnumerateInstanceLayerProperties: {*}\n", .{global.enumerate_instance_layer_properties});
}

test "loader reports error for missing library" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Testing Missing Library Error Handling ===\n", .{});

    const result = vk.loader.Loader.init(allocator, .{
        .search_paths = &.{"/__nonexistent__/libvulkan.so.999"},
    });

    try std.testing.expectError(vk.errors.Error.LibraryNotFound, result);
    std.debug.print("✓ Correctly reports LibraryNotFound for missing library\n", .{});
}

test "loader cleanup is idempotent" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Testing Loader Cleanup ===\n", .{});

    var loader = vk.loader.Loader.init(allocator, .{}) catch |err| {
        std.debug.print("FAILED to init loader: {}\n", .{err});
        return err;
    };

    // Call deinit multiple times - should be safe
    loader.deinit();
    loader.deinit();
    loader.deinit();

    std.debug.print("✓ Multiple deinit() calls handled safely\n", .{});
}
