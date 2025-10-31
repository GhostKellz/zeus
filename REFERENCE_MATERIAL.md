# Zeus Reference Material

Comprehensive analysis of archived reference repositories and resources to leverage for Zeus development.

---

## Overview

This document outlines insights from archived reference repositories that can inform Zeus's development, particularly for:

- **NVIDIA/AMD GPU optimization** - Memory management, display integration, multi-GPU support
- **Vulkan API patterns** - Dispatch tables, error handling, type safety
- **Linux kernel optimizations** - CPU schedulers, memory management, high-refresh-rate support
- **Performance targeting** - 144-360Hz @ 1440p, 144-270Hz @ 4K on NVIDIA RTX 4090

---

## 1. NVIDIA Open GPU Kernel Modules (v580)

**Location:** `archive/open-gpu-kernel-modules/`

### Key Insights for Zeus

#### Memory Management (UVM - Unified Virtual Memory)

**File:** `kernel-open/nvidia-uvm/`

The NVIDIA driver's UVM layer provides sophisticated memory allocation strategies that Zeus can leverage through Vulkan's memory types:

```c
// From nvidia-uvm allocation logic (reference)
// Prioritizes device-local + host-visible memory when available
// Falls back to separate staging buffers for large transfers

// Zeus equivalent (already implemented in memory.zig)
const memory_props = physical_device.getMemoryProperties();
const type_index = findMemoryType(
    memory_props,
    requirements.memoryTypeBits,
    .{ .DEVICE_LOCAL = true, .HOST_VISIBLE = true },
);
```

**Actionable for Zeus:**
-  Already using optimal memory types in `lib/vulkan/memory.zig:72-90`
- = Phase 6: Add ReBAR (Resizable BAR) detection for large host-visible allocations
- = Phase 7: Add memory budget tracking (VK_EXT_memory_budget)

#### Display Integration (DRM/KMS)

**File:** `kernel-open/nvidia-drm/`

NVIDIA's DRM modesetting driver handles high-refresh-rate display configuration. Relevant for Wayland integration:

```c
// From nvidia-drm modeset logic
// Supports 144-360Hz through DRM atomic commits
// Uses VRR (Variable Refresh Rate) when available
```

**Actionable for Zeus:**
-  Already supports Wayland through `lib/vulkan/surface.zig:55-78` (VK_KHR_wayland_surface)
- = Phase 6: Add VK_EXT_present_mode_fifo_latest_ready for adaptive sync
- = Phase 7: Add display timing queries for frame pacing validation

#### Multi-GPU Support

**File:** `kernel-open/nvidia/`

NVIDIA's peer memory access allows direct GPU-to-GPU transfers without CPU involvement:

```c
// From NVIDIA peer memory API
// Enables zero-copy sharing between GPUs
// Requires PCIe peer-to-peer support
```

**Actionable for Zeus:**
- =€ Post-MVP: Multi-monitor support with separate GPUs
- =€ Post-MVP: VK_KHR_device_group for dual-GPU rendering

---

## 2. Vulkan-Zig Bindings (Zig 0.13-0.15)

**Location:** `archive/vulkan-zig/`

### Comparison: vulkan-zig vs Zeus Approach

| Aspect | vulkan-zig | Zeus | Rationale |
|--------|------------|------|-----------|
| **Binding generation** | XML codegen | Manual bindings | Zeus targets text rendering only, smaller API surface |
| **Function loading** | Upfront (all at init) | Lazy (on-demand) | Zeus loads only needed functions, smaller binary |
| **Type safety** | Wrapper structs | Opaque handles | Zeus uses raw Vulkan types for interop |
| **Flags** | Packed structs | Raw u32 + builder | Zeus prioritizes API ergonomics |
| **Error handling** | Result types | Zig errors | Zeus uses idiomatic Zig error unions |

### Key Patterns from vulkan-zig

#### 1. Three-Tier Dispatch Tables

