//! Safe defaults mode for overlay/layer compatibility
//!
//! When ZEUS_SAFE_OVERLAY=1 is set, uses conservative settings that are
//! compatible with overlay layers like MangoHud:
//! - Forces FIFO present mode (vsync)
//! - Forces B8G8R8A8_SRGB swapchain format
//! - Disables HDR metadata
//! - Disables dynamic rendering
//! - Uses most conservative feature/extension sets

const std = @import("std");
const types = @import("types.zig");

const log = std.log.scoped(.safe_defaults);

/// Check if safe overlay mode is enabled via environment variable
pub fn isEnabled() bool {
    const env_value = std.process.getEnvVarOwned(std.heap.page_allocator, "ZEUS_SAFE_OVERLAY") catch return false;
    defer std.heap.page_allocator.free(env_value);

    return std.mem.eql(u8, env_value, "1") or
           std.mem.eql(u8, env_value, "true") or
           std.mem.eql(u8, env_value, "TRUE");
}

/// Safe overlay configuration
pub const SafeConfig = struct {
    enabled: bool,

    pub fn init() SafeConfig {
        const enabled = isEnabled();
        if (enabled) {
            log.info("=== ZEUS SAFE OVERLAY MODE ENABLED ===", .{});
            log.info("Using conservative settings for overlay compatibility", .{});
            log.info("- FIFO present mode (vsync)", .{});
            log.info("- B8G8R8A8_SRGB format", .{});
            log.info("- HDR disabled", .{});
            log.info("- Dynamic rendering disabled", .{});
        }
        return .{ .enabled = enabled };
    }

    /// Get safe present mode (always FIFO for overlay compatibility)
    pub fn getPresentMode(self: SafeConfig, requested: types.VkPresentModeKHR) types.VkPresentModeKHR {
        if (self.enabled) {
            if (requested != .FIFO_KHR) {
                log.warn("Overriding present mode {} -> FIFO_KHR for overlay compatibility", .{requested});
            }
            return .FIFO_KHR;
        }
        return requested;
    }

    /// Get safe surface format (B8G8R8A8_SRGB for overlay compatibility)
    pub fn getSurfaceFormat(self: SafeConfig, requested: types.VkSurfaceFormatKHR) types.VkSurfaceFormatKHR {
        if (self.enabled) {
            const safe_format = types.VkSurfaceFormatKHR{
                .format = .B8G8R8A8_SRGB,
                .colorSpace = .SRGB_NONLINEAR_KHR,
            };

            if (requested.format != safe_format.format or requested.colorSpace != safe_format.colorSpace) {
                log.warn("Overriding surface format for overlay compatibility", .{});
                log.warn("  Requested: format={} colorSpace={}", .{requested.format, requested.colorSpace});
                log.warn("  Using: format={} colorSpace={}", .{safe_format.format, safe_format.colorSpace});
            }

            return safe_format;
        }
        return requested;
    }

    /// Check if HDR should be disabled
    pub fn shouldDisableHDR(self: SafeConfig) bool {
        return self.enabled;
    }

    /// Check if dynamic rendering should be disabled
    pub fn shouldDisableDynamicRendering(self: SafeConfig) bool {
        return self.enabled;
    }

    /// Filter device extensions to remove ones that may cause overlay issues
    pub fn filterDeviceExtensions(
        self: SafeConfig,
        allocator: std.mem.Allocator,
        requested: []const [*:0]const u8,
    ) ![]const [*:0]const u8 {
        if (!self.enabled) {
            return requested;
        }

        // Extensions to exclude in safe mode
        const excluded_extensions = [_][]const u8{
            "VK_EXT_hdr_metadata",
            "VK_KHR_dynamic_rendering",
            "VK_AMD_display_native_hdr",
            "VK_EXT_swapchain_colorspace",
        };

        var filtered = std.ArrayList([*:0]const u8).init(allocator);
        errdefer filtered.deinit();

        for (requested) |ext_ptr| {
            const ext_name = std.mem.sliceTo(ext_ptr, 0);

            var should_exclude = false;
            for (excluded_extensions) |excluded| {
                if (std.mem.eql(u8, ext_name, excluded)) {
                    log.warn("Excluding extension for overlay compatibility: {s}", .{ext_name});
                    should_exclude = true;
                    break;
                }
            }

            if (!should_exclude) {
                try filtered.append(ext_ptr);
            }
        }

        return filtered.toOwnedSlice();
    }

    /// Sanitize physical device features to disable problematic ones
    pub fn sanitizeFeatures(
        self: SafeConfig,
        features: *types.VkPhysicalDeviceFeatures,
    ) void {
        if (!self.enabled) return;

        // Disable features that might cause issues with overlays
        // Most overlays handle standard features fine, but exotic ones can cause problems

        // Log if we're disabling anything that was enabled
        if (features.robustBufferAccess != 0) {
            log.debug("Keeping robustBufferAccess for safety", .{});
        }

        // We generally keep most features enabled unless they're known problematic
        // This is intentionally conservative
    }

    /// Print current configuration
    pub fn printConfig(self: SafeConfig) void {
        if (!self.enabled) {
            log.debug("Safe overlay mode: DISABLED", .{});
            return;
        }

        log.info("", .{});
        log.info("╔══════════════════════════════════════╗", .{});
        log.info("║  ZEUS SAFE OVERLAY MODE ACTIVE      ║", .{});
        log.info("╚══════════════════════════════════════╝", .{});
        log.info("Present Mode: FIFO_KHR (vsync)", .{});
        log.info("Surface Format: B8G8R8A8_SRGB", .{});
        log.info("Color Space: SRGB_NONLINEAR_KHR", .{});
        log.info("HDR: Disabled", .{});
        log.info("Dynamic Rendering: Disabled", .{});
        log.info("", .{});
        log.info("Note: These settings maximize compatibility with", .{});
        log.info("overlay layers like MangoHud, OBS, and Discord.", .{});
        log.info("", .{});
    }
};

/// Global safe config instance (initialized on first access)
var global_config: ?SafeConfig = null;

/// Get global safe config (initializes on first call)
pub fn getGlobalConfig() SafeConfig {
    if (global_config == null) {
        global_config = SafeConfig.init();
    }
    return global_config.?;
}
