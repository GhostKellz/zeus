//! Variable Refresh Rate (VRR) and Adaptive Sync support for high refresh rate displays

const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const swapchain_mod = @import("swapchain.zig");
const instance_mod = @import("instance.zig");

const log = std.log.scoped(.vrr_support);

/// Present mode for VRR
pub const PresentMode = enum {
    immediate, // No vsync, tear possible, lowest latency
    mailbox, // Triple buffering, no tearing
    fifo, // Traditional vsync
    fifo_relaxed, // Adaptive vsync (late frames tear)

    pub fn toVulkan(self: PresentMode) types.VkPresentModeKHR {
        return switch (self) {
            .immediate => .IMMEDIATE,
            .mailbox => .MAILBOX,
            .fifo => .FIFO,
            .fifo_relaxed => .FIFO_RELAXED,
        };
    }

    pub fn fromVulkan(mode: types.VkPresentModeKHR) PresentMode {
        return switch (mode) {
            .IMMEDIATE => .immediate,
            .MAILBOX => .mailbox,
            .FIFO => .fifo,
            .FIFO_RELAXED => .fifo_relaxed,
            else => .fifo,
        };
    }
};

/// VRR configuration
pub const VRRConfig = struct {
    preferred_mode: PresentMode,
    min_refresh_rate: u32, // Hz
    max_refresh_rate: u32, // Hz
    enable_adaptive_sync: bool,

    /// High-end gaming config (240-360Hz OLED)
    pub fn highRefreshRate() VRRConfig {
        return .{
            .preferred_mode = .mailbox,
            .min_refresh_rate = 60,
            .max_refresh_rate = 360,
            .enable_adaptive_sync = true,
        };
    }

    /// Competitive config (lowest latency)
    pub fn competitive() VRRConfig {
        return .{
            .preferred_mode = .immediate,
            .min_refresh_rate = 144,
            .max_refresh_rate = 360,
            .enable_adaptive_sync = true,
        };
    }

    /// Power-saving config
    pub fn powerSaving() VRRConfig {
        return .{
            .preferred_mode = .fifo_relaxed,
            .min_refresh_rate = 30,
            .max_refresh_rate = 144,
            .enable_adaptive_sync = true,
        };
    }

    /// Standard config (traditional vsync)
    pub fn standard() VRRConfig {
        return .{
            .preferred_mode = .fifo,
            .min_refresh_rate = 60,
            .max_refresh_rate = 60,
            .enable_adaptive_sync = false,
        };
    }
};

/// Display timing information
pub const DisplayTiming = struct {
    refresh_duration_ns: u64, // Nanoseconds per frame
    refresh_rate_hz: f32,
    vrr_active: bool,

    pub fn fromRefreshRate(hz: f32) DisplayTiming {
        const duration_ns = @as(u64, @intFromFloat(1_000_000_000.0 / hz));
        return .{
            .refresh_duration_ns = duration_ns,
            .refresh_rate_hz = hz,
            .vrr_active = false,
        };
    }
};

