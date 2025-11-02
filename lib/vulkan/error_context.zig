//! Enhanced error context with call sites and stack traces

const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");

const log = std.log.scoped(.error_context);

/// Error context with source location
pub const ErrorContext = struct {
    err: errors.Error,
    source_location: std.builtin.SourceLocation,
    vk_result: ?types.VkResult,
    message: ?[]const u8,

    pub fn format(
        self: ErrorContext,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("Error: {} at {}:{}:{}", .{
            @errorName(self.err),
            self.source_location.file,
            self.source_location.line,
            self.source_location.column,
        });

        if (self.vk_result) |result| {
            try writer.print(" (VkResult: {})", .{errors.vkResultToString(result)});
        }

        if (self.message) |msg| {
            try writer.print(" - {s}", .{msg});
        }
    }
};

/// Ensure Vulkan success with context
pub fn ensureSuccessWithContext(
    result: types.VkResult,
    source_location: std.builtin.SourceLocation,
    message: ?[]const u8,
) !void {
    if (result != .SUCCESS) {
        const err = try errors.ensureSuccess(result);
        const ctx = ErrorContext{
            .err = err,
            .source_location = source_location,
            .vk_result = result,
            .message = message,
        };
        log.err("{}", .{ctx});
        return err;
    }
}

/// Error tracker for collecting multiple errors
pub const ErrorTracker = struct {
    allocator: std.mem.Allocator,
    errors_list: std.ArrayList(ErrorContext),

    pub fn init(allocator: std.mem.Allocator) ErrorTracker {
        return .{
            .allocator = allocator,
            .errors_list = std.ArrayList(ErrorContext).init(allocator),
        };
    }

    pub fn deinit(self: *ErrorTracker) void {
        self.errors_list.deinit();
    }

    pub fn addError(
        self: *ErrorTracker,
        err: errors.Error,
        source_location: std.builtin.SourceLocation,
        vk_result: ?types.VkResult,
        message: ?[]const u8,
    ) !void {
        try self.errors_list.append(.{
            .err = err,
            .source_location = source_location,
            .vk_result = vk_result,
            .message = message,
        });
    }

    pub fn hasErrors(self: *ErrorTracker) bool {
        return self.errors_list.items.len > 0;
    }

    pub fn printErrors(self: *ErrorTracker) void {
        if (self.errors_list.items.len == 0) {
            log.info("No errors recorded", .{});
            return;
        }

        log.err("=== Error Report ({} errors) ===", .{self.errors_list.items.len});
        for (self.errors_list.items, 0..) |ctx, i| {
            log.err("[{}] {}", .{ i + 1, ctx });
        }
    }

    pub fn clear(self: *ErrorTracker) void {
        self.errors_list.clearRetainingCapacity();
    }
};

/// Error recovery strategies
pub const RecoveryStrategy = enum {
    retry,
    recreate_resource,
    fallback,
    abort,
};

/// Error recovery context
pub const RecoveryContext = struct {
    strategy: RecoveryStrategy,
    max_retries: u32,
    retry_delay_ms: u64,

    pub fn retry() RecoveryContext {
        return .{
            .strategy = .retry,
            .max_retries = 3,
            .retry_delay_ms = 100,
        };
    }

    pub fn immediate() RecoveryContext {
        return .{
            .strategy = .retry,
            .max_retries = 1,
            .retry_delay_ms = 0,
        };
    }

    pub fn persistent() RecoveryContext {
        return .{
            .strategy = .retry,
            .max_retries = 10,
            .retry_delay_ms = 500,
        };
    }

    pub fn recreate() RecoveryContext {
        return .{
            .strategy = .recreate_resource,
            .max_retries = 1,
            .retry_delay_ms = 0,
        };
    }

    pub fn fallback() RecoveryContext {
        return .{
            .strategy = .fallback,
            .max_retries = 0,
            .retry_delay_ms = 0,
        };
    }

    pub fn abort() RecoveryContext {
        return .{
            .strategy = .abort,
            .max_retries = 0,
            .retry_delay_ms = 0,
        };
    }
};

