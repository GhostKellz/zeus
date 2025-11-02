//! Sparse memory binding support for large virtual textures and buffers

const std = @import("std");
const types = @import("types.zig");

const log = std.log.scoped(.sparse_memory);

pub const SparseMemoryManager = struct {
    allocator: std.mem.Allocator,
    device: types.VkDevice,
    sparse_queue: types.VkQueue,
    bound_regions: std.ArrayList(BoundRegion),

    const BoundRegion = struct {
        resource: types.VkDeviceMemory,
        offset: types.VkDeviceSize,
        size: types.VkDeviceSize,
        memory_offset: types.VkDeviceSize,
    };

    pub fn init(allocator: std.mem.Allocator, device: types.VkDevice, queue: types.VkQueue) SparseMemoryManager {
        return .{
            .allocator = allocator,
            .device = device,
            .sparse_queue = queue,
            .bound_regions = std.ArrayList(BoundRegion).init(allocator),
        };
    }

    pub fn deinit(self: *SparseMemoryManager) void {
        self.bound_regions.deinit();
    }

    /// Bind memory to sparse resource
    pub fn bindMemory(
        self: *SparseMemoryManager,
        resource_offset: types.VkDeviceSize,
        size: types.VkDeviceSize,
        memory: types.VkDeviceMemory,
        memory_offset: types.VkDeviceSize,
    ) !void {
        const region = BoundRegion{
            .resource = memory,
            .offset = resource_offset,
            .size = size,
            .memory_offset = memory_offset,
        };

        try self.bound_regions.append(region);
        log.info("Bound sparse memory: offset={} size={} bytes", .{resource_offset, size});
    }

    /// Check if sparse binding is supported
    pub fn checkSparseSupport(physical_device_features: types.VkPhysicalDeviceFeatures) bool {
        return physical_device_features.sparseBinding != 0 and
               physical_device_features.sparseResidencyBuffer != 0;
    }

    pub fn printStatistics(self: *SparseMemoryManager) void {
        log.info("=== Sparse Memory Statistics ===", .{});
        log.info("Bound regions: {}", .{self.bound_regions.items.len});

        var total_size: u64 = 0;
        for (self.bound_regions.items) |region| {
            total_size += region.size;
        }

        log.info("Total bound memory: {} bytes ({d:.2} MB)", .{total_size, @as(f64, @floatFromInt(total_size)) / (1024.0 * 1024.0)});
        log.info("", .{});
    }
};
