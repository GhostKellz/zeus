//! MangoHud detection and compatibility warnings
//!
//! Detects if MangoHud or other overlays are active and provides
//! recommendations for compatibility

const std = @import("std");

const log = std.log.scoped(.mangohud_detect);

/// Detected overlay type
pub const OverlayType = enum {
    none,
    mangohud,
    vkbasalt,
    obs_vulkan,
    reshade,
    unknown,
};

/// Overlay detection result
pub const OverlayDetection = struct {
    detected: bool,
    overlay_type: OverlayType,
    env_vars: []const []const u8,

    pub fn deinit(self: *OverlayDetection, allocator: std.mem.Allocator) void {
        for (self.env_vars) |env_var| {
            allocator.free(env_var);
        }
        allocator.free(self.env_vars);
    }
};

/// Detect active Vulkan overlays/layers
pub fn detectOverlays(allocator: std.mem.Allocator) !OverlayDetection {
    var detected = false;
    var overlay_type = OverlayType.none;
    var env_vars = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (env_vars.items) |item| allocator.free(item);
        env_vars.deinit();
    }

    // Check for MangoHud
    if (std.process.hasEnvVar(allocator, "MANGOHUD")) {
        const value = try std.process.getEnvVarOwned(allocator, "MANGOHUD");
        detected = true;
        overlay_type = .mangohud;
        try env_vars.append(try std.fmt.allocPrint(allocator, "MANGOHUD={s}", .{value}));
        allocator.free(value);
    }

    if (std.process.hasEnvVar(allocator, "MANGOHUD_CONFIG")) {
        const value = try std.process.getEnvVarOwned(allocator, "MANGOHUD_CONFIG");
        detected = true;
        if (overlay_type == .none) overlay_type = .mangohud;
        try env_vars.append(try std.fmt.allocPrint(allocator, "MANGOHUD_CONFIG={s}", .{value}));
        allocator.free(value);
    }

    // Check for vkBasalt
    if (std.process.hasEnvVar(allocator, "ENABLE_VKBASALT")) {
        const value = try std.process.getEnvVarOwned(allocator, "ENABLE_VKBASALT");
        detected = true;
        if (overlay_type == .none) overlay_type = .vkbasalt;
        try env_vars.append(try std.fmt.allocPrint(allocator, "ENABLE_VKBASALT={s}", .{value}));
        allocator.free(value);
    }

    // Check for OBS Vulkan capture
    if (std.process.hasEnvVar(allocator, "OBS_VKCAPTURE")) {
        const value = try std.process.getEnvVarOwned(allocator, "OBS_VKCAPTURE");
        detected = true;
        if (overlay_type == .none) overlay_type = .obs_vulkan;
        try env_vars.append(try std.fmt.allocPrint(allocator, "OBS_VKCAPTURE={s}", .{value}));
        allocator.free(value);
    }

    // Check for generic Vulkan layers
    if (std.process.hasEnvVar(allocator, "VK_INSTANCE_LAYERS")) {
        const value = try std.process.getEnvVarOwned(allocator, "VK_INSTANCE_LAYERS");
        detected = true;
        if (overlay_type == .none) overlay_type = .unknown;
        try env_vars.append(try std.fmt.allocPrint(allocator, "VK_INSTANCE_LAYERS={s}", .{value}));
        allocator.free(value);
    }

    return OverlayDetection{
        .detected = detected,
        .overlay_type = overlay_type,
        .env_vars = try env_vars.toOwnedSlice(),
    };
}

/// Print overlay detection results and recommendations
pub fn printOverlayDetection(detection: OverlayDetection) void {
    if (!detection.detected) {
        log.debug("No overlay layers detected", .{});
        return;
    }

    log.warn("", .{});
    log.warn("╔══════════════════════════════════════════╗", .{});
    log.warn("║  VULKAN OVERLAY LAYER DETECTED          ║", .{});
    log.warn("╚══════════════════════════════════════════╝", .{});

    const overlay_name = switch (detection.overlay_type) {
        .mangohud => "MangoHud",
        .vkbasalt => "vkBasalt",
        .obs_vulkan => "OBS Vulkan Capture",
        .reshade => "ReShade",
        .unknown => "Unknown Layer",
        .none => "None",
    };

    log.warn("Detected: {s}", .{overlay_name});
    log.warn("", .{});
    log.warn("Environment variables:", .{});
    for (detection.env_vars) |env_var| {
        log.warn("  {s}", .{env_var});
    }
    log.warn("", .{});

    // Provide recommendations
    if (detection.overlay_type == .mangohud) {
        log.warn("MangoHud Compatibility Recommendations:", .{});
        log.warn("  1. If experiencing crashes, set: ZEUS_SAFE_OVERLAY=1", .{});
        log.warn("  2. Use FIFO present mode (vsync)", .{});
        log.warn("  3. Avoid HDR/extended colorspaces", .{});
        log.warn("  4. Disable dynamic rendering", .{});
        log.warn("", .{});
        log.warn("To disable MangoHud: unset MANGOHUD and MANGOHUD_CONFIG", .{});
    }

    log.warn("", .{});
}

/// Check and warn about overlays at startup
pub fn checkAndWarnOverlays(allocator: std.mem.Allocator) void {
    var detection = detectOverlays(allocator) catch {
        log.debug("Failed to detect overlays", .{});
        return;
    };
    defer detection.deinit(allocator);

    printOverlayDetection(detection);
}
