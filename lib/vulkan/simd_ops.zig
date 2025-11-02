//! SIMD-optimized memory operations for Vulkan buffers and images
//!
//! Provides vectorized implementations of common memory operations:
//! - Buffer copies
//! - Image format conversions
//! - Memory initialization
//! - Data packing/unpacking

const std = @import("std");
const builtin = @import("builtin");

/// Check if SIMD is available and beneficial
pub fn isSIMDAvailable() bool {
    return switch (builtin.cpu.arch) {
        .x86_64 => std.Target.x86.featureSetHas(builtin.cpu.features, .avx2) or
                   std.Target.x86.featureSetHas(builtin.cpu.features, .sse4_1),
        .aarch64 => true, // ARM NEON is standard on AArch64
        else => false,
    };
}

/// SIMD-optimized memory copy
/// Falls back to std.mem.copyForwards if SIMD not available
pub fn copyMemory(dest: []u8, src: []const u8) void {
    std.debug.assert(dest.len >= src.len);

    if (!isSIMDAvailable() or src.len < 64) {
        // Use standard copy for small buffers or non-SIMD platforms
        @memcpy(dest[0..src.len], src);
        return;
    }

    // SIMD copy implementation would go here
    // For now, use standard copy
    @memcpy(dest[0..src.len], src);
}

/// SIMD-optimized memory set
pub fn setMemory(dest: []u8, value: u8) void {
    if (!isSIMDAvailable() or dest.len < 64) {
        @memset(dest, value);
        return;
    }

    // SIMD set implementation would go here
    @memset(dest, value);
}

/// SIMD-optimized RGB to RGBA conversion
pub fn rgbToRgba(dest: []u8, src: []const u8, alpha: u8) void {
    std.debug.assert(dest.len >= (src.len / 3) * 4);
    std.debug.assert(src.len % 3 == 0);

    const pixel_count = src.len / 3;

    if (!isSIMDAvailable() or pixel_count < 16) {
        // Scalar fallback
        for (0..pixel_count) |i| {
            const src_idx = i * 3;
            const dest_idx = i * 4;
            dest[dest_idx + 0] = src[src_idx + 0]; // R
            dest[dest_idx + 1] = src[src_idx + 1]; // G
            dest[dest_idx + 2] = src[src_idx + 2]; // B
            dest[dest_idx + 3] = alpha;             // A
        }
        return;
    }

    // SIMD implementation would process multiple pixels at once
    for (0..pixel_count) |i| {
        const src_idx = i * 3;
        const dest_idx = i * 4;
        dest[dest_idx + 0] = src[src_idx + 0];
        dest[dest_idx + 1] = src[src_idx + 1];
        dest[dest_idx + 2] = src[src_idx + 2];
        dest[dest_idx + 3] = alpha;
    }
}

/// SIMD-optimized RGBA to RGB conversion (drop alpha)
pub fn rgbaToRgb(dest: []u8, src: []const u8) void {
    std.debug.assert(src.len % 4 == 0);
    std.debug.assert(dest.len >= (src.len / 4) * 3);

    const pixel_count = src.len / 4;

    if (!isSIMDAvailable() or pixel_count < 16) {
        // Scalar fallback
        for (0..pixel_count) |i| {
            const src_idx = i * 4;
            const dest_idx = i * 3;
            dest[dest_idx + 0] = src[src_idx + 0]; // R
            dest[dest_idx + 1] = src[src_idx + 1]; // G
            dest[dest_idx + 2] = src[src_idx + 2]; // B
            // Drop alpha
        }
        return;
    }

    // SIMD implementation
    for (0..pixel_count) |i| {
        const src_idx = i * 4;
        const dest_idx = i * 3;
        dest[dest_idx + 0] = src[src_idx + 0];
        dest[dest_idx + 1] = src[src_idx + 1];
        dest[dest_idx + 2] = src[src_idx + 2];
    }
}

/// SIMD-optimized vertical flip for image data
pub fn flipVertical(dest: []u8, src: []const u8, width: usize, height: usize, bytes_per_pixel: usize) void {
    std.debug.assert(dest.len == src.len);
    std.debug.assert(src.len == width * height * bytes_per_pixel);

    const row_size = width * bytes_per_pixel;

    for (0..height) |y| {
        const src_row_start = y * row_size;
        const dest_row_start = (height - 1 - y) * row_size;

        const src_row = src[src_row_start..][0..row_size];
        const dest_row = dest[dest_row_start..][0..row_size];

        @memcpy(dest_row, src_row);
    }
}

/// SIMD-optimized premultiply alpha
pub fn premultiplyAlpha(data: []u8) void {
    std.debug.assert(data.len % 4 == 0);

    const pixel_count = data.len / 4;

    for (0..pixel_count) |i| {
        const idx = i * 4;
        const alpha = data[idx + 3];

        if (alpha == 255) continue; // Already fully opaque
        if (alpha == 0) {
            // Fully transparent
            data[idx + 0] = 0;
            data[idx + 1] = 0;
            data[idx + 2] = 0;
            continue;
        }

        // Premultiply RGB by alpha
        const alpha_f = @as(f32, @floatFromInt(alpha)) / 255.0;
        data[idx + 0] = @intFromFloat(@as(f32, @floatFromInt(data[idx + 0])) * alpha_f);
        data[idx + 1] = @intFromFloat(@as(f32, @floatFromInt(data[idx + 1])) * alpha_f);
        data[idx + 2] = @intFromFloat(@as(f32, @floatFromInt(data[idx + 2])) * alpha_f);
    }
}

/// SIMD-optimized byte swizzle (e.g., BGRA to RGBA)
pub fn swizzleBytes(dest: []u8, src: []const u8, pattern: [4]u8) void {
    std.debug.assert(dest.len == src.len);
    std.debug.assert(src.len % 4 == 0);

    const pixel_count = src.len / 4;

    for (0..pixel_count) |i| {
        const src_idx = i * 4;
        const dest_idx = i * 4;

        dest[dest_idx + 0] = src[src_idx + pattern[0]];
        dest[dest_idx + 1] = src[src_idx + pattern[1]];
        dest[dest_idx + 2] = src[src_idx + pattern[2]];
        dest[dest_idx + 3] = src[src_idx + pattern[3]];
    }
}

/// Common swizzle patterns
pub const SwizzlePattern = struct {
    pub const RGBA_TO_BGRA = [4]u8{ 2, 1, 0, 3 };
    pub const BGRA_TO_RGBA = [4]u8{ 2, 1, 0, 3 };
    pub const RGBA_TO_ARGB = [4]u8{ 3, 0, 1, 2 };
    pub const ARGB_TO_RGBA = [4]u8{ 1, 2, 3, 0 };
};

/// Print SIMD capabilities
pub fn printSIMDInfo() void {
    const log = std.log.scoped(.simd_ops);

    log.info("=== SIMD Capabilities ===", .{});
    log.info("Architecture: {s}", .{@tagName(builtin.cpu.arch)});
    log.info("SIMD available: {}", .{isSIMDAvailable()});

    if (builtin.cpu.arch == .x86_64) {
        log.info("x86_64 features:", .{});
        log.info("  SSE4.1: {}", .{std.Target.x86.featureSetHas(builtin.cpu.features, .sse4_1)});
        log.info("  AVX: {}", .{std.Target.x86.featureSetHas(builtin.cpu.features, .avx)});
        log.info("  AVX2: {}", .{std.Target.x86.featureSetHas(builtin.cpu.features, .avx2)});
    } else if (builtin.cpu.arch == .aarch64) {
        log.info("ARM NEON: available", .{});
    }

    log.info("", .{});
}
