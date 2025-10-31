# Zeus Performance Guide

**Optimization strategies for 144-360Hz text rendering**

---

## Performance Targets

| Resolution | Refresh Rate | Frame Budget | GPU Target | Status |
|------------|--------------|--------------|------------|--------|
| 1440p | 144 Hz | 6.9ms | RTX 3070+ | ✅ Phase 5 |
| 1440p | 240 Hz | 4.16ms | RTX 4070+ | 🚧 Phase 6 |
| 1440p | 270 Hz | 3.7ms | RTX 4080+ | 🔜 Phase 6 |
| 1080p | 360 Hz | 2.77ms | RTX 4090 | 🔜 Phase 7 |

---

## Frame Budget Breakdown

**Target: 240Hz @ 1440p (4.16ms total)**

```
CPU Work:        1.0ms  (frame prep, batching, command recording)
GPU Setup:       0.5ms  (barrier transitions, descriptor binds)
GPU Draw:        1.5ms  (vertex processing, fragment shading)
GPU Present:     0.5ms  (swapchain present, vsync wait)
Slack:           0.66ms (buffer for spikes)
─────────────────────────────────────────
Total:           4.16ms
```

**Critical Path:** CPU command recording is the bottleneck at high refresh rates.

---

## CPU Optimizations

### 1. Minimize Allocations

**Problem:** Allocations are slow (50-200ns each)

**Solution:** Pre-allocate and reuse

```zig
// BAD: Allocate per-frame
fn render(allocator: Allocator) !void {
    const quads = try allocator.alloc(Quad, glyph_count);  // SLOW!
    defer allocator.free(quads);
    // ...
}

// GOOD: Pre-allocate once, reuse
fn init() !*Renderer {
    var self = try allocator.create(Renderer);
    self.instance_data = try allocator.alloc(Instance, MAX_INSTANCES);
    return self;
}

fn render(self: *Renderer) !void {
    // Reuse pre-allocated buffer (fast!)
    self.frame_states[idx].instance_count = 0;
    // ...
}
```

**Savings:** ~100μs per frame (2.4% of 4.16ms budget)

### 2. Cache-Friendly Data Layout

**Problem:** Cache misses are expensive (50-200 cycles)

**Solution:** Structure of Arrays (SoA) over Array of Structures (AoS)

```zig
// BAD: AoS (cache-unfriendly)
const Glyph = struct {
    position: [2]f32,
    uv: [4]f32,
    color: [4]f32,
};
var glyphs: []Glyph;

// Iterate positions (loads color/uv unnecessarily)
for (glyphs) |g| {
    if (g.position[0] > 100) { ... }  // Cache miss!
}

// GOOD: SoA (cache-friendly)
const GlyphBatch = struct {
    positions: [][2]f32,
    uvs: [][4]f32,
    colors: [][4]f32,
};

// Only load what we need
for (batch.positions) |pos| {
    if (pos[0] > 100) { ... }  // Cache hit!
}
```

**Savings:** ~50μs per frame (1.2% of budget)

### 3. SIMD Batching (Phase 6)

**Problem:** Scalar glyph processing is slow

**Solution:** Process 4-8 glyphs at once with AVX2/AVX-512

```zig
// Scalar (current)
for (glyphs) |g| {
    instance_data[i] = transformGlyph(g);  // 1 glyph/cycle
}

// SIMD (Phase 6)
const Vec8f32 = @Vector(8, f32);
for (glyphs_chunks) |chunk| {
    const positions = @as(Vec8f32, chunk.positions);
    const transformed = positions * scale + offset;  // 8 glyphs/cycle
    @memcpy(instance_data[i..], &transformed);
}
```

**Expected Savings:** ~200μs per frame (4.8% of budget)

---

## GPU Optimizations

### 1. Instanced Rendering

**Problem:** Draw call overhead is significant

**Solution:** Single draw call for all glyphs

```zig
// BAD: Per-glyph draw calls
for (glyphs) |g| {
    vkCmdDraw(cmd, 6, 1, 0, 0);  // 1000 calls = overhead!
}

// GOOD: Single instanced draw
vkCmdDraw(cmd, 6, glyph_count, 0, 0);  // 1 call!
```

**GPU Time:** 0.5ms → 0.1ms (80% reduction)

### 2. Command Buffer Reuse

**Problem:** Recording commands is CPU-bound

**Solution:** Record once, submit multiple times

