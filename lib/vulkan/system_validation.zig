const std = @import("std");
const types = @import("types.zig");
const physical_device = @import("physical_device.zig");
const compositor_validation = @import("compositor_validation.zig");

pub const KernelValidationOptions = struct {
    min_vm_max_map_count: u64 = 16_777_216,
};

pub const SystemValidationOptions = struct {
    kernel: KernelValidationOptions = .{},
    check_compositor: bool = true,
    check_high_refresh: bool = true,
    target_refresh_hz: u32 = 144,
};

pub const SystemValidation = struct {
    kernel: KernelValidation,
    compositor: ?compositor_validation.CompositorInfo = null,
    max_refresh_hz: u32 = 0,

    pub fn needsAttention(self: SystemValidation) bool {
        if (self.kernel.needsAttention()) return true;
        if (self.compositor) |comp| {
            if (comp.needsAttention()) return true;
        }
        return false;
    }

    pub fn deinit(self: *SystemValidation, allocator: std.mem.Allocator) void {
        if (self.compositor) |*comp| {
            comp.deinit(allocator);
        }
    }
};

pub const KernelValidation = struct {
    vm_max_map_count: ?u64 = null,
    vm_max_map_count_required: u64,
    vm_max_map_count_ok: bool,
    bore_scheduler_detected: bool,
    rebar_enabled: bool,

    pub fn needsAttention(self: KernelValidation) bool {
        return !self.vm_max_map_count_ok or !self.bore_scheduler_detected or !self.rebar_enabled;
    }
};

pub fn validateKernelParameters(memory_props: types.VkPhysicalDeviceMemoryProperties, options: KernelValidationOptions) KernelValidation {
    const vm_value = readVmMaxMapCount();
    const bore = detectBoreScheduler();
    const rebar = physical_device.detectReBAR(memory_props);
    const vm_ok = if (vm_value) |value| value >= options.min_vm_max_map_count else false;

    return KernelValidation{
        .vm_max_map_count = vm_value,
        .vm_max_map_count_required = options.min_vm_max_map_count,
        .vm_max_map_count_ok = vm_ok,
        .bore_scheduler_detected = bore,
        .rebar_enabled = rebar,
    };
}

/// Perform full system validation
pub fn validateSystem(allocator: std.mem.Allocator, memory_props: types.VkPhysicalDeviceMemoryProperties, options: SystemValidationOptions) !SystemValidation {
    var result = SystemValidation{
        .kernel = validateKernelParameters(memory_props, options.kernel),
        .compositor = null,
        .max_refresh_hz = 0,
    };

    if (options.check_compositor) {
        result.compositor = try compositor_validation.detectCompositor(allocator);
    }

    if (options.check_high_refresh) {
        result.max_refresh_hz = getMaxRefreshRate();
    }

    return result;
}

/// Log full system validation results
pub fn logSystemValidation(result: SystemValidation) void {
    std.log.info("=== Zeus System Validation ===", .{});

    // Kernel validation
    logKernelValidation(result.kernel);

    // Compositor validation
    if (result.compositor) |comp| {
        compositor_validation.logCompositorInfo(comp);
    }

    // Display refresh rate
    if (result.max_refresh_hz > 0) {
        std.log.info("display max_refresh={d} Hz", .{result.max_refresh_hz});
    }

    // Overall status
    if (result.needsAttention()) {
        std.log.warn("system validation: some checks require attention (see warnings above)", .{});
    } else {
        std.log.info("system validation: all checks passed", .{});
    }
}

pub fn logKernelValidation(result: KernelValidation) void {
    if (result.vm_max_map_count) |value| {
        const status = if (result.vm_max_map_count_ok) "ok" else "raise";
        std.log.info(
            "kernel vm.max_map_count={d} (required>={d}) status={s}",
            .{ value, result.vm_max_map_count_required, status },
        );
    } else {
        std.log.warn("kernel vm.max_map_count unavailable", .{});
    }

    std.log.info("kernel bore_scheduler={s}", .{if (result.bore_scheduler_detected) "detected" else "missing"});
    std.log.info("kernel rebar_enabled={s}", .{if (result.rebar_enabled) "true" else "false"});
}

/// Get maximum refresh rate from DRM
fn getMaxRefreshRate() u32 {
    const dir = std.fs.openDirAbsolute("/sys/class/drm", .{ .iterate = true }) catch return 0;
    defer dir.close();

    var best_refresh: u32 = 0;
    var iter = dir.iterate();
    while (iter.next()) |entry| {
        if (entry.kind != .directory and entry.kind != .sym_link) continue;
        if (!std.mem.startsWith(u8, entry.name, "card")) continue;

        var path_buf: [128]u8 = undefined;
        const modes_rel = std.fmt.bufPrint(&path_buf, "{s}/modes", .{entry.name}) catch continue;
        var modes_file = dir.openFile(modes_rel, .{}) catch continue;
        defer modes_file.close();

        var line_buf: [128]u8 = undefined;
        var reader = modes_file.reader();
        while (true) {
            const line_opt = reader.readUntilDelimiterOrEof(&line_buf, '\n') catch break;
            if (line_opt == null) break;
            const line = std.mem.trim(u8, line_opt.?, " \r\t");
            if (line.len == 0) continue;
            if (parseRefresh(line)) |refresh| {
                if (refresh > best_refresh) {
                    best_refresh = refresh;
                }
            }
        }
    }
    return best_refresh;
}

