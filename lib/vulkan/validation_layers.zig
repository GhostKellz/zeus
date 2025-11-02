//! Automatic validation layer enablement for Debug builds
//!
//! Enables VK_LAYER_KHRONOS_validation in Debug mode with:
//! - Parsed and pretty-printed validation messages
//! - Optional fatal warnings (ZEUS_STRICT_VALIDATION=1)
//! - Per-message-type filtering and statistics

const std = @import("std");
const types = @import("types.zig");
const builtin = @import("builtin");

const log = std.log.scoped(.validation);

/// Validation message severity
pub const MessageSeverity = enum {
    verbose,
    info,
    warning,
    error_,

    pub fn fromVulkan(severity: types.VkDebugUtilsMessageSeverityFlagBitsEXT) MessageSeverity {
        return switch (severity) {
            .VERBOSE_BIT_EXT => .verbose,
            .INFO_BIT_EXT => .info,
            .WARNING_BIT_EXT => .warning,
            .ERROR_BIT_EXT => .error_,
            else => .info,
        };
    }
};

/// Validation message type
pub const MessageType = enum {
    general,
    validation,
    performance,

    pub fn fromVulkan(type_flags: types.VkDebugUtilsMessageTypeFlagsEXT) MessageType {
        if (type_flags & @intFromEnum(types.VkDebugUtilsMessageTypeFlagBitsEXT.VALIDATION_BIT_EXT) != 0) {
            return .validation;
        }
        if (type_flags & @intFromEnum(types.VkDebugUtilsMessageTypeFlagBitsEXT.PERFORMANCE_BIT_EXT) != 0) {
            return .performance;
        }
        return .general;
    }
};

/// Validation statistics
pub const ValidationStats = struct {
    verbose_count: u64 = 0,
    info_count: u64 = 0,
    warning_count: u64 = 0,
    error_count: u64 = 0,
    mutex: std.Thread.Mutex = .{},

    pub fn record(self: *ValidationStats, severity: MessageSeverity) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        switch (severity) {
            .verbose => self.verbose_count += 1,
            .info => self.info_count += 1,
            .warning => self.warning_count += 1,
            .error_ => self.error_count += 1,
        }
    }

    pub fn print(self: *ValidationStats) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        log.info("=== Validation Statistics ===", .{});
        log.info("Verbose: {}", .{self.verbose_count});
        log.info("Info:    {}", .{self.info_count});
        log.info("Warning: {}", .{self.warning_count});
        log.info("Error:   {}", .{self.error_count});
        log.info("", .{});
    }
};

/// Global validation statistics
var global_stats = ValidationStats{};

/// Check if strict validation mode is enabled
pub fn isStrictValidationEnabled() bool {
    const env_value = std.process.getEnvVarOwned(std.heap.page_allocator, "ZEUS_STRICT_VALIDATION") catch return false;
    defer std.heap.page_allocator.free(env_value);

    return std.mem.eql(u8, env_value, "1") or
           std.mem.eql(u8, env_value, "true") or
           std.mem.eql(u8, env_value, "TRUE");
}

