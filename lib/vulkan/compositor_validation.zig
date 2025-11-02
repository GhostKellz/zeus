const std = @import("std");

/// Wayland compositor types
pub const CompositorType = enum {
    hyprland,
    kde_plasma,
    gnome,
    cosmic,
    sway,
    river,
    wayfire,
    weston,
    unknown,

    pub fn fromString(name: []const u8) CompositorType {
        if (std.ascii.indexOfIgnoreCase(name, "hyprland")) |_| return .hyprland;
        if (std.ascii.indexOfIgnoreCase(name, "plasma")) |_| return .kde_plasma;
        if (std.ascii.indexOfIgnoreCase(name, "kde")) |_| return .kde_plasma;
        if (std.ascii.indexOfIgnoreCase(name, "kwin")) |_| return .kde_plasma;
        if (std.ascii.indexOfIgnoreCase(name, "gnome")) |_| return .gnome;
        if (std.ascii.indexOfIgnoreCase(name, "mutter")) |_| return .gnome;
        if (std.ascii.indexOfIgnoreCase(name, "cosmic")) |_| return .cosmic;
        if (std.ascii.indexOfIgnoreCase(name, "pop")) |_| return .cosmic;
        if (std.ascii.indexOfIgnoreCase(name, "sway")) |_| return .sway;
        if (std.ascii.indexOfIgnoreCase(name, "river")) |_| return .river;
        if (std.ascii.indexOfIgnoreCase(name, "wayfire")) |_| return .wayfire;
        if (std.ascii.indexOfIgnoreCase(name, "weston")) |_| return .weston;
        return .unknown;
    }

    pub fn isTested(self: CompositorType) bool {
        return switch (self) {
            .hyprland, .kde_plasma => true,
            else => false,
        };
    }

    pub fn toString(self: CompositorType) []const u8 {
        return switch (self) {
            .hyprland => "Hyprland",
            .kde_plasma => "KDE Plasma Wayland",
            .gnome => "GNOME Shell",
            .cosmic => "Cosmic (Pop!_OS)",
            .sway => "Sway",
            .river => "River",
            .wayfire => "Wayfire",
            .weston => "Weston",
            .unknown => "Unknown",
        };
    }
};

/// Wayland compositor detection result
pub const CompositorInfo = struct {
    compositor_type: CompositorType,
    detected: bool,
    display_name: ?[]const u8,
    desktop_session: ?[]const u8,
    wayland_socket: ?[]const u8,
    is_tested: bool,
    supports_vulkan: bool,

    pub fn needsAttention(self: CompositorInfo) bool {
        return !self.detected or !self.is_tested or !self.supports_vulkan;
    }

    pub fn deinit(self: *CompositorInfo, allocator: std.mem.Allocator) void {
        if (self.display_name) |s| allocator.free(s);
        if (self.desktop_session) |s| allocator.free(s);
        if (self.wayland_socket) |s| allocator.free(s);
    }
};

/// Detect Wayland compositor and capabilities
pub fn detectCompositor(allocator: std.mem.Allocator) !CompositorInfo {
    // Check if Wayland is running
    const wayland_display = std.posix.getenv("WAYLAND_DISPLAY");
    if (wayland_display == null) {
        return CompositorInfo{
            .compositor_type = .unknown,
            .detected = false,
            .display_name = null,
            .desktop_session = null,
            .wayland_socket = null,
            .is_tested = false,
            .supports_vulkan = false,
        };
    }

    // Get desktop session info
    const xdg_session_desktop = std.posix.getenv("XDG_CURRENT_DESKTOP");
    const xdg_session_type = std.posix.getenv("XDG_SESSION_TYPE");

    // Verify we're in a Wayland session
    const is_wayland = if (xdg_session_type) |st|
        std.mem.eql(u8, st, "wayland")
    else
        true; // Assume Wayland if WAYLAND_DISPLAY is set

    if (!is_wayland) {
        return CompositorInfo{
            .compositor_type = .unknown,
            .detected = false,
            .display_name = null,
            .desktop_session = null,
            .wayland_socket = null,
            .is_tested = false,
            .supports_vulkan = false,
        };
    }

    // Detect compositor type
    var comp_type: CompositorType = .unknown;

    // First, check XDG_CURRENT_DESKTOP
    if (xdg_session_desktop) |desktop| {
        comp_type = CompositorType.fromString(desktop);
    }

    // If still unknown, check for compositor-specific processes
    if (comp_type == .unknown) {
        comp_type = detectCompositorFromProcess(allocator) catch .unknown;
    }

    // Clone strings for persistent storage
    const display_name = if (wayland_display) |wd|
        try allocator.dupe(u8, wd)
    else
        null;

    const desktop_session = if (xdg_session_desktop) |ds|
        try allocator.dupe(u8, ds)
    else
        null;

    const wayland_socket = try getWaylandSocketPath(allocator);

    return CompositorInfo{
        .compositor_type = comp_type,
        .detected = true,
        .display_name = display_name,
        .desktop_session = desktop_session,
        .wayland_socket = wayland_socket,
        .is_tested = comp_type.isTested(),
        .supports_vulkan = true, // All modern Wayland compositors support Vulkan
    };
}

