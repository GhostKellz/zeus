//! Vulkan memory budget tracking using VK_EXT_memory_budget

const std = @import("std");
const types = @import("types.zig");

const log = std.log.scoped(.memory_budget);

pub const MemoryBudgetTracker = struct {
    allocator: std.mem.Allocator,
    memory_heaps: []HeapBudget,
    last_update: i64,
    update_interval_ms: u64,

    pub const HeapBudget = struct {
        heap_index: u32,
        budget: types.VkDeviceSize,
        usage: types.VkDeviceSize,
        available: types.VkDeviceSize,
    };

    pub fn init(allocator: std.mem.Allocator, heap_count: u32) !*MemoryBudgetTracker {
        const self = try allocator.create(MemoryBudgetTracker);
        const heaps = try allocator.alloc(HeapBudget, heap_count);

        for (heaps, 0..) |*heap, i| {
            heap.* = .{
                .heap_index = @intCast(i),
                .budget = 0,
                .usage = 0,
                .available = 0,
            };
        }

        self.* = .{
            .allocator = allocator,
            .memory_heaps = heaps,
            .last_update = 0,
            .update_interval_ms = 100, // Update every 100ms
        };

        return self;
    }

    pub fn deinit(self: *MemoryBudgetTracker) void {
        self.allocator.free(self.memory_heaps);
        self.allocator.destroy(self);
    }

    /// Update budget information
    pub fn update(self: *MemoryBudgetTracker) void {
        const now = std.time.milliTimestamp();
        const elapsed = now - self.last_update;

        if (elapsed < self.update_interval_ms) {
            return; // Don't update too frequently
        }

        // Would query VK_EXT_memory_budget here
        self.last_update = now;
        log.debug("Updated memory budget information", .{});
    }

    /// Check if allocation would exceed budget
    pub fn canAllocate(self: *MemoryBudgetTracker, heap_index: u32, size: types.VkDeviceSize) bool {
        if (heap_index >= self.memory_heaps.len) return false;

        const heap = &self.memory_heaps[heap_index];
        return (heap.usage + size) <= heap.budget;
    }

    /// Record allocation
    pub fn recordAllocation(self: *MemoryBudgetTracker, heap_index: u32, size: types.VkDeviceSize) void {
        if (heap_index >= self.memory_heaps.len) return;

        self.memory_heaps[heap_index].usage += size;
        self.memory_heaps[heap_index].available = self.memory_heaps[heap_index].budget -
                                                   self.memory_heaps[heap_index].usage;
    }

    /// Record free
    pub fn recordFree(self: *MemoryBudgetTracker, heap_index: u32, size: types.VkDeviceSize) void {
        if (heap_index >= self.memory_heaps.len) return;

        if (self.memory_heaps[heap_index].usage >= size) {
            self.memory_heaps[heap_index].usage -= size;
        } else {
            self.memory_heaps[heap_index].usage = 0;
        }

        self.memory_heaps[heap_index].available = self.memory_heaps[heap_index].budget -
                                                   self.memory_heaps[heap_index].usage;
    }

    /// Print budget information
    pub fn printBudgets(self: *MemoryBudgetTracker) void {
        log.info("=== Memory Budget Status ===", .{});

        for (self.memory_heaps) |heap| {
            const usage_mb = @as(f64, @floatFromInt(heap.usage)) / (1024.0 * 1024.0);
            const budget_mb = @as(f64, @floatFromInt(heap.budget)) / (1024.0 * 1024.0);
            const usage_percent = if (heap.budget > 0)
                (@as(f64, @floatFromInt(heap.usage)) / @as(f64, @floatFromInt(heap.budget))) * 100.0
            else
                0.0;

            log.info("Heap {}: {d:.1}/{d:.1} MB ({d:.1}%)", .{
                heap.heap_index,
                usage_mb,
                budget_mb,
                usage_percent,
            });
        }
        log.info("", .{});
    }

    /// Check if close to budget limit
    pub fn isNearBudgetLimit(self: *MemoryBudgetTracker, heap_index: u32, threshold_percent: f32) bool {
        if (heap_index >= self.memory_heaps.len) return false;

        const heap = &self.memory_heaps[heap_index];
        if (heap.budget == 0) return false;

        const usage_percent = (@as(f64, @floatFromInt(heap.usage)) / @as(f64, @floatFromInt(heap.budget))) * 100.0;
        return usage_percent >= threshold_percent;
    }
};