/// Retry with exponential backoff
pub fn retryWithBackoff(
    comptime func: anytype,
    args: anytype,
    recovery: RecoveryContext,
    source_location: std.builtin.SourceLocation,
) !@TypeOf(func(args)) {
    var attempt: u32 = 0;
    var delay_ms = recovery.retry_delay_ms;

    while (attempt < recovery.max_retries) : (attempt += 1) {
        if (func(args)) |result| {
            if (attempt > 0) {
                log.info("Succeeded after {} retries at {}:{}", .{
                    attempt,
                    source_location.file,
                    source_location.line,
                });
            }
            return result;
        } else |err| {
            log.warn("Attempt {}/{} failed with {} at {}:{}", .{
                attempt + 1,
                recovery.max_retries,
                @errorName(err),
                source_location.file,
                source_location.line,
            });

            if (attempt < recovery.max_retries - 1) {
                std.time.sleep(delay_ms * std.time.ns_per_ms);
                delay_ms *= 2; // Exponential backoff
            } else {
                return err;
            }
        }
    }

    unreachable;
}

/// Common Vulkan error descriptions
pub const ErrorDescriptions = struct {
    pub fn getDescription(err: errors.Error) []const u8 {
        return switch (err) {
            errors.BaseError.LibraryNotFound => "Vulkan library (libvulkan.so) not found. Install vulkan-icd-loader",
            errors.BaseError.MissingSymbol => "Required Vulkan symbol not found in library",
            errors.BaseError.LayerNotPresent => "Requested validation layer not available",
            errors.BaseError.ExtensionNotPresent => "Requested extension not supported",
            errors.BaseError.NoPhysicalDevices => "No Vulkan-capable GPU found",
            errors.BaseError.QueueFamilyNotFound => "Required queue family not available",
            errors.BaseError.InstanceCreationFailed => "Failed to create Vulkan instance",
            errors.BaseError.DeviceCreationFailed => "Failed to create logical device",
            errors.BaseError.DebugMessengerUnavailable => "Debug messenger extension not available",
            errors.BaseError.SuitableDeviceNotFound => "No GPU meets the requirements",
            errors.VkError.NotReady => "Resource not ready yet",
            errors.VkError.Timeout => "Operation timed out",
            errors.VkError.EventSet => "Event is signaled",
            errors.VkError.EventReset => "Event is unsignaled",
            errors.VkError.Incomplete => "Return array too small",
            errors.VkError.OutOfHostMemory => "Host memory allocation failed",
            errors.VkError.OutOfDeviceMemory => "Device memory allocation failed",
            errors.VkError.InitializationFailed => "Initialization failed",
            errors.VkError.DeviceLost => "Device lost (driver crash or hang)",
            errors.VkError.MemoryMapFailed => "Memory mapping failed",
            errors.VkError.FeatureNotPresent => "Required feature not supported",
            errors.VkError.IncompatibleDriver => "Driver version incompatible",
            errors.VkError.TooManyObjects => "Too many objects allocated",
            errors.VkError.FormatNotSupported => "Image format not supported",
            errors.VkError.FragmentedPool => "Pool allocation failed due to fragmentation",
            errors.VkError.OutOfDate => "Swapchain out of date (window resized)",
            errors.VkError.SurfaceLost => "Surface lost (window destroyed)",
            errors.VkError.Unknown => "Unknown error occurred",
        };
    }

    pub fn getSolution(err: errors.Error) []const u8 {
        return switch (err) {
            errors.BaseError.LibraryNotFound => "Install Vulkan ICD loader (vulkan-icd-loader on Arch)",
            errors.BaseError.ExtensionNotPresent => "Update GPU drivers or check extension availability",
            errors.BaseError.NoPhysicalDevices => "Ensure GPU drivers are installed correctly",
            errors.VkError.OutOfHostMemory => "Reduce memory usage or increase system RAM",
            errors.VkError.OutOfDeviceMemory => "Reduce VRAM usage or use lower quality settings",
            errors.VkError.DeviceLost => "Check dmesg for GPU errors, may need driver update",
            errors.VkError.IncompatibleDriver => "Update GPU drivers to latest version",
            errors.VkError.OutOfDate => "Recreate swapchain with new surface size",
            errors.VkError.SurfaceLost => "Recreate surface and swapchain",
            else => "Check Vulkan documentation for details",
        };
    }
};

/// Helper macro-like function for error context
pub inline fn checkVk(
    result: types.VkResult,
    comptime message: []const u8,
) !void {
    return ensureSuccessWithContext(
        result,
        @src(),
        message,
    );
}