/// Detect compositor from running processes
fn detectCompositorFromProcess(allocator: std.mem.Allocator) !CompositorType {
    // Try to read /proc/self/environ to find parent process
    const proc_dir = std.fs.openDirAbsolute("/proc", .{}) catch return .unknown;
    defer proc_dir.close();

    // Check common compositor process names
    const compositor_names = [_][]const u8{
        "Hyprland",
        "kwin_wayland",
        "plasmashell",
        "gnome-shell",
        "sway",
        "river",
        "wayfire",
        "weston",
    };

    var buf: [4096]u8 = undefined;
    var iter = proc_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) continue;

        // Skip if not a numeric PID
        const pid = std.fmt.parseInt(u32, entry.name, 10) catch continue;
        _ = pid;

        // Try to read cmdline
        const cmdline_path = try std.fmt.bufPrint(&buf, "{s}/cmdline", .{entry.name});
        const cmdline_file = proc_dir.openFile(cmdline_path, .{}) catch continue;
        defer cmdline_file.close();

        var cmdline_buf: [256]u8 = undefined;
        const len = cmdline_file.readAll(&cmdline_buf) catch continue;
        if (len == 0) continue;

        // cmdline is null-separated, check first component
        const null_idx = std.mem.indexOfScalar(u8, cmdline_buf[0..len], 0) orelse len;
        const cmd = cmdline_buf[0..null_idx];

        // Check against known compositor names
        for (compositor_names) |name| {
            if (std.mem.indexOf(u8, cmd, name)) |_| {
                return CompositorType.fromString(name);
            }
        }
    }

    _ = allocator;
    return .unknown;
}

/// Get Wayland socket path
fn getWaylandSocketPath(allocator: std.mem.Allocator) !?[]const u8 {
    const wayland_display = std.posix.getenv("WAYLAND_DISPLAY") orelse return null;
    const xdg_runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse return null;

    return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ xdg_runtime_dir, wayland_display });
}

/// Log compositor detection results
pub fn logCompositorInfo(info: CompositorInfo) void {
    if (!info.detected) {
        std.log.warn("wayland compositor not detected (running under X11 or other?)", .{});
        return;
    }

    const status_str = if (info.is_tested) "tested" else "untested";
    std.log.info("wayland compositor detected: {s} (status={s})", .{
        info.compositor_type.toString(),
        status_str,
    });

    if (info.display_name) |name| {
        std.log.info("wayland display: {s}", .{name});
    }

    if (info.desktop_session) |session| {
        std.log.info("desktop session: {s}", .{session});
    }

    if (info.wayland_socket) |socket| {
        std.log.info("wayland socket: {s}", .{socket});
    }

    if (!info.is_tested) {
        std.log.warn(
            "compositor '{s}' is not officially tested - KDE Plasma Wayland and Hyprland are recommended",
            .{info.compositor_type.toString()},
        );
    }

    if (!info.supports_vulkan) {
        std.log.err("compositor does not support Vulkan rendering", .{});
    }
}

