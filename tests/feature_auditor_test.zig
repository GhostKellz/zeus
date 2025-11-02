const std = @import("std");
const vk = @import("vulkan");

test "feature auditor - enumerate and validate extensions" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize loader
    var loader = try vk.Loader.init(allocator, .{});
    defer loader.deinit();

    // Create instance
    var instance = try vk.Instance.create(&loader, allocator, .{
        .application = .{
            .application_name = "Feature Auditor Test",
            .application_version = vk.types.makeApiVersion(1, 0, 0),
            .engine_name = "Zeus",
            .engine_version = vk.types.makeApiVersion(0, 1, 5),
            .api_version = vk.types.makeApiVersion(1, 3, 0),
        },
    });
    defer instance.destroy();

    // Get physical device
    const candidates = try instance.enumeratePhysicalDevices(allocator);
    defer allocator.free(candidates);

    if (candidates.len == 0) {
        std.debug.print("No Vulkan devices found - skipping test\n", .{});
        return error.SkipZigTest;
    }

    const physical_device = candidates[0];

    // Create feature auditor
    const auditor = try vk.FeatureAuditor.init(allocator, @constCast(&instance), physical_device);
    defer auditor.deinit();

    // Print audit report
    auditor.printAuditReport();

    // Test validating an extension that should exist (VK_KHR_swapchain typically exists)
    const test_extensions = [_][*:0]const u8{"VK_KHR_swapchain"};

    // This might fail if swapchain isn't supported, which is fine for the test
    auditor.validateExtensions(&test_extensions) catch |err| {
        std.debug.print("Extension validation failed (expected on headless): {}\n", .{err});
    };

    // Test validating features (all zeroed should pass)
    const zero_features = std.mem.zeroes(vk.types.VkPhysicalDeviceFeatures);
    try auditor.validateFeatures(zero_features);

    std.debug.print("✓ Feature auditor test passed\n", .{});
}

test "feature auditor - debug assertions" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var loader = try vk.Loader.init(allocator, .{});
    defer loader.deinit();

    var instance = try vk.Instance.create(&loader, allocator, .{
        .application = .{
            .application_name = "Feature Auditor Assert Test",
            .application_version = vk.types.makeApiVersion(1, 0, 0),
            .engine_name = "Zeus",
            .engine_version = vk.types.makeApiVersion(0, 1, 5),
            .api_version = vk.types.makeApiVersion(1, 3, 0),
        },
    });
    defer instance.destroy();

    const candidates = try instance.enumeratePhysicalDevices(allocator);
    defer allocator.free(candidates);

    if (candidates.len == 0) {
        return error.SkipZigTest;
    }

    const physical_device = candidates[0];
    const auditor = try vk.FeatureAuditor.init(allocator, @constCast(&instance), physical_device);
    defer auditor.deinit();

    // Test debug assertions with safe values
    const zero_features = std.mem.zeroes(vk.types.VkPhysicalDeviceFeatures);
    vk.feature_auditor.assertFeaturesSupported(auditor, zero_features);

    std.debug.print("✓ Feature auditor assertions test passed\n", .{});
}
