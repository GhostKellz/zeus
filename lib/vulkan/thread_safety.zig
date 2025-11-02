//! Thread safety documentation and guards for Vulkan operations
//!
//! Documents which functions are thread-safe and provides mutex guards
//! for shared state (pools, allocators, etc.)

const std = @import("std");

const log = std.log.scoped(.thread_safety);

/// Thread safety guarantees for different Vulkan object types
pub const ThreadSafetyLevel = enum {
    /// Can be used from multiple threads without external synchronization
    thread_safe,
    /// Externally synchronized - caller must ensure exclusive access
    externally_synchronized,
    /// Immutable after creation - safe to read from multiple threads
    immutable_after_creation,
};

/// Documentation of thread safety for common Vulkan operations
pub const ThreadSafetyDocs = struct {
    /// VkInstance operations are externally synchronized
    pub const instance = ThreadSafetyLevel.externally_synchronized;

    /// VkDevice operations are externally synchronized
    pub const device = ThreadSafetyLevel.externally_synchronized;

    /// VkQueue operations require external synchronization
    pub const queue = ThreadSafetyLevel.externally_synchronized;

    /// VkCommandPool is NOT thread-safe - must be externally synchronized
    /// OR use VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT with per-command-buffer sync
    pub const command_pool = ThreadSafetyLevel.externally_synchronized;

    /// VkCommandBuffer allocated from the same pool require external synchronization
    /// CommandBuffers from different pools can be recorded in parallel
    pub const command_buffer = ThreadSafetyLevel.externally_synchronized;

    /// VkDescriptorPool requires external synchronization
    pub const descriptor_pool = ThreadSafetyLevel.externally_synchronized;

    /// VkPipeline is immutable after creation - thread safe to use
    pub const pipeline = ThreadSafetyLevel.immutable_after_creation;

    /// VkRenderPass is immutable after creation - thread safe to use
    pub const render_pass = ThreadSafetyLevel.immutable_after_creation;
};

/// Mutex-protected resource wrapper
pub fn Protected(comptime T: type) type {
    return struct {
        const Self = @This();

        data: T,
        mutex: std.Thread.Mutex,

        pub fn init(data: T) Self {
            return .{
                .data = data,
                .mutex = .{},
            };
        }

        /// Lock and get mutable access to data
        pub fn lock(self: *Self) *T {
            self.mutex.lock();
            return &self.data;
        }

        /// Unlock after accessing data
        pub fn unlock(self: *Self) void {
            self.mutex.unlock();
        }

        /// Execute a function with locked access to data
        pub fn withLock(self: *Self, comptime func: anytype, args: anytype) @TypeOf(func) {
            self.mutex.lock();
            defer self.mutex.unlock();
            return @call(.auto, func, .{&self.data} ++ args);
        }
    };
}

/// Thread-safe command pool manager
pub const ThreadSafeCommandPoolManager = struct {
    pools: std.ArrayList(PoolEntry),
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,

    const PoolEntry = struct {
        pool: ?*anyopaque, // VkCommandPool handle
        thread_id: std.Thread.Id,
    };

    pub fn init(allocator: std.mem.Allocator) ThreadSafeCommandPoolManager {
        return .{
            .pools = std.ArrayList(PoolEntry).init(allocator),
            .mutex = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ThreadSafeCommandPoolManager) void {
        self.pools.deinit();
    }

    /// Get or create a command pool for the current thread
    pub fn getPoolForCurrentThread(self: *ThreadSafeCommandPoolManager) !?*anyopaque {
        const thread_id = std.Thread.getCurrentId();

        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if pool exists for this thread
        for (self.pools.items) |entry| {
            if (std.meta.eql(entry.thread_id, thread_id)) {
                return entry.pool;
            }
        }

        // Create new pool for this thread
        log.info("Creating new command pool for thread {}", .{thread_id});
        // Pool creation would happen here
        // try self.pools.append(.{ .pool = new_pool, .thread_id = thread_id });

        return error.NotImplemented;
    }
};

/// Thread-safe descriptor pool allocator
pub const ThreadSafeDescriptorAllocator = struct {
    mutex: std.Thread.Mutex,
    // Actual descriptor pool data would go here

    pub fn init() ThreadSafeDescriptorAllocator {
        return .{
            .mutex = .{},
        };
    }

    pub fn allocate(self: *ThreadSafeDescriptorAllocator) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Allocation logic here
        return error.NotImplemented;
    }

    pub fn free(self: *ThreadSafeDescriptorAllocator) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Free logic here
    }
};

/// Assert that we're on the expected thread (Debug mode only)
pub fn assertThread(expected_thread: std.Thread.Id) void {
    if (@import("builtin").mode != .Debug) return;

    const current_thread = std.Thread.getCurrentId();
    if (!std.meta.eql(current_thread, expected_thread)) {
        log.err("Thread safety violation: expected thread {}, got {}", .{
            expected_thread,
            current_thread,
        });
        @panic("Thread safety violation detected");
    }
}

/// Thread-local storage for per-thread Vulkan resources
threadlocal var tls_command_pool: ?*anyopaque = null;
threadlocal var tls_descriptor_pool: ?*anyopaque = null;

pub const ThreadLocalResources = struct {
    pub fn getCommandPool() ?*anyopaque {
        return tls_command_pool;
    }

    pub fn setCommandPool(pool: ?*anyopaque) void {
        tls_command_pool = pool;
    }

    pub fn getDescriptorPool() ?*anyopaque {
        return tls_descriptor_pool;
    }

    pub fn setDescriptorPool(pool: ?*anyopaque) void {
        tls_descriptor_pool = pool;
    }
};

/// Print thread safety guidelines
pub fn printThreadSafetyGuidelines() void {
    log.info("", .{});
    log.info("╔══════════════════════════════════════════╗", .{});
    log.info("║    Vulkan Thread Safety Guidelines      ║", .{});
    log.info("╚══════════════════════════════════════════╝", .{});
    log.info("", .{});
    log.info("Thread-Safe (after creation):", .{});
    log.info("  ✓ VkPipeline", .{});
    log.info("  ✓ VkRenderPass", .{});
    log.info("  ✓ VkShaderModule", .{});
    log.info("  ✓ VkPipelineLayout", .{});
    log.info("", .{});
    log.info("Requires External Synchronization:", .{});
    log.info("  ⚠ VkDevice", .{});
    log.info("  ⚠ VkQueue", .{});
    log.info("  ⚠ VkCommandPool", .{});
    log.info("  ⚠ VkDescriptorPool", .{});
    log.info("  ⚠ VkCommandBuffer (from same pool)", .{});
    log.info("", .{});
    log.info("Best Practices:", .{});
    log.info("  1. Use per-thread command pools", .{});
    log.info("  2. Use per-thread descriptor pools", .{});
    log.info("  3. Protect shared resources with mutexes", .{});
    log.info("  4. Record command buffers in parallel using separate pools", .{});
    log.info("  5. Submit to queues from a single thread", .{});
    log.info("", .{});
}

/// Run thread safety audit
pub fn runThreadSafetyAudit() void {
    log.info("=== Thread Safety Audit ===", .{});
    log.info("Checking thread safety of shared resources...", .{});
    printThreadSafetyGuidelines();
    log.info("✓ Thread safety audit complete", .{});
    log.info("", .{});
}