/// Debug messenger callback
pub fn debugCallback(
    message_severity: types.VkDebugUtilsMessageSeverityFlagBitsEXT,
    message_types: types.VkDebugUtilsMessageTypeFlagsEXT,
    callback_data: ?*const types.VkDebugUtilsMessengerCallbackDataEXT,
    user_data: ?*anyopaque,
) callconv(.C) types.VkBool32 {
    _ = user_data;

    const data = callback_data orelse return types.VK_FALSE;
    const severity = MessageSeverity.fromVulkan(message_severity);
    const msg_type = MessageType.fromVulkan(message_types);

    // Record statistics
    global_stats.record(severity);

    // Get message ID name and message
    const id_name = if (data.pMessageIdName != null)
        std.mem.sliceTo(data.pMessageIdName.?, 0)
    else
        "unknown";

    const message = if (data.pMessage != null)
        std.mem.sliceTo(data.pMessage.?, 0)
    else
        "";

    // Format and log based on severity
    const prefix = switch (msg_type) {
        .validation => "VALIDATION",
        .performance => "PERFORMANCE",
        .general => "GENERAL",
    };

    switch (severity) {
        .verbose => {
            log.debug("[{s}] {s}: {s}", .{prefix, id_name, message});
        },
        .info => {
            log.info("[{s}] {s}: {s}", .{prefix, id_name, message});
        },
        .warning => {
            log.warn("[{s}] {s}: {s}", .{prefix, id_name, message});

            if (isStrictValidationEnabled()) {
                log.err("STRICT VALIDATION: Treating warning as error", .{});
                return types.VK_TRUE; // Abort on warning in strict mode
            }
        },
        .error_ => {
            log.err("[{s}] {s}: {s}", .{prefix, id_name, message});

            // Print object info if available
            if (data.objectCount > 0 and data.pObjects != null) {
                const objects = data.pObjects.?[0..data.objectCount];
                for (objects, 0..) |obj, i| {
                    const obj_name = if (obj.pObjectName != null)
                        std.mem.sliceTo(obj.pObjectName.?, 0)
                    else
                        "unnamed";

                    log.err("  Object[{}]: type={} handle=0x{x} name={s}", .{
                        i,
                        obj.objectType,
                        obj.objectHandle,
                        obj_name,
                    });
                }
            }
        },
    }

    return types.VK_FALSE; // Don't abort (unless strict mode warning)
}

/// Create debug messenger for validation layers
pub fn createDebugMessenger(
    instance_dispatch: anytype,
    instance: types.VkInstance,
) !types.VkDebugUtilsMessengerEXT {
    const create_info = types.VkDebugUtilsMessengerCreateInfoEXT{
        .sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        .pNext = null,
        .flags = 0,
        .messageSeverity = @intFromEnum(types.VkDebugUtilsMessageSeverityFlagBitsEXT.VERBOSE_BIT_EXT) |
                          @intFromEnum(types.VkDebugUtilsMessageSeverityFlagBitsEXT.INFO_BIT_EXT) |
                          @intFromEnum(types.VkDebugUtilsMessageSeverityFlagBitsEXT.WARNING_BIT_EXT) |
                          @intFromEnum(types.VkDebugUtilsMessageSeverityFlagBitsEXT.ERROR_BIT_EXT),
        .messageType = @intFromEnum(types.VkDebugUtilsMessageTypeFlagBitsEXT.GENERAL_BIT_EXT) |
                      @intFromEnum(types.VkDebugUtilsMessageTypeFlagBitsEXT.VALIDATION_BIT_EXT) |
                      @intFromEnum(types.VkDebugUtilsMessageTypeFlagBitsEXT.PERFORMANCE_BIT_EXT),
        .pfnUserCallback = debugCallback,
        .pUserData = null,
    };

    var messenger: types.VkDebugUtilsMessengerEXT = undefined;
    const result = instance_dispatch.create_debug_utils_messenger_ext(
        instance,
        &create_info,
        null,
        &messenger,
    );

    if (result != .SUCCESS) {
        return error.FailedToCreateDebugMessenger;
    }

    log.info("Validation layer debug messenger created", .{});
    if (isStrictValidationEnabled()) {
        log.warn("STRICT VALIDATION MODE: Warnings will be treated as errors", .{});
    }

    return messenger;
}

/// Should validation layers be enabled?
pub fn shouldEnableValidation() bool {
    // Always enable in Debug mode
    if (builtin.mode == .Debug) {
        return true;
    }

    // Check environment variable for Release builds
    const env_value = std.process.getEnvVarOwned(
        std.heap.page_allocator,
        "ZEUS_ENABLE_VALIDATION",
    ) catch return false;
    defer std.heap.page_allocator.free(env_value);

    return std.mem.eql(u8, env_value, "1") or
           std.mem.eql(u8, env_value, "true") or
           std.mem.eql(u8, env_value, "TRUE");
}

/// Get validation layer names to enable
pub fn getValidationLayers() []const [*:0]const u8 {
    const layers = [_][*:0]const u8{
        "VK_LAYER_KHRONOS_validation",
    };
    return &layers;
}

/// Print validation statistics
pub fn printValidationStats() void {
    global_stats.print();
}
