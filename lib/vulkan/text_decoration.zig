//! Text decoration rendering (underlines, strikethroughs, backgrounds)
//!
//! This module provides utilities for rendering text decorations that complement
//! glyph rendering. These are typically rendered as simple quads before or after
//! text rendering.

const std = @import("std");
const types = @import("types.zig");

/// Decoration type
pub const DecorationType = enum {
    underline,
    strikethrough,
    double_underline,
    wavy_underline,
    dotted_underline,
    dashed_underline,
    background,
    overline,
};

/// Decoration style
pub const DecorationStyle = struct {
    decoration_type: DecorationType,
    color: [4]f32, // RGBA
    thickness: f32,
    offset_y: f32, // Relative to baseline
};

/// Rectangle for decoration rendering
pub const DecorationRect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    color: [4]f32,

    /// Convert to a simple quad that can be rendered
    pub fn toQuad(self: DecorationRect) TextureQuad {
        return .{
            .position = .{ self.x, self.y },
            .size = .{ self.width, self.height },
            .atlas_rect = .{ 0.0, 0.0, 0.0, 0.0 }, // No texture
            .color = self.color,
        };
    }
};

/// Quad for rendering (compatible with TextRenderer)
pub const TextureQuad = extern struct {
    position: [2]f32,
    size: [2]f32,
    atlas_rect: [4]f32,
    color: [4]f32,
};

/// Generate underline rectangle
pub fn generateUnderline(
    x: f32,
    _: f32,
    width: f32,
    baseline: f32,
    style: DecorationStyle,
) DecorationRect {
    const underline_y = baseline + style.offset_y;
    return .{
        .x = x,
        .y = underline_y,
        .width = width,
        .height = style.thickness,
        .color = style.color,
    };
}

/// Generate strikethrough rectangle
pub fn generateStrikethrough(
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    style: DecorationStyle,
) DecorationRect {
    // Strikethrough is typically at mid-height
    const strikethrough_y = y + (height * 0.5) + style.offset_y;
    return .{
        .x = x,
        .y = strikethrough_y,
        .width = width,
        .height = style.thickness,
        .color = style.color,
    };
}

/// Generate double underline rectangles
pub fn generateDoubleUnderline(
    x: f32,
    _: f32,
    width: f32,
    baseline: f32,
    style: DecorationStyle,
    allocator: std.mem.Allocator,
) ![]DecorationRect {
    const rects = try allocator.alloc(DecorationRect, 2);

    const spacing = style.thickness * 2.0;
    const base_y = baseline + style.offset_y;

    // First line
    rects[0] = .{
        .x = x,
        .y = base_y,
        .width = width,
        .height = style.thickness,
        .color = style.color,
    };

    // Second line
    rects[1] = .{
        .x = x,
        .y = base_y + spacing,
        .width = width,
        .height = style.thickness,
        .color = style.color,
    };

    return rects;
}

/// Generate background rectangle
pub fn generateBackground(
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    color: [4]f32,
) DecorationRect {
    return .{
        .x = x,
        .y = y,
        .width = width,
        .height = height,
        .color = color,
    };
}

/// Generate wavy underline (approximated with multiple small rectangles)
pub fn generateWavyUnderline(
    x: f32,
    _: f32,
    width: f32,
    baseline: f32,
    style: DecorationStyle,
    allocator: std.mem.Allocator,
) ![]DecorationRect {
    const wave_length = 4.0; // pixels per wave
    const wave_amplitude = style.thickness * 1.5;
    const segments = @as(usize, @intFromFloat(@ceil(width / wave_length)));

    const rects = try allocator.alloc(DecorationRect, segments);

    for (0..segments) |i| {
        const segment_x = x + @as(f32, @floatFromInt(i)) * wave_length;
        const segment_width = @min(wave_length, width - @as(f32, @floatFromInt(i)) * wave_length);

        // Simple sine wave approximation
        const phase = @as(f32, @floatFromInt(i)) * std.math.pi / 2.0;
        const wave_offset = @sin(phase) * wave_amplitude;

        rects[i] = .{
            .x = segment_x,
            .y = baseline + style.offset_y + wave_offset,
            .width = segment_width,
            .height = style.thickness,
            .color = style.color,
        };
    }

    return rects;
}