```zig
// Record when scene changes
if (scene_dirty) {
    vkBeginCommandBuffer(cmd, ...);
    vkCmdBindPipeline(...);
    vkCmdDraw(...);
    vkEndCommandBuffer(cmd);
    scene_dirty = false;
}

// Just submit (no recording)
vkQueueSubmit(queue, &submit_info, fence);
```

**Savings:** ~300μs per frame when scene static (7.2% of budget)

### 3. Descriptor Caching

**Problem:** vkUpdateDescriptorSets is slow (~10μs)

**Solution:** Only update when resources change

```zig
// Track what's bound
var bound_atlas: VkImageView = null;

// Only update if different
if (atlas_view != bound_atlas) {
    vkUpdateDescriptorSets(...);
    bound_atlas = atlas_view;
}
```

**Savings:** ~10μs per frame (0.24% of budget)

### 4. Pipeline Barriers (minimize)

**Problem:** Barriers stall the GPU

**Solution:** Batch transitions, use correct stages

```zig
// BAD: Per-image barriers
for (images) |img| {
    vkCmdPipelineBarrier(..., img, ...);  // GPU stall!
}

// GOOD: Single barrier for all images
vkCmdPipelineBarrier(..., all_images, ...);

// BETTER: Use correct pipeline stages
srcStageMask = .VERTEX_SHADER_BIT;  // Don't wait for fragment!
dstStageMask = .FRAGMENT_SHADER_BIT;
```

**GPU Time:** 0.5ms → 0.2ms (60% reduction)

---

## Memory Optimizations

### 1. Pool Allocators

**Problem:** vkAllocateMemory is slow (~100μs per call)

**Solution:** Allocate large blocks, suballocate from them

```zig
// Single 256MB allocation
const pool = try allocator.allocate(256 * 1024 * 1024);

// Suballocate buffers from pool
fn allocBuffer(size: usize) !VkBuffer {
    const offset = pool.allocate(size);  // Fast!
    return createBufferFromPool(pool, offset, size);
}
```

**Savings:** Startup time: 500ms → 50ms

### 2. Atlas Growth Strategy

**Problem:** Reallocating atlas is expensive

**Solution:** Double size when full

```zig
// Start small (512x512), grow exponentially
512x512 → 1024x1024 → 2048x2048 → 4096x4096

// Amortized O(1) growth
// Total reallocations: log2(max_size) = ~4 for 4096x4096
```

**Savings:** Avoids frequent reallocations

### 3. Staging Buffer Recycling

**Problem:** Allocating staging buffers per upload

**Solution:** Reuse staging buffers across frames

```zig
// Pool of staging buffers
const staging_pool = [3]VkBuffer{...};

fn uploadData(data: []u8, frame_idx: usize) !void {
    const staging = staging_pool[frame_idx % 3];  // Reuse!
    @memcpy(staging.mapped_ptr, data);
    vkCmdCopyBuffer(...);
}
```

**Savings:** ~50μs per atlas upload

---

## Frame Pacing (Phase 6)

### 1. VSync Modes

**FIFO (VSync):**
```
Pros: Predictable frame time, no tearing
Cons: Input latency (+1 frame), capped at refresh rate
Use: Default for most users
```

**MAILBOX (Triple Buffer):**
```
Pros: Low latency, no tearing, high throughput
Cons: Higher GPU usage, potential judder
Use: High refresh rate gaming (240Hz+)
```

**IMMEDIATE (No VSync):**
```
Pros: Lowest latency, uncapped FPS
Cons: Screen tearing, inconsistent frame times
Use: Competitive gaming, benchmarking
```

**FIFO_RELAXED (Adaptive):**
```
Pros: VSync when fast, tearing when slow
Cons: Inconsistent behavior
Use: Systems with variable GPU performance
```

### 2. Frame Rate Limiting

```zig
// Cap at target refresh rate
const target_frame_time_ns = 1_000_000_000 / 240;  // 4.16ms for 240Hz

while (true) {
    const frame_start = std.time.nanoTimestamp();

    renderFrame();

    const frame_end = std.time.nanoTimestamp();
    const elapsed = frame_end - frame_start;

    if (elapsed < target_frame_time_ns) {
        std.time.sleep(target_frame_time_ns - elapsed);
    }
}
```

### 3. Frame Time Tracking

