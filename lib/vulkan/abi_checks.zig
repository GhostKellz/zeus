//! ABI sanity checks for Vulkan function pointers and structs
//!
//! Compile-time validation that:
//! - All function pointers use C calling convention
//! - Struct sizes/alignment match expectations
//! - No ABI mismatches between declarations

const std = @import("std");
const types = @import("types.zig");

/// Compile-time check that a function pointer type uses C calling convention
pub fn assertCCallingConvention(comptime FnPtr: type) void {
    const type_info = @typeInfo(FnPtr);
    if (type_info != .Pointer) {
        @compileError("Expected pointer type, got: " ++ @typeName(FnPtr));
    }

    const ptr_info = type_info.Pointer;
    if (ptr_info.size != .One) {
        @compileError("Expected single-item pointer");
    }

    const child_info = @typeInfo(ptr_info.child);
    if (child_info != .Fn) {
        @compileError("Expected function pointer, got pointer to: " ++ @typeName(ptr_info.child));
    }

    const fn_info = child_info.Fn;
    if (fn_info.calling_convention != .C) {
        @compileError("Function pointer must use C calling convention: " ++ @typeName(FnPtr));
    }
}

/// Compile-time struct size validation
pub fn assertStructSize(comptime T: type, comptime expected_size: comptime_int) void {
    const actual_size = @sizeOf(T);
    if (actual_size != expected_size) {
        @compileError(std.fmt.comptimePrint(
            "Struct {s} has unexpected size: expected {}, got {}",
            .{@typeName(T), expected_size, actual_size}
        ));
    }
}

/// Run all ABI checks at compile time
pub fn runABIChecks() void {
    // Check critical function pointer types use C calling convention
    assertCCallingConvention(types.PFN_vkGetInstanceProcAddr);
    assertCCallingConvention(types.PFN_vkGetDeviceProcAddr);
    assertCCallingConvention(types.PFN_vkCreateInstance);
    assertCCallingConvention(types.PFN_vkCreateDevice);
    assertCCallingConvention(types.PFN_vkDestroyInstance);
    assertCCallingConvention(types.PFN_vkDestroyDevice);

    // Validate struct layouts are extern
    comptime {
        // These must be extern structs for ABI compatibility
        const vk_instance_create_info_info = @typeInfo(types.VkInstanceCreateInfo);
        if (vk_instance_create_info_info.Struct.layout != .@"extern") {
            @compileError("VkInstanceCreateInfo must be extern struct");
        }

        const vk_device_create_info_info = @typeInfo(types.VkDeviceCreateInfo);
        if (vk_device_create_info_info.Struct.layout != .@"extern") {
            @compileError("VkDeviceCreateInfo must be extern struct");
        }
    }

    // Validate critical types have expected sizes
    // VkBool32 must be 32 bits
    if (@sizeOf(types.VkBool32) != 4) {
        @compileError("VkBool32 must be 4 bytes");
    }

    // Handles must be pointer-sized
    if (@sizeOf(types.VkInstance) != @sizeOf(?*anyopaque)) {
        @compileError("VkInstance handle size mismatch");
    }

    if (@sizeOf(types.VkDevice) != @sizeOf(?*anyopaque)) {
        @compileError("VkDevice handle size mismatch");
    }
}

// Run checks at comptime
comptime {
    runABIChecks();
}
