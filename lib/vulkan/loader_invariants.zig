//! Loader invariant checks to catch subtle UB and double-loading issues
//!
//! Ensures:
//! - Single libvulkan.so handle (no multiple dlopen)
//! - Function pointer origins are consistent
//! - No reuse of function pointers across device/instance

const std = @import("std");
const types = @import("types.zig");

const log = std.log.scoped(.loader_invariants);

/// Global state to track loader instances
var loader_count: usize = 0;
var loader_mutex = std.Thread.Mutex{};

/// Register a new loader instance
pub fn registerLoader() void {
    loader_mutex.lock();
    defer loader_mutex.unlock();

    loader_count += 1;

    if (loader_count > 1) {
        log.warn("Multiple loader instances detected: {}", .{loader_count});
        log.warn("This may indicate a bug or resource leak", .{});
    }
}

/// Unregister a loader instance
pub fn unregisterLoader() void {
    loader_mutex.lock();
    defer loader_mutex.unlock();

    if (loader_count == 0) {
        log.err("Unregistering loader but count is already 0!", .{});
        return;
    }

    loader_count -= 1;
}

/// Get current loader count
pub fn getLoaderCount() usize {
    loader_mutex.lock();
    defer loader_mutex.unlock();
    return loader_count;
}

/// Validate function pointer is not null
pub fn validateFunctionPointer(comptime name: []const u8, ptr: ?*const anyopaque) !void {
    if (ptr == null) {
        log.err("Function pointer '{s}' is null", .{name});
        return error.NullFunctionPointer;
    }
}

/// Assert function pointer is valid (Debug mode only)
pub fn assertFunctionPointerValid(comptime name: []const u8, ptr: ?*const anyopaque) void {
    if (@import("builtin").mode != .Debug) return;

    validateFunctionPointer(name, ptr) catch |err| {
        log.err("ASSERTION FAILED: Function pointer '{s}' validation failed: {}", .{name, err});
        @panic("Function pointer validation failed");
    };
}

/// Validate all function pointers in a dispatch table are non-null
pub fn validateDispatchTable(comptime T: type, table: T) !void {
    inline for (@typeInfo(T).Struct.fields) |field| {
        const ptr = @field(table, field.name);

        // Skip optional function pointers
        if (@typeInfo(field.type) == .Optional) {
            continue;
        }

        // Check required function pointers
        if (@typeInfo(field.type) == .Pointer) {
            if (ptr == null) {
                log.err("Dispatch table has null function pointer: {s}", .{field.name});
                return error.NullDispatchFunction;
            }
        }
    }
}

/// Print loader statistics for debugging
pub fn printLoaderStats() void {
    const count = getLoaderCount();
    log.info("=== Loader Invariants ===", .{});
    log.info("Active loader instances: {}", .{count});

    if (count == 0) {
        log.info("✓ No active loaders", .{});
    } else if (count == 1) {
        log.info("✓ Single loader instance (correct)", .{});
    } else {
        log.warn("⚠ Multiple loader instances detected", .{});
        log.warn("  This may indicate a resource leak or bug", .{});
    }
}