**File:** `archive/vulkan-zig/generator/vulkan/wrapper.zig`

```zig
// vulkan-zig pattern (reference)
pub const BaseDispatch = struct {
    vkGetInstanceProcAddr: PFN_vkGetInstanceProcAddr,
    vkEnumerateInstanceVersion: PFN_vkEnumerateInstanceVersion,
    // ... base-level functions
};

pub const InstanceDispatch = struct {
    vkCreateDevice: PFN_vkCreateDevice,
    vkEnumeratePhysicalDevices: PFN_vkEnumeratePhysicalDevices,
    // ... instance-level functions
};

pub const DeviceDispatch = struct {
    vkCreateBuffer: PFN_vkCreateBuffer,
    vkQueueSubmit: PFN_vkQueueSubmit,
    // ... device-level functions
};

// Zeus equivalent (lib/vulkan/loader.zig)
pub const Loader = struct {
    base: BaseFunctions,
    instance: ?InstanceFunctions,
    device: ?DeviceFunctions,

    pub fn init() !Loader { /* ... */ }
    pub fn loadInstance(instance: VkInstance) !void { /* ... */ }
    pub fn loadDevice(device: VkDevice) !void { /* ... */ }
};
```

**Status:**  Zeus already uses this pattern in `loader.zig:45-120`

#### 2. SPIR-V Shader Embedding

**File:** `archive/vulkan-zig/examples/`

```zig
// vulkan-zig pattern
const shader_bytes = @embedFile("shader.spv");
const aligned_bytes align(@alignOf(u32)) = shader_bytes.*;  //   CRITICAL

const create_info = VkShaderModuleCreateInfo{
    .pCode = @ptrCast(&aligned_bytes),
    .codeSize = aligned_bytes.len,
};
```

**Issue:** SPIR-V requires 4-byte alignment, `@embedFile` doesn't guarantee this.

**Zeus Status:**
-   Check `lib/vulkan/shader.zig:35-50` for alignment
- = Phase 6: Add compile-time assertion for SPIR-V alignment

#### 3. Error Mapping

**File:** `archive/vulkan-zig/generator/vulkan/wrapper.zig`

```zig
// vulkan-zig approach (codegen)
pub fn vkResultToZigError(result: VkResult) error{...}!void {
    return switch (result) {
        .SUCCESS => {},
        .ERROR_OUT_OF_HOST_MEMORY => error.OutOfHostMemory,
        .ERROR_OUT_OF_DEVICE_MEMORY => error.OutOfDeviceMemory,
        // ... 100+ error codes
    };
}

// Zeus approach (manual, focused)
pub fn checkResult(result: VkResult) Error!void {
    return switch (result) {
        .VK_SUCCESS => {},
        .VK_ERROR_OUT_OF_HOST_MEMORY => error.OutOfHostMemory,
        .VK_ERROR_OUT_OF_DEVICE_MEMORY => error.OutOfDeviceMemory,
        .VK_ERROR_DEVICE_LOST => error.DeviceLost,
        // Only errors Zeus actually handles
        else => error.VulkanError,
    };
}
```

**Status:**  Zeus uses minimal error set in `lib/vulkan/error.zig:10-35`

---

## 3. Linux Kernel Optimizations (TKG, BORE, CachyOS)

**Locations:**
- `archive/linux-tkg/`
- `archive/bore-scheduler/`
- `archive/linux-cachyos/`

### BORE Scheduler for Text Rendering

**Why BORE is Ideal for Zeus/Grim:**

Text rendering is a **bursty, I/O-oriented workload**:
1. **Wait for input** (keyboard/mouse) ’ CPU sleeps (low burst score)
2. **Process input** ’ Brief CPU burst (render glyphs)
3. **Wait for VSync** ’ GPU work, CPU sleeps again

BORE prioritizes tasks with **low burst scores** (frequent sleep/yield), which perfectly describes a text editor:

