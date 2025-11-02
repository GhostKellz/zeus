//! Multi-GPU support with device groups and inter-GPU synchronization

const std = @import("std");
const types = @import("types.zig");

const log = std.log.scoped(.multi_gpu);

pub const MultiGPUManager = struct {
    allocator: std.mem.Allocator,
    physical_devices: []types.VkPhysicalDevice,
    device_group: ?types.VkDeviceGroupDeviceCreateInfo,
    device_mask: u32,

    pub fn init(allocator: std.mem.Allocator) MultiGPUManager {
        return .{
            .allocator = allocator,
            .physical_devices = &.{},
            .device_group = null,
            .device_mask = 0,
        };
    }

    pub fn deinit(self: *MultiGPUManager) void {
        if (self.physical_devices.len > 0) {
            self.allocator.free(self.physical_devices);
        }
    }

    /// Enumerate available GPUs
    pub fn enumerateGPUs(
        self: *MultiGPUManager,
        instance_dispatch: anytype,
        instance: types.VkInstance,
    ) !void {
        var count: u32 = 0;
        _ = instance_dispatch.enumerate_physical_devices(instance, &count, null);

        if (count == 0) return error.NoPhysicalDevices;

        const devices = try self.allocator.alloc(types.VkPhysicalDevice, count);
        _ = instance_dispatch.enumerate_physical_devices(instance, &count, devices.ptr);

        self.physical_devices = devices;

        log.info("Found {} physical device(s)", .{count});

        for (devices, 0..) |device, i| {
            var props: types.VkPhysicalDeviceProperties = undefined;
            instance_dispatch.get_physical_device_properties(device, &props);

            const name = std.mem.sliceTo(&props.deviceName, 0);
            log.info("  GPU {}: {s} (type={})", .{i, name, props.deviceType});
        }
    }

    /// Enable multi-GPU mode for device creation
    pub fn enableMultiGPU(self: *MultiGPUManager, device_indices: []const u32) !void {
        if (device_indices.len < 2) {
            return error.NeedAtLeastTwoDevices;
        }

        self.device_mask = 0;
        for (device_indices) |idx| {
            if (idx >= 32) return error.DeviceIndexTooLarge;
            self.device_mask |= (@as(u32, 1) << @intCast(idx));
        }

        log.info("Enabled multi-GPU with device mask: 0x{x}", .{self.device_mask});
        log.info("Active devices: {}", .{device_indices.len});
    }

    /// Get device mask for rendering
    pub fn getDeviceMask(self: *MultiGPUManager) u32 {
        return if (self.device_mask != 0) self.device_mask else 1;
    }

    /// Check if multi-GPU is enabled
    pub fn isMultiGPUEnabled(self: *MultiGPUManager) bool {
        return self.device_mask != 0 and @popCount(self.device_mask) > 1;
    }

    /// Print multi-GPU configuration
    pub fn printConfiguration(self: *MultiGPUManager) void {
        log.info("=== Multi-GPU Configuration ===", .{});
        log.info("Available GPUs: {}", .{self.physical_devices.len});
        log.info("Multi-GPU enabled: {}", .{self.isMultiGPUEnabled()});
        log.info("Device mask: 0x{x}", .{self.device_mask});
        log.info("Active devices: {}", .{@popCount(self.device_mask)});
        log.info("", .{});
    }
};

/// Split-frame rendering mode for multi-GPU
pub const SplitFrameMode = enum {
    /// Alternate frames between GPUs
    alternate_frame,
    /// Split screen space between GPUs
    split_screen,
    /// Split workload by draw calls
    split_workload,
};

/// Multi-GPU rendering coordinator
pub const RenderCoordinator = struct {
    mode: SplitFrameMode,
    current_device_index: u32,
    frame_count: u64,

    pub fn init(mode: SplitFrameMode) RenderCoordinator {
        return .{
            .mode = mode,
            .current_device_index = 0,
            .frame_count = 0,
        };
    }

    /// Get device index for current frame
    pub fn getCurrentDevice(self: *RenderCoordinator, device_count: u32) u32 {
        return switch (self.mode) {
            .alternate_frame => @intCast(self.frame_count % device_count),
            .split_screen, .split_workload => 0, // Would implement proper splitting
        };
    }

    /// Advance to next frame
    pub fn nextFrame(self: *RenderCoordinator) void {
        self.frame_count += 1;
        self.current_device_index = @intCast(self.frame_count % 32);
    }
};
