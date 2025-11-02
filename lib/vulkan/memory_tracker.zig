//! Memory allocation tracking for leak detection in Debug builds
//!
//! Tracks all VkDeviceMemory allocations with call site information
//! and reports leaks on shutdown

const std = @import("std");
const types = @import("types.zig");
const builtin = @import("builtin");

const log = std.log.scoped(.memory_tracker);

/// Allocation record with call site information
const AllocationRecord = struct {
    memory: types.VkDeviceMemory,
    size: types.VkDeviceSize,
    memory_type_index: u32,
    allocation_time: i64, // timestamp in nanoseconds
    call_site: std.builtin.SourceLocation,
};

/// Global memory tracker state
pub const MemoryTracker = struct {
    allocator: std.mem.Allocator,
    allocations: std.AutoHashMap(u64, AllocationRecord),
    mutex: std.Thread.Mutex,
    total_allocated: u64,
    total_freed: u64,
    peak_usage: u64,
    allocation_count: u64,
    free_count: u64,

    pub fn init(allocator: std.mem.Allocator) MemoryTracker {
        return .{
            .allocator = allocator,
            .allocations = std.AutoHashMap(u64, AllocationRecord).init(allocator),
            .mutex = .{},
            .total_allocated = 0,
            .total_freed = 0,
            .peak_usage = 0,
            .allocation_count = 0,
            .free_count = 0,
        };
    }

    pub fn deinit(self: *MemoryTracker) void {
        self.allocations.deinit();
    }

    /// Record a memory allocation
    pub fn recordAllocation(
        self: *MemoryTracker,
        memory: types.VkDeviceMemory,
        size: types.VkDeviceSize,
        memory_type_index: u32,
        call_site: std.builtin.SourceLocation,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const memory_handle = @intFromPtr(memory);
        const timestamp = std.time.nanoTimestamp();

        const record = AllocationRecord{
            .memory = memory,
            .size = size,
            .memory_type_index = memory_type_index,
            .allocation_time = timestamp,
            .call_site = call_site,
        };

        try self.allocations.put(memory_handle, record);

        self.total_allocated += size;
        self.allocation_count += 1;

        const current_usage = self.total_allocated - self.total_freed;
        if (current_usage > self.peak_usage) {
            self.peak_usage = current_usage;
        }

        log.debug("Allocated {} bytes (type {}) from {s}:{}", .{
            size,
            memory_type_index,
            call_site.file,
            call_site.line,
        });
    }

    /// Record a memory free
    pub fn recordFree(
        self: *MemoryTracker,
        memory: types.VkDeviceMemory,
        call_site: std.builtin.SourceLocation,
    ) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const memory_handle = @intFromPtr(memory);

        if (self.allocations.get(memory_handle)) |record| {
            self.total_freed += record.size;
            self.free_count += 1;

            log.debug("Freed {} bytes from {s}:{}", .{
                record.size,
                call_site.file,
                call_site.line,
            });

            _ = self.allocations.remove(memory_handle);
        } else {
            log.err("Attempted to free untracked memory from {s}:{}", .{
                call_site.file,
                call_site.line,
            });
        }
    }

    /// Print memory statistics
    pub fn printStatistics(self: *MemoryTracker) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        log.info("", .{});
        log.info("╔══════════════════════════════════════════╗", .{});
        log.info("║      Memory Allocation Statistics       ║", .{});
        log.info("╚══════════════════════════════════════════╝", .{});
        log.info("", .{});
        log.info("Total allocated:     {} bytes ({} allocations)", .{
            self.total_allocated,
            self.allocation_count,
        });
        log.info("Total freed:         {} bytes ({} frees)", .{
            self.total_freed,
            self.free_count,
        });
        log.info("Peak usage:          {} bytes", .{self.peak_usage});
        log.info("Current allocations: {}", .{self.allocations.count()});

        const current_usage = self.total_allocated - self.total_freed;
        log.info("Current usage:       {} bytes", .{current_usage});
        log.info("", .{});
    }

    /// Check for memory leaks and print detailed report
    pub fn checkLeaks(self: *MemoryTracker) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        const leak_count = self.allocations.count();

        if (leak_count == 0) {
            log.info("✓ No memory leaks detected", .{});
            return false;
        }

        log.err("", .{});
        log.err("╔══════════════════════════════════════════╗", .{});
        log.err("║       MEMORY LEAKS DETECTED              ║", .{});
        log.err("╚══════════════════════════════════════════╝", .{});
        log.err("", .{});
        log.err("Found {} leaked allocation(s):", .{leak_count});
        log.err("", .{});

        var total_leaked: u64 = 0;
        var iter = self.allocations.valueIterator();
        var index: usize = 0;

        while (iter.next()) |record| {
            index += 1;
            total_leaked += record.size;

            const age_ns = std.time.nanoTimestamp() - record.allocation_time;
            const age_ms = @divFloor(age_ns, std.time.ns_per_ms);

            log.err("Leak #{}: {} bytes (age: {}ms)", .{index, record.size, age_ms});
            log.err("  Memory type: {}", .{record.memory_type_index});
            log.err("  Allocated at: {s}:{}", .{
                record.call_site.file,
                record.call_site.line,
            });
            log.err("  Function: {s}", .{record.call_site.fn_name});
            log.err("", .{});
        }

        log.err("Total leaked: {} bytes", .{total_leaked});
        log.err("", .{});

        return true;
    }

    /// Assert no leaks (Debug mode only)
    pub fn assertNoLeaks(self: *MemoryTracker) void {
        if (builtin.mode != .Debug) return;

        if (self.checkLeaks()) {
            @panic("Memory leaks detected - see log for details");
        }
    }
};

/// Global memory tracker instance
var global_tracker: ?MemoryTracker = null;
var global_tracker_mutex = std.Thread.Mutex{};

/// Initialize global memory tracker
pub fn initGlobalTracker(allocator: std.mem.Allocator) !void {
    global_tracker_mutex.lock();
    defer global_tracker_mutex.unlock();

    if (global_tracker != null) {
        return error.TrackerAlreadyInitialized;
    }

    global_tracker = MemoryTracker.init(allocator);
    log.info("Memory tracker initialized", .{});
}

/// Deinitialize global memory tracker
pub fn deinitGlobalTracker() void {
    global_tracker_mutex.lock();
    defer global_tracker_mutex.unlock();

    if (global_tracker) |*tracker| {
        tracker.printStatistics();
        tracker.checkLeaks();
        tracker.deinit();
        global_tracker = null;
    }
}

/// Get global tracker (if enabled)
pub fn getGlobalTracker() ?*MemoryTracker {
    global_tracker_mutex.lock();
    defer global_tracker_mutex.unlock();

    if (global_tracker) |*tracker| {
        return tracker;
    }
    return null;
}

/// Record allocation in global tracker (if enabled and in Debug mode)
pub fn trackAllocation(
    memory: types.VkDeviceMemory,
    size: types.VkDeviceSize,
    memory_type_index: u32,
    call_site: std.builtin.SourceLocation,
) void {
    if (builtin.mode != .Debug) return;

    if (getGlobalTracker()) |tracker| {
        tracker.recordAllocation(memory, size, memory_type_index, call_site) catch |err| {
            log.warn("Failed to track allocation: {}", .{err});
        };
    }
}

/// Record free in global tracker (if enabled and in Debug mode)
pub fn trackFree(
    memory: types.VkDeviceMemory,
    call_site: std.builtin.SourceLocation,
) void {
    if (builtin.mode != .Debug) return;

    if (getGlobalTracker()) |tracker| {
        tracker.recordFree(memory, call_site);
    }
}