```c
// From archive/bore-scheduler/README.md

Burstiness = CPU time consumed since last sleep/yield/IO-wait
Burst Score = bitcount(normalized_burst_time) - offset

Low Score  = Task sleeps often (I/O-bound, interactive) ’ HIGH PRIORITY
High Score = Task runs long (CPU-bound, batch)        ’ LOW PRIORITY

// Text editor pattern:
Input event ’ 50¼s CPU burst ’ VSync wait ’ Low burst score ’ High priority
```

**Tunables for Grim/Zeus (already set on user's system via linux-tkg-bore):**

```bash
# /etc/sysctl.d/99-bore.conf (reference)
kernel.sched_bore = 1                        # Enable BORE
kernel.sched_burst_penalty_offset = 24       # Effective burst range
kernel.sched_burst_penalty_scale = 1280      # Discrimination strength
kernel.sched_burst_smoothness = 20           # Avoid "burst spikes"
```

**Actionable for Zeus:**
-  User already running linux-tkg-bore 6.17.4 kernel
- =Ý Document in PERFORMANCE.md: "Zeus designed for BORE/EEVDF schedulers"
- = Phase 6: Add busy-wait avoidance (prefer vkWaitForFences over spin loops)

### x86-64-v3/v4 Optimizations (CachyOS)

**File:** `archive/linux-cachyos/README.md`

AMD Ryzen 9 7950X3D supports **x86-64-v4** instruction set (AVX2, AVX-512):

```bash
# User's CPU capabilities (reference)
$ /lib/ld-linux-x86-64.so.2 --help | grep supported
  x86-64-v4 (supported, searched)  #  Full AVX2/AVX-512 support
  x86-64-v3 (supported, searched)
  x86-64-v2 (supported, searched)
```

**Instruction sets:**
- **x86-64-v3:** AVX, AVX2, SSE4.2, SSSE3 (2012+ CPUs)
- **x86-64-v4:** AVX-512F, AVX-512BW, AVX-512CD, AVX-512DQ, AVX-512VL (2017+ CPUs)

**Actionable for Zeus:**

= **Phase 6: SIMD Glyph Batching**

```zig
// Current scalar code (lib/vulkan/text_renderer.zig:220-240)
for (glyphs) |glyph, i| {
    instance_data[i] = .{
        .position = glyph.position,
        .size = glyph.size,
        .atlas_rect = glyph.uv,
        .color = glyph.color,
    };
}

// Phase 6: AVX2 vectorized (8 glyphs/iteration)
const Vec8f32 = @Vector(8, f32);
var i: usize = 0;
while (i + 8 <= glyphs.len) : (i += 8) {
    const positions_x: Vec8f32 = loadVec8(&glyphs[i].position.x);
    const positions_y: Vec8f32 = loadVec8(&glyphs[i].position.y);
    const transformed_x = positions_x * scale + offset_x;
    const transformed_y = positions_y * scale + offset_y;
    storeVec8(&instance_data[i].position.x, transformed_x);
    storeVec8(&instance_data[i].position.y, transformed_y);
}
// Handle remaining glyphs (i to glyphs.len) with scalar code
```

**Expected Performance Gain:**
- **Scalar:** ~500¼s to process 10,000 glyphs (1 glyph/cycle)
- **AVX2:** ~65¼s to process 10,000 glyphs (8 glyphs/cycle)
- **Savings:** ~435¼s per frame (10.4% of 4.16ms budget @ 240Hz)

### Memory Management Tweaks

**File:** `archive/linux-tkg/customization.cfg`

```bash
# Relevant kernel parameters for Vulkan
vm.max_map_count = 16777216       # Allow many descriptor sets
vm.swappiness = 10                # Prefer RAM over swap for GPU buffers
vm.vfs_cache_pressure = 50        # Balance file cache vs GPU memory
```

**Actionable for Zeus:**
-  Already handled by linux-tkg-bore kernel defaults
- =Ý Document in INTEGRATION.md: Recommended kernel parameters for Grim deployment

---

## 4. AMD GPU Support Considerations

While Zeus is currently optimized for NVIDIA (user's RTX 4090), AMD support is achievable with minimal changes:

### Memory Type Differences

| Aspect | NVIDIA (Proprietary) | AMD (RADV Mesa) |
|--------|---------------------|-----------------|
| **Preferred type** | DEVICE_LOCAL + HOST_VISIBLE (ReBAR) | Separate staging buffers |
| **Large allocations** | Single host-visible heap | DEVICE_LOCAL only, explicit staging |
| **Small allocations** | HOST_VISIBLE for < 256KB | Same as NVIDIA |

**Zeus Status:**
-  `lib/vulkan/memory.zig:72-90` already tries DEVICE_LOCAL + HOST_VISIBLE, falls back gracefully
- = Phase 7: Add AMD-specific staging buffer optimization path

### AMD-Specific Extensions

**Optional optimizations for RADV:**

```zig
// VK_AMD_shader_ballot (Zig equivalent)
// Allows wave-level operations in shaders (similar to NVIDIA's warp intrinsics)
// Useful for future SDF font rendering (Post-MVP)

// VK_EXT_descriptor_indexing (already widely supported)
// Both NVIDIA and AMD, Zeus can use in Phase 7 for bindless textures
```

**Actionable:**
- =€ Post-MVP: Test on AMD RX 7900 XTX for validation
- =€ Post-MVP: Add AMD-specific code paths if performance differs significantly

---

## 5. Future Research Areas

### Vulkan 1.4 Features (Released 2025)

**Potential benefits for Zeus:**

```c
// VK_KHR_maintenance7 (Vulkan 1.4 core)
// - Reduced CPU overhead for descriptor updates
// - Better pipeline cache hit rates

// VK_KHR_dynamic_rendering_local_read (Vulkan 1.4 core)
// - Tile-based GPUs (mobile) can read framebuffer without round-trip
```

**Actionable:**
- =€ Post-MVP: Evaluate Vulkan 1.4 adoption (requires driver updates)

### GPU-Accelerated Glyph Rasterization

**Current:** CPU rasterizes glyphs ’ upload to atlas
**Future:** Compute shader rasterizes glyphs on GPU

**References:**
- Slug library (GPU vector graphics)
- Pathfinder (GPU font rendering)

**Actionable:**
- =€ Post-MVP: Research compute shader rasterization for dynamic font sizes

### HDR Support

**Current:** SDR (8-bit SRGB)
**Future:** HDR10 (10-bit, wide color gamut)

**Requirements:**
- VK_EXT_swapchain_colorspace
- VK_FORMAT_A2B10G10R10_UNORM_PACK32 swapchain
- HDR-capable display (user has capable hardware)

**Actionable:**
- =€ Post-MVP: Add HDR rendering mode for compatible displays

---

## 6. Documentation Improvements

### Performance Profiling (Phase 7)

Add to `docs/PERFORMANCE.md`:

```markdown
## Profiling Tools

### RenderDoc (Vulkan Frame Capture)
```bash
# Capture Zeus rendering
renderdoc --attach grim

# Analyze:
# - Draw call count (target: 1-2 per frame)
# - GPU timing (vertex vs fragment)
# - Pipeline stalls
```

### NVIDIA Nsight Graphics
```bash
# Deep NVIDIA profiling
nsight-gfx ./grim

# Focus areas:
# - Texture cache hit rate (atlas access)
# - Memory bandwidth (instance buffer uploads)
# - Warp occupancy (fragment shader)
```

### perf (CPU Profiling)
```bash
# CPU hotspots in Zeus
perf record -F 999 -g -- ./grim
perf report --no-children --sort=dso,symbol

# Expected hotspots:
# - text_renderer.queueQuad() - batching logic
# - glyph_atlas.upload() - texture updates
```
```

### Integration Testing (Phase 8)

Add to `docs/INTEGRATION.md`:

```markdown
## Validation Tests

### Frame Timing Validation
```zig
// Ensure we hit target frame times
const target_fps = 240;
const tolerance_ms = 0.5;

var frame_times: [100]f64 = undefined;
for (0..100) |i| {
    const start = std.time.nanoTimestamp();
    try renderFrame();
    const end = std.time.nanoTimestamp();
    frame_times[i] = @as(f64, @floatFromInt(end - start)) / 1e6;
}

const avg = std.mem.sum(f64, &frame_times) / 100.0;
const expected = 1000.0 / @as(f64, target_fps);
assert(std.math.fabs(avg - expected) < tolerance_ms);
```

### Stress Testing
```zig
// 10,000 glyphs (typical large file in Grim)
var glyphs: [10000]GlyphQuad = undefined;
try renderer.beginFrame(0);
for (glyphs) |glyph| try renderer.queueQuad(glyph);
try renderer.encode(cmd_buffer, 0);

// Verify no OOM, no stalls
assert(renderer.instance_count == 10000);
```
```

---

## 7. Upstream Contributions

### Potential Contributions to Zig Ecosystem

Once Zeus is stable (Phase 7+), consider upstreaming:

1. **Vulkan dispatch table pattern** ’ Zig standard library example
2. **Dynamic library loading** ’ Improve `std.DynLib` documentation
3. **SIMD glyph batching** ’ Blog post on Zig SIMD patterns

### Community Engagement

- **Zig gamedev community** (discord.gg/zig-gamedev)
- **Vulkan community** (discord.gg/vulkan)
- **Wayland developers** (wayland-devel mailing list)

---

## 8. Archive Maintenance

### Keep Updated

Periodically sync archived repos to stay current:

```bash
# NVIDIA Open GPU Kernel Modules
cd archive/open-gpu-kernel-modules
git fetch origin
git log main..origin/main --oneline  # Check for new features

# Linux TKG
cd archive/linux-tkg
git fetch origin
git log main..origin/main --oneline  # Check for new scheduler patches

# Vulkan-Zig (if development resumes)
cd archive/vulkan-zig
git fetch origin
git log main..origin/main --oneline
```

### Prune Unnecessary Files

Keep archives lean:

```bash
# Remove build artifacts
find archive/ -name "*.o" -delete
find archive/ -name "*.a" -delete

# Keep only source code and documentation
du -sh archive/*  # Monitor size
```

---

## Summary

### Immediate Actionable Items (Phase 6)

1.  **BORE scheduler benefits** - Already leveraging via linux-tkg-bore kernel
2. = **AVX2 SIMD batching** - 8x speedup for glyph processing (~435¼s savings/frame)
3. = **SPIR-V alignment check** - Ensure shader bytecode is 4-byte aligned
4. = **ReBAR detection** - Optimize memory allocation on NVIDIA RTX 4090

### Long-Term Opportunities (Phase 7-8, Post-MVP)

1. =€ **AMD GPU support** - Test on RADV, add staging buffer optimization
2. =€ **Multi-monitor** - Dual-GPU rendering with device groups
3. =€ **HDR rendering** - 10-bit color for wide gamut displays
4. =€ **GPU rasterization** - Compute shader glyph rendering
5. =€ **Vulkan 1.4** - Leverage maintenance7, dynamic_rendering_local_read

### Reference Repositories Status

| Repository | Status | Key Insights |
|------------|--------|--------------|
| NVIDIA Open Modules |  Analyzed | UVM memory strategy, DRM modesetting, peer memory |
| vulkan-zig |  Analyzed | Dispatch tables, error mapping, SPIR-V alignment |
| linux-tkg |  Analyzed | BORE scheduler, memory tweaks, I/O optimizations |
| BORE scheduler |  Analyzed | Burstiness tracking, tunables, interactive workload benefits |
| CachyOS kernel |  Analyzed | x86-64-v4 optimizations (AVX2/AVX-512), NVIDIA compat |

---

**Built with Zig**
