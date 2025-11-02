//! HDR support with VK_EXT_hdr_metadata for OLED displays

const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const swapchain_mod = @import("swapchain.zig");
const instance_mod = @import("instance.zig");

const log = std.log.scoped(.hdr_support);

/// HDR metadata for displays (BT.2020 primaries)
pub const HDRMetadata = struct {
    // Display mastering metadata
    display_primary_red: [2]f32,
    display_primary_green: [2]f32,
    display_primary_blue: [2]f32,
    white_point: [2]f32,
    max_luminance: f32, // nits
    min_luminance: f32, // nits

    // Content light level
    max_content_light_level: f32, // nits
    max_frame_average_light_level: f32, // nits

    /// Standard HDR10 metadata (BT.2020 primaries)
    pub fn hdr10() HDRMetadata {
        return .{
            // BT.2020 primaries
            .display_primary_red = .{ 0.708, 0.292 },
            .display_primary_green = .{ 0.170, 0.797 },
            .display_primary_blue = .{ 0.131, 0.046 },
            .white_point = .{ 0.3127, 0.3290 }, // D65

            // Display capabilities (typical OLED)
            .max_luminance = 1000.0,
            .min_luminance = 0.0001,

            // Content metadata (conservative defaults)
            .max_content_light_level = 1000.0,
            .max_frame_average_light_level = 400.0,
        };
    }

    /// High-end OLED metadata (for displays like LG C2/C3, Samsung S95B)
    pub fn highEndOLED() HDRMetadata {
        return .{
            .display_primary_red = .{ 0.708, 0.292 },
            .display_primary_green = .{ 0.170, 0.797 },
            .display_primary_blue = .{ 0.131, 0.046 },
            .white_point = .{ 0.3127, 0.3290 },

            // High-end OLED capabilities
            .max_luminance = 1500.0, // Peak brightness
            .min_luminance = 0.00005, // Near perfect blacks

            .max_content_light_level = 1500.0,
            .max_frame_average_light_level = 600.0,
        };
    }

    /// Convert to Vulkan HDR metadata
    pub fn toVulkan(self: HDRMetadata) types.VkHdrMetadataEXT {
        return .{
            .sType = .HDR_METADATA_EXT,
            .pNext = null,
            .displayPrimaryRed = .{ .x = self.display_primary_red[0], .y = self.display_primary_red[1] },
            .displayPrimaryGreen = .{ .x = self.display_primary_green[0], .y = self.display_primary_green[1] },
            .displayPrimaryBlue = .{ .x = self.display_primary_blue[0], .y = self.display_primary_blue[1] },
            .whitePoint = .{ .x = self.white_point[0], .y = self.white_point[1] },
            .maxLuminance = self.max_luminance,
            .minLuminance = self.min_luminance,
            .maxContentLightLevel = self.max_content_light_level,
            .maxFrameAverageLightLevel = self.max_frame_average_light_level,
        };
    }
};

/// HDR color space and format support
pub const HDRColorSpace = enum {
    srgb_nonlinear, // SDR
    extended_srgb_linear, // scRGB (linear extended sRGB)
    hdr10_st2084, // HDR10 (PQ/SMPTE ST 2084)
    hdr10_hlg, // Hybrid Log-Gamma
    dolby_vision, // Dolby Vision

    pub fn toVulkan(self: HDRColorSpace) types.VkColorSpaceKHR {
        return switch (self) {
            .srgb_nonlinear => .SRGB_NONLINEAR,
            .extended_srgb_linear => .EXTENDED_SRGB_LINEAR_EXT,
            .hdr10_st2084 => .HDR10_ST2084_EXT,
            .hdr10_hlg => .HDR10_HLG_EXT,
            .dolby_vision => .DOLBY_VISION_EXT,
        };
    }
};

/// HDR surface format configuration
pub const HDRSurfaceFormat = struct {
    format: types.VkFormat,
    color_space: HDRColorSpace,

    /// HDR10 format (10-bit ABGR with PQ transfer)
    pub fn hdr10() HDRSurfaceFormat {
        return .{
            .format = .A2B10G10R10_UNORM_PACK32,
            .color_space = .hdr10_st2084,
        };
    }

    /// Extended sRGB (16-bit float linear)
    pub fn extendedSRGB() HDRSurfaceFormat {
        return .{
            .format = .R16G16B16A16_SFLOAT,
            .color_space = .extended_srgb_linear,
        };
    }

    /// Standard SDR fallback
    pub fn sdr() HDRSurfaceFormat {
        return .{
            .format = .B8G8R8A8_SRGB,
            .color_space = .srgb_nonlinear,
        };
    }

    pub fn toVulkanSurfaceFormat(self: HDRSurfaceFormat) types.VkSurfaceFormatKHR {
        return .{
            .format = self.format,
            .colorSpace = self.color_space.toVulkan(),
        };
    }
};