```zig
// Circular buffer for frame times
const FrameTimer = struct {
    samples: [120]u64,  // 120 frames @ 240Hz = 0.5s
    index: usize = 0,

    fn record(self: *FrameTimer, frame_time_ns: u64) void {
        self.samples[self.index] = frame_time_ns;
        self.index = (self.index + 1) % 120;
    }

    fn percentile(self: *FrameTimer, p: f32) u64 {
        var sorted = self.samples;
        std.mem.sort(u64, &sorted, {}, std.sort.asc(u64));
        const idx = @as(usize, @intFromFloat(@as(f32, @floatFromInt(sorted.len)) * p));
        return sorted[idx];
    }
};

// Track metrics
const p99 = timer.percentile(0.99);  // 99th percentile frame time
const p50 = timer.percentile(0.50);  // Median
```

---

## Profiling Tools

### 1. GPU Timestamps

```zig
// Query pool for timestamps
const query_pool = try device.createQueryPool(.TIMESTAMP, 10);

// Measure GPU work
vkCmdWriteTimestamp(cmd, .TOP_OF_PIPE_BIT, query_pool, 0);
vkCmdDraw(...);
vkCmdWriteTimestamp(cmd, .BOTTOM_OF_PIPE_BIT, query_pool, 1);

// Read results
var timestamps: [2]u64 = undefined;
vkGetQueryPoolResults(device, query_pool, 0, 2, &timestamps, ...);

const gpu_time_ns = (timestamps[1] - timestamps[0]) * timestamp_period;
```

### 2. CPU Profiling

```zig
const Profiler = struct {
    sections: std.StringHashMap(u64),

    fn begin(name: []const u8) i64 {
        return std.time.nanoTimestamp();
    }

    fn end(self: *Profiler, name: []const u8, start: i64) void {
        const elapsed = std.time.nanoTimestamp() - start;
        const entry = self.sections.getOrPut(name);
        entry.value_ptr.* += elapsed;
    }
};

// Usage
const t0 = profiler.begin("command_recording");
recordCommands();
profiler.end("command_recording", t0);
```

### 3. Validation Layer Stats

```bash
# Enable pipeline statistics
VK_LAYER_SETTINGS_PATH=validation_layer_settings.txt zig build test

# validation_layer_settings.txt:
khronos_validation.enables = VK_VALIDATION_FEATURE_ENABLE_BEST_PRACTICES_EXT
```

---

## NVIDIA-Specific Optimizations (Phase 6)

### 1. Memory Allocation Flags

```zig
// Prefer device-local memory
const alloc_info = VkMemoryAllocateInfo{
    .allocationSize = size,
    .memoryTypeIndex = findMemoryType(
        .DEVICE_LOCAL_BIT,
        .{ }  // No host-visible requirement
    ),
};
```

### 2. Pipeline Cache

```zig
// Save pipeline cache to disk
const cache_data = try device.getPipelineCacheData(cache);
try std.fs.cwd().writeFile("pipeline_cache.bin", cache_data);

// Load on next launch (50-200ms savings)
const cache_file = try std.fs.cwd().readFileAlloc(..., "pipeline_cache.bin");
const cache = try device.createPipelineCache(cache_file);
```

### 3. Async Compute (future)

```zig
// Use compute queue for atlas uploads (parallel with graphics)
const compute_queue = device.getQueue(.COMPUTE_BIT, 0);

vkQueueSubmit(compute_queue, &upload_submit, null);  // Non-blocking!
vkQueueSubmit(graphics_queue, &draw_submit, fence);  // Parallel!
```

---

## Bottleneck Identification

### CPU-Bound Symptoms
- GPU utilization < 90%
- Frame time scales with CPU clock
- Task Manager shows high CPU usage

**Fix:** Reduce CPU work (SIMD, caching, parallel recording)

### GPU-Bound Symptoms
- GPU utilization 95-100%
- Frame time scales with resolution
- Lowering settings improves FPS

**Fix:** Reduce GPU work (fewer draws, smaller atlas, simpler shaders)

### Memory-Bound Symptoms
- Frame time spikes during uploads
- GPU memory usage high
- Stuttering when loading new glyphs

**Fix:** Better atlas management, compression, streaming

---

## Performance Checklist

### Phase 6 Goals
- [ ] SIMD glyph batching (AVX2)
- [ ] Command buffer reuse
- [ ] Descriptor caching
- [ ] Pipeline cache persistence
- [ ] Frame pacing (MAILBOX mode)
- [ ] CPU/GPU profiling tools
- [ ] Parallel command recording (multi-threaded)

### Phase 7 Goals
- [ ] Async compute for uploads
- [ ] Texture compression (BC4)
- [ ] Atlas eviction (LRU)
- [ ] Memory defragmentation
- [ ] Hot shader reload

---

**Last Updated:** 2025-10-31
