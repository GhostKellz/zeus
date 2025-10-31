//! Simple text rendering example
//!
//! Demonstrates Zeus text rendering API with minimal setup.
//! Renders "Hello, Zeus!" in white text on black background.

const std = @import("std");
const zeus = @import("zeus");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Zeus Simple Text Example\n", .{});
    std.debug.print("=========================\n\n", .{});

    // TODO: Phase 6 - Complete this example
    // For now, this is a placeholder showing the intended API

    std.debug.print("Zeus TextRenderer API Preview:\n\n", .{});
    std.debug.print("1. Create Vulkan instance\n", .{});
    std.debug.print("   const instance = try zeus.Instance.init(allocator, .{{}});\n\n", .{});

    std.debug.print("2. Select physical device (GPU)\n", .{});
    std.debug.print("   const physical_device = try zeus.PhysicalDevice.select(instance, surface);\n\n", .{});

    std.debug.print("3. Create logical device\n", .{});
    std.debug.print("   const device = try zeus.Device.init(allocator, physical_device, .{{}});\n\n", .{});

    std.debug.print("4. Create text renderer\n", .{});
    std.debug.print("   var renderer = try zeus.TextRenderer.init(allocator, device, .{{\n", .{});
    std.debug.print("       .extent = .{{ .width = 1920, .height = 1080 }},\n", .{});
    std.debug.print("       .max_instances = 1000,\n", .{});
    std.debug.print("   }});\n\n", .{});

    std.debug.print("5. Render frame\n", .{});
    std.debug.print("   try renderer.beginFrame(frame_index);\n", .{});
    std.debug.print("   try renderer.queueQuad(.{{\n", .{});
    std.debug.print("       .position = .{{ 100, 100 }},\n", .{});
    std.debug.print("       .size = .{{ 16, 24 }},\n", .{});
    std.debug.print("       .atlas_rect = .{{ 0, 0, 0.1, 0.1 }},\n", .{});
    std.debug.print("       .color = .{{ 1, 1, 1, 1 }},\n", .{});
    std.debug.print("   }});\n", .{});
    std.debug.print("   try renderer.encode(cmd_buffer, frame_index);\n", .{});
    std.debug.print("   renderer.endFrame();\n\n", .{});

    std.debug.print("This example will be completed in Phase 6.\n", .{});
    std.debug.print("Stay tuned!\n", .{});
}