/// HDR capability detection and management
pub const HDRSupport = struct {
    allocator: std.mem.Allocator,
    instance: *instance_mod.Instance,
    device: *device_mod.Device,
    has_hdr_metadata_ext: bool,
    has_swapchain_colorspace_ext: bool,
    supported_formats: std.ArrayList(types.VkSurfaceFormatKHR),

    pub fn init(
        allocator: std.mem.Allocator,
        instance: *instance_mod.Instance,
        device: *device_mod.Device,
    ) !*HDRSupport {
        const self = try allocator.create(HDRSupport);
        self.* = .{
            .allocator = allocator,
            .instance = instance,
            .device = device,
            .has_hdr_metadata_ext = false,
            .has_swapchain_colorspace_ext = false,
            .supported_formats = std.ArrayList(types.VkSurfaceFormatKHR).init(allocator),
        };

        try self.detectCapabilities();

        return self;
    }

    pub fn deinit(self: *HDRSupport) void {
        self.supported_formats.deinit();
        self.allocator.destroy(self);
    }

    /// Detect HDR capabilities
    fn detectCapabilities(self: *HDRSupport) !void {
        // Check for VK_EXT_hdr_metadata
        self.has_hdr_metadata_ext = self.device.hasExtension("VK_EXT_hdr_metadata");

        // Check for VK_EXT_swapchain_colorspace
        self.has_swapchain_colorspace_ext = self.device.hasExtension("VK_EXT_swapchain_colorspace");

        log.info("HDR capabilities: metadata={}, colorspace={}", .{
            self.has_hdr_metadata_ext,
            self.has_swapchain_colorspace_ext,
        });
    }

    /// Query supported HDR surface formats for a surface
    pub fn querySurfaceFormats(
        self: *HDRSupport,
        physical_device: types.VkPhysicalDevice,
        surface: types.VkSurfaceKHR,
    ) ![]types.VkSurfaceFormatKHR {
        self.supported_formats.clearRetainingCapacity();

        var format_count: u32 = 0;
        _ = self.instance.dispatch.get_physical_device_surface_formats_khr(
            physical_device,
            surface,
            &format_count,
            null,
        );

        if (format_count == 0) {
            return &[_]types.VkSurfaceFormatKHR{};
        }

        try self.supported_formats.resize(format_count);
        _ = self.instance.dispatch.get_physical_device_surface_formats_khr(
            physical_device,
            surface,
            &format_count,
            self.supported_formats.items.ptr,
        );

        log.debug("Found {} surface formats", .{format_count});
        for (self.supported_formats.items) |fmt| {
            log.debug("  Format: {}, ColorSpace: {}", .{ fmt.format, fmt.colorSpace });
        }

        return self.supported_formats.items;
    }

    /// Check if a specific HDR format is supported
    pub fn supportsFormat(self: *HDRSupport, desired: HDRSurfaceFormat) bool {
        const vk_format = desired.toVulkanSurfaceFormat();

        for (self.supported_formats.items) |fmt| {
            if (fmt.format == vk_format.format and fmt.colorSpace == vk_format.colorSpace) {
                return true;
            }
        }

        return false;
    }

    /// Select best available HDR format
    pub fn selectBestFormat(self: *HDRSupport) HDRSurfaceFormat {
        // Prefer HDR10 if available
        if (self.supportsFormat(HDRSurfaceFormat.hdr10())) {
            log.info("Using HDR10 format", .{});
            return HDRSurfaceFormat.hdr10();
        }

        // Fallback to extended sRGB
        if (self.supportsFormat(HDRSurfaceFormat.extendedSRGB())) {
            log.info("Using extended sRGB format", .{});
            return HDRSurfaceFormat.extendedSRGB();
        }

        // SDR fallback
        log.info("HDR not available, using SDR", .{});
        return HDRSurfaceFormat.sdr();
    }

    /// Set HDR metadata for swapchain
    pub fn setMetadata(
        self: *HDRSupport,
        swapchain: types.VkSwapchainKHR,
        metadata: HDRMetadata,
    ) !void {
        if (!self.has_hdr_metadata_ext) {
            log.warn("VK_EXT_hdr_metadata not available, skipping", .{});
            return;
        }

        const vk_metadata = metadata.toVulkan();
        const swapchains = [_]types.VkSwapchainKHR{swapchain};
        const metadatas = [_]types.VkHdrMetadataEXT{vk_metadata};

        self.device.dispatch.set_hdr_metadata_ext(
            self.device.handle.?,
            1,
            &swapchains,
            &metadatas,
        );

        log.info("Set HDR metadata: maxLum={d:.1} nits, minLum={d:.5} nits", .{
            metadata.max_luminance,
            metadata.min_luminance,
        });
    }

    /// Check if HDR is fully supported
    pub fn isHDRAvailable(self: *HDRSupport) bool {
        return self.has_hdr_metadata_ext and self.has_swapchain_colorspace_ext;
    }
};

/// HDR tonemapping push constants for shaders
pub const HDRPushConstants = struct {
    exposure: f32,
    max_luminance: f32,
    use_tonemap: u32, // bool
    _padding: u32,

    pub fn init(exposure: f32, max_luminance: f32) HDRPushConstants {
        return .{
            .exposure = exposure,
            .max_luminance = max_luminance,
            .use_tonemap = 1,
            ._padding = 0,
        };
    }

    pub fn noTonemap() HDRPushConstants {
        return .{
            .exposure = 1.0,
            .max_luminance = 1.0,
            .use_tonemap = 0,
            ._padding = 0,
        };
    }
};