/// Generate dotted underline
pub fn generateDottedUnderline(
    x: f32,
    _: f32,
    width: f32,
    baseline: f32,
    style: DecorationStyle,
    allocator: std.mem.Allocator,
) ![]DecorationRect {
    const dot_width = style.thickness * 2.0;
    const dot_spacing = dot_width * 1.5;
    const total_dots = @as(usize, @intFromFloat(@ceil(width / (dot_width + dot_spacing))));

    const rects = try allocator.alloc(DecorationRect, total_dots);

    for (0..total_dots) |i| {
        const dot_x = x + @as(f32, @floatFromInt(i)) * (dot_width + dot_spacing);

        rects[i] = .{
            .x = dot_x,
            .y = baseline + style.offset_y,
            .width = dot_width,
            .height = style.thickness,
            .color = style.color,
        };
    }

    return rects;
}

/// Generate dashed underline
pub fn generateDashedUnderline(
    x: f32,
    _: f32,
    width: f32,
    baseline: f32,
    style: DecorationStyle,
    allocator: std.mem.Allocator,
) ![]DecorationRect {
    const dash_width = style.thickness * 6.0;
    const dash_spacing = style.thickness * 3.0;
    const total_dashes = @as(usize, @intFromFloat(@ceil(width / (dash_width + dash_spacing))));

    const rects = try allocator.alloc(DecorationRect, total_dashes);

    for (0..total_dashes) |i| {
        const dash_x = x + @as(f32, @floatFromInt(i)) * (dash_width + dash_spacing);
        const actual_width = @min(dash_width, width - (dash_x - x));

        rects[i] = .{
            .x = dash_x,
            .y = baseline + style.offset_y,
            .width = actual_width,
            .height = style.thickness,
            .color = style.color,
        };
    }

    return rects;
}

// Tests
test "generateUnderline creates correct rectangle" {
    const style = DecorationStyle{
        .decoration_type = .underline,
        .color = .{ 1.0, 1.0, 1.0, 1.0 },
        .thickness = 2.0,
        .offset_y = 2.0,
    };

    const rect = generateUnderline(10.0, 20.0, 100.0, 50.0, style);

    try std.testing.expectEqual(@as(f32, 10.0), rect.x);
    try std.testing.expectEqual(@as(f32, 52.0), rect.y); // baseline + offset
    try std.testing.expectEqual(@as(f32, 100.0), rect.width);
    try std.testing.expectEqual(@as(f32, 2.0), rect.height);
}

test "generateStrikethrough positions at mid-height" {
    const style = DecorationStyle{
        .decoration_type = .strikethrough,
        .color = .{ 1.0, 0.0, 0.0, 1.0 },
        .thickness = 1.5,
        .offset_y = 0.0,
    };

    const rect = generateStrikethrough(0.0, 0.0, 50.0, 20.0, style);

    try std.testing.expectEqual(@as(f32, 10.0), rect.y); // mid-height of 20px
    try std.testing.expectEqual(@as(f32, 1.5), rect.height);
}

test "generateBackground creates full-size rect" {
    const rect = generateBackground(5.0, 10.0, 100.0, 20.0, .{ 0.2, 0.2, 0.2, 1.0 });

    try std.testing.expectEqual(@as(f32, 5.0), rect.x);
    try std.testing.expectEqual(@as(f32, 10.0), rect.y);
    try std.testing.expectEqual(@as(f32, 100.0), rect.width);
    try std.testing.expectEqual(@as(f32, 20.0), rect.height);
}

test "generateDoubleUnderline creates two lines" {
    const allocator = std.testing.allocator;

    const style = DecorationStyle{
        .decoration_type = .double_underline,
        .color = .{ 1.0, 1.0, 1.0, 1.0 },
        .thickness = 1.0,
        .offset_y = 0.0,
    };

    const rects = try generateDoubleUnderline(0.0, 0.0, 100.0, 20.0, style, allocator);
    defer allocator.free(rects);

    try std.testing.expectEqual(@as(usize, 2), rects.len);
    try std.testing.expect(rects[1].y > rects[0].y); // Second line below first
}

test "DecorationRect.toQuad converts correctly" {
    const rect = DecorationRect{
        .x = 10.0,
        .y = 20.0,
        .width = 100.0,
        .height = 2.0,
        .color = .{ 1.0, 0.0, 0.0, 1.0 },
    };

    const quad = rect.toQuad();

    try std.testing.expectEqual(@as(f32, 10.0), quad.position[0]);
    try std.testing.expectEqual(@as(f32, 20.0), quad.position[1]);
    try std.testing.expectEqual(@as(f32, 100.0), quad.size[0]);
    try std.testing.expectEqual(@as(f32, 2.0), quad.size[1]);
}
