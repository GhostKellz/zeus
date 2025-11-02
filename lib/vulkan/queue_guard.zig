//! Queue priority validation and guards for device creation
//!
//! Ensures queue priorities are properly allocated and validated
//! to prevent issues with overlay layers that inspect VkDeviceCreateInfo

const std = @import("std");
const types = @import("types.zig");

const log = std.log.scoped(.queue_guard);

/// Validate queue create info array for common issues
pub fn validateQueueCreateInfos(infos: []const types.VkDeviceQueueCreateInfo) !void {
    if (infos.len == 0) {
        log.err("No queue create infos provided", .{});
        return error.NoQueueCreateInfos;
    }

    for (infos, 0..) |info, i| {
        // Validate sType
        if (info.sType != .DEVICE_QUEUE_CREATE_INFO) {
            log.err("Queue create info[{}] has invalid sType: {}", .{i, info.sType});
            return error.InvalidQueueCreateInfoSType;
        }

        // Validate queueCount
        if (info.queueCount == 0) {
            log.err("Queue create info[{}] has queueCount = 0", .{i});
            return error.ZeroQueueCount;
        }

        // Validate priorities pointer
        if (info.pQueuePriorities == null) {
            log.err("Queue create info[{}] has null pQueuePriorities", .{i});
            return error.NullQueuePriorities;
        }

        // Validate priorities are in valid range [0.0, 1.0]
        const priorities = info.pQueuePriorities.?[0..info.queueCount];
        for (priorities, 0..) |priority, j| {
            if (priority < 0.0 or priority > 1.0) {
                log.err("Queue create info[{}] priority[{}] = {} is out of range [0.0, 1.0]", .{i, j, priority});
                return error.InvalidQueuePriority;
            }
        }

        // Check for duplicate family indices
        for (infos[0..i]) |prev_info| {
            if (prev_info.queueFamilyIndex == info.queueFamilyIndex) {
                log.err("Duplicate queue family index {} found", .{info.queueFamilyIndex});
                return error.DuplicateQueueFamilyIndex;
            }
        }
    }

    log.debug("Queue create infos validation passed ({} families)", .{infos.len});
}

/// Assert queue priorities are properly allocated (Debug mode only)
pub fn assertQueuePrioritiesValid(infos: []const types.VkDeviceQueueCreateInfo) void {
    if (@import("builtin").mode != .Debug) return;

    validateQueueCreateInfos(infos) catch |err| {
        log.err("ASSERTION FAILED: Queue priorities validation failed: {}", .{err});
        @panic("Queue priorities validation failed - see log for details");
    };
}

/// Allocate and initialize queue priorities buffer
/// Returns a buffer that must be kept alive until vkCreateDevice returns
pub fn allocateQueuePriorities(
    allocator: std.mem.Allocator,
    queue_count: usize,
    default_priority: f32,
) ![]f32 {
    if (queue_count == 0) {
        return error.ZeroQueueCount;
    }

    if (default_priority < 0.0 or default_priority > 1.0) {
        log.err("Invalid default priority: {}", .{default_priority});
        return error.InvalidQueuePriority;
    }

    const priorities = try allocator.alloc(f32, queue_count);
    @memset(priorities, default_priority);

    log.debug("Allocated {} queue priorities (default: {})", .{queue_count, default_priority});

    return priorities;
}

/// Helper to create queue create info with validated priorities
pub fn createQueueCreateInfo(
    family_index: u32,
    priorities: []const f32,
) types.VkDeviceQueueCreateInfo {
    std.debug.assert(priorities.len > 0);
    std.debug.assert(priorities.len <= std.math.maxInt(u32));

    // Validate all priorities are in range
    for (priorities) |p| {
        std.debug.assert(p >= 0.0 and p <= 1.0);
    }

    return types.VkDeviceQueueCreateInfo{
        .sType = .DEVICE_QUEUE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .queueFamilyIndex = family_index,
        .queueCount = @intCast(priorities.len),
        .pQueuePriorities = priorities.ptr,
    };
}

/// Print queue create info details for debugging
pub fn printQueueCreateInfo(info: types.VkDeviceQueueCreateInfo) void {
    log.debug("Queue Family {}: {} queues", .{info.queueFamilyIndex, info.queueCount});

    const priorities = info.pQueuePriorities.?[0..info.queueCount];
    for (priorities, 0..) |priority, i| {
        log.debug("  Queue[{}]: priority = {d:.2}", .{i, priority});
    }
}