/// Validate Vulkan surface extensions for Wayland
pub fn validateWaylandExtensions(available_exts: []const u8) bool {
    // Check for VK_KHR_wayland_surface
    const has_wayland_surface = std.mem.indexOf(u8, available_exts, "VK_KHR_wayland_surface") != null;
    if (!has_wayland_surface) {
        std.log.err("VK_KHR_wayland_surface extension not available", .{});
        return false;
    }
    return true;
}

/// Check for specific compositor quirks/workarounds
pub const CompositorQuirks = struct {
    needs_explicit_sync: bool,
    requires_mailbox_fallback: bool,
    has_fractional_scaling: bool,
    supports_presentation_timing: bool,

    pub fn forCompositor(comp_type: CompositorType) CompositorQuirks {
        return switch (comp_type) {
            .hyprland => .{
                .needs_explicit_sync = false,
                .requires_mailbox_fallback = false,
                .has_fractional_scaling = true,
                .supports_presentation_timing = true,
            },
            .kde_plasma => .{
                .needs_explicit_sync = false,
                .requires_mailbox_fallback = false,
                .has_fractional_scaling = true,
                .supports_presentation_timing = true,
            },
            .gnome => .{
                .needs_explicit_sync = true,
                .requires_mailbox_fallback = true,
                .has_fractional_scaling = true,
                .supports_presentation_timing = false,
            },
            .cosmic => .{
                .needs_explicit_sync = false,
                .requires_mailbox_fallback = false,
                .has_fractional_scaling = true,
                .supports_presentation_timing = true,
            },
            .sway => .{
                .needs_explicit_sync = false,
                .requires_mailbox_fallback = false,
                .has_fractional_scaling = false,
                .supports_presentation_timing = true,
            },
            else => .{
                .needs_explicit_sync = false,
                .requires_mailbox_fallback = true,
                .has_fractional_scaling = false,
                .supports_presentation_timing = false,
            },
        };
    }
};

test "CompositorType.fromString detects known compositors" {
    try std.testing.expectEqual(CompositorType.hyprland, CompositorType.fromString("Hyprland"));
    try std.testing.expectEqual(CompositorType.kde_plasma, CompositorType.fromString("KDE"));
    try std.testing.expectEqual(CompositorType.kde_plasma, CompositorType.fromString("plasma"));
    try std.testing.expectEqual(CompositorType.kde_plasma, CompositorType.fromString("kwin_wayland"));
    try std.testing.expectEqual(CompositorType.gnome, CompositorType.fromString("GNOME"));
    try std.testing.expectEqual(CompositorType.gnome, CompositorType.fromString("mutter"));
    try std.testing.expectEqual(CompositorType.cosmic, CompositorType.fromString("cosmic"));
    try std.testing.expectEqual(CompositorType.cosmic, CompositorType.fromString("pop"));
    try std.testing.expectEqual(CompositorType.sway, CompositorType.fromString("sway"));
    try std.testing.expectEqual(CompositorType.unknown, CompositorType.fromString("foobar"));
}

test "CompositorType.isTested returns correct status" {
    try std.testing.expect(CompositorType.hyprland.isTested());
    try std.testing.expect(CompositorType.kde_plasma.isTested());
    try std.testing.expect(!CompositorType.gnome.isTested());
    try std.testing.expect(!CompositorType.unknown.isTested());
}

test "CompositorQuirks.forCompositor provides compositor-specific settings" {
    const hyprland_quirks = CompositorQuirks.forCompositor(.hyprland);
    try std.testing.expect(hyprland_quirks.has_fractional_scaling);
    try std.testing.expect(hyprland_quirks.supports_presentation_timing);

    const plasma_quirks = CompositorQuirks.forCompositor(.kde_plasma);
    try std.testing.expect(plasma_quirks.has_fractional_scaling);
    try std.testing.expect(plasma_quirks.supports_presentation_timing);

    const gnome_quirks = CompositorQuirks.forCompositor(.gnome);
    try std.testing.expect(gnome_quirks.needs_explicit_sync);
    try std.testing.expect(gnome_quirks.requires_mailbox_fallback);

    const cosmic_quirks = CompositorQuirks.forCompositor(.cosmic);
    try std.testing.expect(cosmic_quirks.has_fractional_scaling);
    try std.testing.expect(cosmic_quirks.supports_presentation_timing);
    try std.testing.expect(!cosmic_quirks.needs_explicit_sync);
}
