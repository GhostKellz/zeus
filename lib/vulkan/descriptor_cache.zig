//! Descriptor set caching for reduced allocation overhead
//!
//! Caches and reuses descriptor sets based on their binding configuration
//! to avoid redundant allocations

const std = @import("std");
const types = @import("types.zig");

const log = std.log.scoped(.descriptor_cache);

/// Descriptor set binding signature for cache key
pub const BindingSignature = struct {
    layout: types.VkDescriptorSetLayout,
    bindings_hash: u64,

    pub fn init(layout: types.VkDescriptorSetLayout, bindings: []const types.VkDescriptorSetLayoutBinding) BindingSignature {
        // Hash the binding configuration
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&layout));
        for (bindings) |binding| {
            hasher.update(std.mem.asBytes(&binding));
        }

        return .{
            .layout = layout,
            .bindings_hash = hasher.final(),
        };
    }

    pub fn hash(self: BindingSignature) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&self.layout));
        hasher.update(std.mem.asBytes(&self.bindings_hash));
        return hasher.final();
    }

    pub fn eql(a: BindingSignature, b: BindingSignature) bool {
        return @intFromPtr(a.layout) == @intFromPtr(b.layout) and a.bindings_hash == b.bindings_hash;
    }
};

/// Cached descriptor set entry
const CachedDescriptorSet = struct {
    set: types.VkDescriptorSet,
    signature: BindingSignature,
    last_used_frame: u64,
    use_count: u64,
};

/// Descriptor set cache
pub const DescriptorCache = struct {
    allocator: std.mem.Allocator,
    cache: std.AutoHashMap(u64, std.ArrayList(CachedDescriptorSet)),
    mutex: std.Thread.Mutex,
    current_frame: u64,
    hit_count: u64,
    miss_count: u64,
    max_cached_per_signature: usize,

    pub fn init(allocator: std.mem.Allocator) DescriptorCache {
        return .{
            .allocator = allocator,
            .cache = std.AutoHashMap(u64, std.ArrayList(CachedDescriptorSet)).init(allocator),
            .mutex = .{},
            .current_frame = 0,
            .hit_count = 0,
            .miss_count = 0,
            .max_cached_per_signature = 16,
        };
    }

    pub fn deinit(self: *DescriptorCache) void {
        var iter = self.cache.valueIterator();
        while (iter.next()) |list| {
            list.deinit();
        }
        self.cache.deinit();
    }

    /// Try to get a cached descriptor set
    pub fn get(self: *DescriptorCache, signature: BindingSignature) ?types.VkDescriptorSet {
        self.mutex.lock();
        defer self.mutex.unlock();

        const sig_hash = signature.hash();

        if (self.cache.get(sig_hash)) |*list| {
            // Find an available set
            for (list.items, 0..) |*entry, i| {
                if (entry.signature.eql(signature)) {
                    const set = entry.set;

                    // Update usage statistics
                    entry.last_used_frame = self.current_frame;
                    entry.use_count += 1;

                    // Move to front (LRU)
                    if (i > 0) {
                        const temp = entry.*;
                        list.items[i] = list.items[0];
                        list.items[0] = temp;
                    }

                    self.hit_count += 1;
                    log.debug("Cache HIT for signature hash 0x{x}", .{sig_hash});
                    return set;
                }
            }
        }

        self.miss_count += 1;
        log.debug("Cache MISS for signature hash 0x{x}", .{sig_hash});
        return null;
    }

    /// Store a descriptor set in the cache
    pub fn put(
        self: *DescriptorCache,
        signature: BindingSignature,
        set: types.VkDescriptorSet,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const sig_hash = signature.hash();

        const entry = CachedDescriptorSet{
            .set = set,
            .signature = signature,
            .last_used_frame = self.current_frame,
            .use_count = 0,
        };

        const gop = try self.cache.getOrPut(sig_hash);
        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayList(CachedDescriptorSet).init(self.allocator);
        }

        // Check if we've reached the limit
        if (gop.value_ptr.items.len >= self.max_cached_per_signature) {
            log.warn("Cache full for signature 0x{x}, evicting oldest", .{sig_hash});
            // Remove the least recently used (last in list)
            _ = gop.value_ptr.pop();
        }

        // Add to front
        try gop.value_ptr.insert(0, entry);

        log.debug("Cached descriptor set for signature 0x{x}", .{sig_hash});
    }

    /// Advance to next frame and cleanup old entries
    pub fn nextFrame(self: *DescriptorCache, max_frames_old: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.current_frame += 1;

        // Cleanup entries that haven't been used recently
        var iter = self.cache.iterator();
        while (iter.next()) |kv| {
            const list = kv.value_ptr;

            var i: usize = 0;
            while (i < list.items.len) {
                const entry = list.items[i];
                const age = self.current_frame - entry.last_used_frame;

                if (age > max_frames_old) {
                    log.debug("Evicting descriptor set (age: {} frames)", .{age});
                    _ = list.swapRemove(i);
                    // Don't increment i, check the swapped item
                } else {
                    i += 1;
                }
            }
        }
    }

    /// Print cache statistics
    pub fn printStatistics(self: *DescriptorCache) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        log.info("=== Descriptor Cache Statistics ===", .{});
        log.info("Current frame: {}", .{self.current_frame});
        log.info("Cache hits: {}", .{self.hit_count});
        log.info("Cache misses: {}", .{self.miss_count});

        const total = self.hit_count + self.miss_count;
        if (total > 0) {
            const hit_rate = (@as(f64, @floatFromInt(self.hit_count)) / @as(f64, @floatFromInt(total))) * 100.0;
            log.info("Hit rate: {d:.1}%", .{hit_rate});
        }

        var total_cached: usize = 0;
        var iter = self.cache.valueIterator();
        while (iter.next()) |list| {
            total_cached += list.items.len;
        }

        log.info("Cached descriptor sets: {}", .{total_cached});
        log.info("Unique signatures: {}", .{self.cache.count()});
        log.info("", .{});
    }

    /// Reset statistics
    pub fn resetStatistics(self: *DescriptorCache) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.hit_count = 0;
        self.miss_count = 0;
    }
};