pub fn logDrmHighRefresh(threshold_hz: u32) void {
    const dir = std.fs.openDirAbsolute("/sys/class/drm", .{ .iterate = true }) catch |err| {
        std.log.warn("drm modes unavailable: {s}", .{@errorName(err)});
        return;
    };
    defer dir.close();

    var best_refresh: u32 = 0;
    var best_name_buf: [64]u8 = undefined;
    var best_name_len: usize = 0;

    var iter = dir.iterate();
    while (iter.next()) |entry| {
        if (entry.kind != .directory and entry.kind != .sym_link) continue;
        if (!std.mem.startsWith(u8, entry.name, "card")) continue;

        var path_buf: [128]u8 = undefined;
        const modes_rel = std.fmt.bufPrint(&path_buf, "{s}/modes", .{entry.name}) catch continue;
        var modes_file = dir.openFile(modes_rel, .{}) catch continue;
        defer modes_file.close();

        var line_buf: [128]u8 = undefined;
        var reader = modes_file.reader();
        while (true) {
            const line_opt = reader.readUntilDelimiterOrEof(&line_buf, '\n') catch break;
            if (line_opt == null) break;
            const line = std.mem.trim(u8, line_opt.?, " \r\t");
            if (line.len == 0) continue;
            if (parseRefresh(line)) |refresh| {
                if (refresh > best_refresh) {
                    best_refresh = refresh;
                    best_name_len = @min(entry.name.len, best_name_buf.len);
                    std.mem.copyForwards(u8, best_name_buf[0..best_name_len], entry.name[0..best_name_len]);
                }
            }
        }
    }

    if (best_refresh == 0) {
        std.log.warn("drm modes: no refresh information detected", .{});
        return;
    }

    const best_name = best_name_buf[0..best_name_len];
    if (best_refresh >= threshold_hz) {
        std.log.info("drm modes: {s} supports {d} Hz (target {d} Hz)", .{ best_name, best_refresh, threshold_hz });
    } else {
        std.log.warn("drm modes: {s} max {d} Hz (below target {d} Hz)", .{ best_name, best_refresh, threshold_hz });
    }
}

fn parseRefresh(line: []const u8) ?u32 {
    const at_index = std.mem.indexOfScalar(u8, line, '@') orelse return null;
    const freq_slice = line[at_index + 1 ..];
    var end: usize = 0;
    while (end < freq_slice.len and std.ascii.isDigit(freq_slice[end])) : (end += 1) {}
    if (end == 0) return null;
    return std.fmt.parseInt(u32, freq_slice[0..end], 10) catch null;
}

fn readVmMaxMapCount() ?u64 {
    const path = "/proc/sys/vm/max_map_count";
    var file = std.fs.openFileAbsolute(path, .{}) catch return null;
    defer file.close();

    var buffer: [64]u8 = undefined;
    const len = file.readAll(&buffer) catch return null;
    const trimmed = std.mem.trim(u8, buffer[0..len], " \t\n\r");
    if (trimmed.len == 0) return null;
    return std.fmt.parseInt(u64, trimmed, 10) catch return null;
}

fn detectBoreScheduler() bool {
    const uts = std.os.uname() catch return false;
    const release = std.mem.sliceTo(&uts.release, 0);
    if (std.ascii.indexOfIgnoreCase(release, "bore")) |_| {
        return true;
    }
    const version = std.mem.sliceTo(&uts.version, 0);
    if (std.ascii.indexOfIgnoreCase(version, "bore")) |_| {
        return true;
    }

    const sched_path = "/sys/kernel/debug/sched_features";
    var sched_file = std.fs.openFileAbsolute(sched_path, .{}) catch return false;
    defer sched_file.close();

    var buffer: [512]u8 = undefined;
    const len = sched_file.readAll(&buffer) catch return false;
    const slice = buffer[0..len];
    return std.mem.indexOf(u8, slice, "BORE") != null;
}

test "KernelValidation.needsAttention reflects fields" {
    const ok = KernelValidation{
        .vm_max_map_count = 16_777_216,
        .vm_max_map_count_required = 16_777_216,
        .vm_max_map_count_ok = true,
        .bore_scheduler_detected = true,
        .rebar_enabled = true,
    };
    try std.testing.expect(!ok.needsAttention());

    const missing = KernelValidation{
        .vm_max_map_count = null,
        .vm_max_map_count_required = 16_777_216,
        .vm_max_map_count_ok = false,
        .bore_scheduler_detected = false,
        .rebar_enabled = false,
    };
    try std.testing.expect(missing.needsAttention());
}