/// VRR support and management
pub const VRRSupport = struct {
    allocator: std.mem.Allocator,
    instance: *instance_mod.Instance,
    device: *device_mod.Device,
    config: VRRConfig,
    has_display_control_ext: bool,
    supported_present_modes: std.ArrayList(types.VkPresentModeKHR),
    current_timing: DisplayTiming,

    pub fn init(
        allocator: std.mem.Allocator,
        instance: *instance_mod.Instance,
        device: *device_mod.Device,
        config: VRRConfig,
    ) !*VRRSupport {
        const self = try allocator.create(VRRSupport);
        self.* = .{
            .allocator = allocator,
            .instance = instance,
            .device = device,
            .config = config,
            .has_display_control_ext = false,
            .supported_present_modes = std.ArrayList(types.VkPresentModeKHR).init(allocator),
            .current_timing = DisplayTiming.fromRefreshRate(@floatFromInt(config.max_refresh_rate)),
        };

        try self.detectCapabilities();

        return self;
    }

    pub fn deinit(self: *VRRSupport) void {
        self.supported_present_modes.deinit();
        self.allocator.destroy(self);
    }

    /// Detect VRR capabilities
    fn detectCapabilities(self: *VRRSupport) !void {
        // Check for VK_EXT_display_control
        self.has_display_control_ext = self.device.hasExtension("VK_EXT_display_control");

        log.info("VRR capabilities: display_control={}", .{self.has_display_control_ext});
    }

    /// Query supported present modes for a surface
    pub fn queryPresentModes(
        self: *VRRSupport,
        physical_device: types.VkPhysicalDevice,
        surface: types.VkSurfaceKHR,
    ) ![]types.VkPresentModeKHR {
        self.supported_present_modes.clearRetainingCapacity();

        var mode_count: u32 = 0;
        _ = self.instance.dispatch.get_physical_device_surface_present_modes_khr(
            physical_device,
            surface,
            &mode_count,
            null,
        );

        if (mode_count == 0) {
            return &[_]types.VkPresentModeKHR{};
        }

        try self.supported_present_modes.resize(mode_count);
        _ = self.instance.dispatch.get_physical_device_surface_present_modes_khr(
            physical_device,
            surface,
            &mode_count,
            self.supported_present_modes.items.ptr,
        );

        log.debug("Found {} present modes:", .{mode_count});
        for (self.supported_present_modes.items) |mode| {
            log.debug("  {}", .{mode});
        }

        return self.supported_present_modes.items;
    }

    /// Check if a present mode is supported
    pub fn supportsPresentMode(self: *VRRSupport, mode: PresentMode) bool {
        const vk_mode = mode.toVulkan();
        for (self.supported_present_modes.items) |supported| {
            if (supported == vk_mode) {
                return true;
            }
        }
        return false;
    }

    /// Select best available present mode based on config
    pub fn selectBestPresentMode(self: *VRRSupport) PresentMode {
        // Try preferred mode first
        if (self.supportsPresentMode(self.config.preferred_mode)) {
            log.info("Using preferred present mode: {}", .{self.config.preferred_mode});
            return self.config.preferred_mode;
        }

        // Fallback hierarchy
        const fallbacks = [_]PresentMode{ .mailbox, .fifo_relaxed, .immediate, .fifo };

        for (fallbacks) |mode| {
            if (self.supportsPresentMode(mode)) {
                log.info("Using fallback present mode: {}", .{mode});
                return mode;
            }
        }

        // FIFO is guaranteed to be available
        log.info("Using guaranteed FIFO present mode", .{});
        return .fifo;
    }

    /// Update display timing based on actual present mode
    pub fn updateTiming(self: *VRRSupport, present_mode: PresentMode, measured_fps: ?f32) void {
        if (measured_fps) |fps| {
            self.current_timing = DisplayTiming.fromRefreshRate(fps);
            self.current_timing.vrr_active = switch (present_mode) {
                .immediate, .mailbox, .fifo_relaxed => true,
                .fifo => false,
            };
        }
    }

    /// Get current frame time target
    pub fn getTargetFrameTime(self: *VRRSupport) u64 {
        return self.current_timing.refresh_duration_ns;
    }

    /// Check if VRR is active
    pub fn isVRRActive(self: *VRRSupport) bool {
        return self.current_timing.vrr_active and self.config.enable_adaptive_sync;
    }

    /// Get recommended swapchain image count for present mode
    pub fn getRecommendedImageCount(_: *VRRSupport, present_mode: PresentMode, min_images: u32) u32 {
        return switch (present_mode) {
            .immediate => @max(min_images, 2), // Double buffering for immediate
            .mailbox => @max(min_images, 3), // Triple buffering for mailbox
            .fifo, .fifo_relaxed => @max(min_images, 2), // Double buffering for FIFO
        };
    }
};

/// Frame pacing helper for consistent frame times
pub const FramePacer = struct {
    target_frame_time_ns: u64,
    last_frame_time_ns: i128,
    frame_times: std.ArrayList(u64),
    max_history: usize,

    pub fn init(allocator: std.mem.Allocator, target_fps: f32) !*FramePacer {
        const self = try allocator.create(FramePacer);
        self.* = .{
            .target_frame_time_ns = @intFromFloat(1_000_000_000.0 / target_fps),
            .last_frame_time_ns = std.time.nanoTimestamp(),
            .frame_times = std.ArrayList(u64).init(allocator),
            .max_history = 60,
        };
        return self;
    }

    pub fn deinit(self: *FramePacer, allocator: std.mem.Allocator) void {
        self.frame_times.deinit();
        allocator.destroy(self);
    }

    /// Mark frame start
    pub fn frameStart(self: *FramePacer) void {
        self.last_frame_time_ns = std.time.nanoTimestamp();
    }

    /// Mark frame end and calculate sleep time
    pub fn frameEnd(self: *FramePacer) !void {
        const now = std.time.nanoTimestamp();
        const frame_time = @as(u64, @intCast(now - self.last_frame_time_ns));

        // Record frame time
        try self.frame_times.append(frame_time);
        if (self.frame_times.items.len > self.max_history) {
            _ = self.frame_times.orderedRemove(0);
        }

        // Sleep if we're ahead of target
        if (frame_time < self.target_frame_time_ns) {
            const sleep_ns = self.target_frame_time_ns - frame_time;
            std.time.sleep(sleep_ns);
        }
    }

    /// Get average FPS
    pub fn getAverageFPS(self: *FramePacer) f32 {
        if (self.frame_times.items.len == 0) return 0.0;

        var total: u64 = 0;
        for (self.frame_times.items) |ft| {
            total += ft;
        }

        const avg_ns = total / self.frame_times.items.len;
        return 1_000_000_000.0 / @as(f32, @floatFromInt(avg_ns));
    }

    /// Get frame time percentiles (for 1% and 0.1% lows)
    pub fn getPercentile(self: *FramePacer, percentile: f32) u64 {
        if (self.frame_times.items.len == 0) return 0;

        var sorted = std.ArrayList(u64).init(self.frame_times.allocator);
        defer sorted.deinit();

        sorted.appendSlice(self.frame_times.items) catch return 0;
        std.mem.sort(u64, sorted.items, {}, comptime std.sort.asc(u64));

        const index = @as(usize, @intFromFloat(@as(f32, @floatFromInt(sorted.items.len)) * percentile));
        return sorted.items[@min(index, sorted.items.len - 1)];
    }
};
