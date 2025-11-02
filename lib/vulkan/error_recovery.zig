//! Comprehensive error recovery for common Vulkan errors
//!
//! Handles:
//! - VK_ERROR_OUT_OF_DATE_KHR gracefully (swapchain recreation)
//! - VK_ERROR_DEVICE_LOST with exponential backoff retry
//! - Fallback to lower quality settings on OOM

const std = @import("std");
const types = @import("types.zig");

const log = std.log.scoped(.error_recovery);

/// Error recovery strategy
pub const RecoveryStrategy = enum {
    retry,
    recreate_swapchain,
    reduce_quality,
    fail,
};

/// Error recovery result
pub const RecoveryResult = union(enum) {
    recovered,
    retry_needed,
    unrecoverable: anyerror,
};

/// Recovery context with retry state
pub const RecoveryContext = struct {
    retry_count: u32 = 0,
    max_retries: u32 = 3,
    backoff_ms: u64 = 100,
    max_backoff_ms: u64 = 5000,

    /// Reset retry state
    pub fn reset(self: *RecoveryContext) void {
        self.retry_count = 0;
        self.backoff_ms = 100;
    }

    /// Check if we should retry
    pub fn shouldRetry(self: *RecoveryContext) bool {
        return self.retry_count < self.max_retries;
    }

    /// Perform exponential backoff
    pub fn backoff(self: *RecoveryContext) void {
        if (self.retry_count > 0) {
            log.info("Backing off for {}ms (retry {}/{})", .{
                self.backoff_ms,
                self.retry_count,
                self.max_retries,
            });
            std.time.sleep(self.backoff_ms * std.time.ns_per_ms);
        }

        self.retry_count += 1;
        self.backoff_ms = @min(self.backoff_ms * 2, self.max_backoff_ms);
    }
};

/// Determine recovery strategy for a Vulkan result
pub fn getRecoveryStrategy(result: types.VkResult) RecoveryStrategy {
    return switch (result) {
        .SUCCESS => .retry, // No recovery needed
        .NOT_READY, .TIMEOUT, .INCOMPLETE => .retry,

        // Swapchain issues
        .ERROR_OUT_OF_DATE_KHR, .SUBOPTIMAL_KHR => .recreate_swapchain,

        // Device lost - retry with backoff
        .ERROR_DEVICE_LOST => .retry,

        // Out of memory - reduce quality
        .ERROR_OUT_OF_HOST_MEMORY,
        .ERROR_OUT_OF_DEVICE_MEMORY,
        .ERROR_FRAGMENTED_POOL => .reduce_quality,

        // Fatal errors
        .ERROR_INITIALIZATION_FAILED,
        .ERROR_LAYER_NOT_PRESENT,
        .ERROR_EXTENSION_NOT_PRESENT,
        .ERROR_FEATURE_NOT_PRESENT,
        .ERROR_INCOMPATIBLE_DRIVER,
        .ERROR_TOO_MANY_OBJECTS,
        .ERROR_FORMAT_NOT_SUPPORTED => .fail,

        // Surface errors
        .ERROR_SURFACE_LOST_KHR,
        .ERROR_NATIVE_WINDOW_IN_USE_KHR => .recreate_swapchain,

        // Unknown - fail safely
        else => .fail,
    };
}

/// Handle swapchain out of date error
pub fn handleOutOfDate(result: types.VkResult) bool {
    if (result == .ERROR_OUT_OF_DATE_KHR or result == .SUBOPTIMAL_KHR) {
        log.info("Swapchain is out of date (result={}), needs recreation", .{result});
        return true;
    }
    return false;
}

/// Handle device lost with retry logic
pub fn handleDeviceLost(
    result: types.VkResult,
    ctx: *RecoveryContext,
) RecoveryResult {
    if (result != .ERROR_DEVICE_LOST) {
        return .recovered;
    }

    log.err("Device lost detected", .{});

    if (!ctx.shouldRetry()) {
        log.err("Max retries ({}) exceeded, giving up", .{ctx.max_retries});
        return .{ .unrecoverable = error.DeviceLost };
    }

    log.warn("Attempting recovery (retry {}/{})", .{
        ctx.retry_count + 1,
        ctx.max_retries,
    });

    ctx.backoff();
    return .retry_needed;
}

/// Handle out of memory errors
pub fn handleOutOfMemory(
    result: types.VkResult,
    current_quality: *f32, // Quality factor 0.0-1.0
) RecoveryResult {
    const is_oom = switch (result) {
        .ERROR_OUT_OF_HOST_MEMORY,
        .ERROR_OUT_OF_DEVICE_MEMORY,
        .ERROR_FRAGMENTED_POOL => true,
        else => false,
    };

    if (!is_oom) {
        return .recovered;
    }

    log.err("Out of memory detected (result={})", .{result});

    // Reduce quality by 25%
    const old_quality = current_quality.*;
    current_quality.* = @max(0.25, current_quality.* * 0.75);

    log.warn("Reducing quality: {d:.2} -> {d:.2}", .{old_quality, current_quality.*});

    if (current_quality.* <= 0.25) {
        log.err("Quality already at minimum, cannot reduce further", .{});
        return .{ .unrecoverable = error.OutOfMemory };
    }

    return .retry_needed;
}

/// Attempt to recover from a Vulkan error
pub fn attemptRecovery(
    result: types.VkResult,
    ctx: *RecoveryContext,
    quality: *f32,
) RecoveryResult {
    if (result == .SUCCESS) {
        ctx.reset();
        return .recovered;
    }

    log.warn("Attempting recovery from error: {}", .{result});

    const strategy = getRecoveryStrategy(result);
    log.info("Recovery strategy: {}", .{strategy});

    return switch (strategy) {
        .retry => {
            if (!ctx.shouldRetry()) {
                return .{ .unrecoverable = error.MaxRetriesExceeded };
            }
            ctx.backoff();
            return .retry_needed;
        },

        .recreate_swapchain => {
            log.info("Swapchain recreation required", .{});
            return .retry_needed;
        },

        .reduce_quality => handleOutOfMemory(result, quality),

        .fail => {
            log.err("Unrecoverable error: {}", .{result});
            return .{ .unrecoverable = error.VulkanError };
        },
    };
}

/// Print recovery statistics
pub fn printRecoveryInfo(ctx: *RecoveryContext, quality: f32) void {
    log.info("=== Error Recovery Status ===", .{});
    log.info("Retry count: {}/{}", .{ctx.retry_count, ctx.max_retries});
    log.info("Current quality: {d:.2}", .{quality});
    log.info("Backoff delay: {}ms", .{ctx.backoff_ms});
    log.info("", .{});
}

/// Example usage wrapper for operations that may need recovery
pub fn withRecovery(
    comptime operation: anytype,
    ctx: *RecoveryContext,
    quality: *f32,
) !void {
    while (true) {
        const result = operation();

        const recovery_result = attemptRecovery(result, ctx, quality);

        switch (recovery_result) {
            .recovered => {
                ctx.reset();
                return;
            },
            .retry_needed => {
                log.info("Retrying operation after recovery attempt", .{});
                continue;
            },
            .unrecoverable => |err| {
                log.err("Unrecoverable error during operation", .{});
                return err;
            },
        }
    }
}
