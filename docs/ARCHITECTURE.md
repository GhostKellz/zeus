# Zeus Architecture

**System Design Decisions for High-Performance Vulkan Text Rendering**

---

## Design Philosophy

Zeus follows three core principles:

1. **Performance First** - Every design decision optimized for 144-360Hz refresh rates
2. **Pure Zig** - No C dependencies, idiomatic Zig patterns throughout
3. **Modular Composition** - Clear boundaries, testable components

---

## Module Architecture

### Layer 1: Foundation (loader, types, error)

**Purpose:** Platform-independent Vulkan access

**Key Files:**
- `loader.zig` - Dynamic library loading, function pointer dispatch
- `types.zig` - Vulkan type definitions, enums, structs
- `error.zig` - VkResult → Zig error mapping

**Design Decisions:**
- **Dynamic loading only:** No static linking to libvulkan
  - *Rationale:* Platform portability, smaller binaries, runtime flexibility
- **Opaque handle types:** `VkDevice = *opaque {}`
  - *Rationale:* Type safety, prevent misuse, match Vulkan semantics
- **Packed structs for flags:** `VkAccessFlags = packed struct { ... }`
  - *Rationale:* Type-safe bitfields, compile-time validation

**Function Pointer Loading:**
```zig
// Two-stage loading
vkGetInstanceProcAddr → load instance-level functions
vkGetDeviceProcAddr → load device-level functions (faster)

// Lazy caching
if (instance_fn_cache.vkCreateDevice == null) {
    instance_fn_cache.vkCreateDevice = vkGetInstanceProcAddr(...);
}
```

---

### Layer 2: Device Management (instance, device, physical_device, surface)

**Purpose:** Vulkan initialization and GPU selection

**Key Files:**
- `instance.zig` - VkInstance creation, extensions, validation layers
- `device.zig` - VkDevice creation, queue allocation
- `physical_device.zig` - GPU enumeration, feature queries
- `surface.zig` - Platform surface creation (Wayland/X11/Windows)

**Design Decisions:**
- **Debug validation in Debug builds:** Automatic VK_LAYER_KHRONOS_validation
  - *Rationale:* Catch bugs early, zero cost in release builds
- **Queue family caching:** Store graphics/present/transfer queue indices
  - *Rationale:* Avoid repeated queries, faster queue submission
- **Surface from external handle:** Zeus doesn't create windows
  - *Rationale:* Grim/Phantom owns window lifecycle, Zeus just renders

**GPU Selection Strategy:**
```zig
// 1. Prefer discrete GPU (NVIDIA/AMD)
// 2. Check for required features (dynamic rendering, timeline semaphores)
// 3. Verify swapchain support
// 4. Fall back to integrated GPU if no discrete available
```

---

### Layer 3: Resource Management (memory, buffer, image, sampler, descriptor)

**Purpose:** GPU memory and resource lifecycle

**Key Files:**
- `memory.zig` - Memory allocation, type selection
- `buffer.zig` - Vertex/index/uniform buffer management
- `image.zig` - Texture/render target management
- `sampler.zig` - Texture sampling configuration
- `descriptor.zig` - Descriptor set layout/pool/allocation

**Design Decisions:**
- **Pool allocators for small allocations:** Reduce vkAllocateMemory calls
  - *Rationale:* Vulkan spec recommends <4096 allocations total
- **Staging buffer strategy:** Separate pool for host→device transfers
  - *Rationale:* Optimal for atlas uploads, reusable across frames
- **Descriptor caching:** Cache descriptor set layouts by hash
  - *Rationale:* Avoid redundant vkCreateDescriptorSetLayout calls

**Memory Types:**
```
Device-Local (GPU-only):    Image atlas, vertex buffers (static)
Host-Visible (CPU→GPU):     Staging buffers, uniform buffers
Host-Cached (GPU→CPU):      Readback buffers (unused in Zeus)
```

**Buffer Suballocation:**
```zig
// Single large allocation, multiple buffers
Memory Block (256MB device-local)
├── Vertex Buffer (16KB)
├── Index Buffer (8KB)
├── Instance Buffer (4MB)
└── Free space (remaining)
```

---

### Layer 4: Pipeline Construction (shader, render_pass, pipeline)

**Purpose:** Graphics pipeline creation

**Key Files:**
- `shader.zig` - SPIR-V module loading
- `render_pass.zig` - Render pass builder
- `pipeline.zig` - Graphics pipeline builder

**Design Decisions:**
- **Embedded SPIR-V:** `@embedFile("shaders/text.vert.spv")`
  - *Rationale:* No runtime file loading, always available
- **Builder pattern:** Fluent API for pipeline construction
  - *Rationale:* Reduce boilerplate, catch errors at compile time
- **Pipeline cache:** Store compiled pipelines to disk
  - *Rationale:* Faster subsequent launches (50-200ms savings)

**Render Pass Design:**
```
Single Subpass:
  Attachment 0: Swapchain image (color, load=CLEAR, store=STORE)
  No depth/stencil (2D text doesn't need it)
  Dependencies: External → subpass (wait for acquire)
                subpass → External (signal for present)
```

**Graphics Pipeline:**
```
Vertex Shader:   Instanced quad expansion
Fragment Shader: Atlas texture sampling + alpha blend
Vertex Input:    2 bindings (per-vertex + per-instance)
Rasterization:   Fill, no culling
Blend:           Alpha blending (srcAlpha, oneMinusSrcAlpha)
Dynamic State:   Viewport, scissor
```

---

### Layer 5: Command & Sync (commands, sync, swapchain)

**Purpose:** GPU work submission and synchronization

**Key Files:**
- `commands.zig` - Command buffer helpers
- `sync.zig` - Fences, semaphores, barriers
- `swapchain.zig` - Presentation management

**Design Decisions:**
- **Per-frame command pools:** One pool per frame in flight
  - *Rationale:* Avoid vkResetCommandPool contention
- **Triple buffering default:** 3 frames in flight
  - *Rationale:* Balance latency (lower is better) vs throughput
- **Timeline semaphores:** Use VK_KHR_timeline_semaphore when available
  - *Rationale:* Simplify synchronization, reduce fence overhead

**Frame Synchronization:**
```
Frame N:
  1. Wait for fence N-3 (previous use of this frame slot)
  2. Acquire swapchain image (signal imageAvailable semaphore)
  3. Record commands
  4. Submit (wait=imageAvailable, signal=renderFinished)
  5. Present (wait=renderFinished)
  6. Fence N signals when GPU done
```

**Present Modes:**
```
FIFO (VSync):           Capped at refresh rate, low latency
MAILBOX (triple buffer): Uncapped, replaces queued frames
IMMEDIATE (no VSync):    Lowest latency, may tear
FIFO_RELAXED (adaptive): VSync when >refresh rate, tearing when <
```

---

### Layer 6: Text Rendering (glyph_atlas, text_renderer)

**Purpose:** High-level text rendering API

**Key Files:**
- `glyph_atlas.zig` - Dynamic texture atlas, rectangle packing
- `text_renderer.zig` - Text rendering pipeline, frame API

**Design Decisions:**
- **R8_UNORM atlas format:** Single-channel grayscale
  - *Rationale:* Minimal memory (1 byte/pixel), sufficient for text
- **Rectangle packing:** Guillotine algorithm (fast, simple)
  - *Rationale:* Good packing ratio, O(n) insertion, no fragmentation
- **Atlas growth:** Double width/height when full
  - *Rationale:* Amortized O(1) growth, predictable memory usage
- **Instanced rendering:** One draw call for thousands of glyphs
  - *Rationale:* Minimize CPU overhead, maximize GPU parallelism

**Frame API Design:**
```zig
// Explicit frame lifecycle
beginFrame()      → Reset per-frame state
setProjection()   → Update uniform buffer
queueQuad()       → CPU-side batching (no GPU calls yet)
encode()          → Record commands (vkCmd*)
endFrame()        → Cleanup, prepare for next frame

// Why this design?
// - Batching: Accumulate quads on CPU before GPU submission
// - Cache-friendly: Sequential quad appends, no random access
// - Error handling: Failures caught before GPU work
```

**Glyph Atlas Layout:**
```
1024x1024 R8_UNORM Image
┌────────────────────────────┐
│ Glyph A (32x32)            │
│ Glyph B (16x16)  Glyph C   │
│ ...                        │
│                            │
│                            │
│         Free space         │
│                            │
└────────────────────────────┘

Per-glyph data:
- UV rect: (x, y, width, height) in [0, 1] space
- Position: (x, y) in screen space
- Size: (w, h) in pixels
- Color: (r, g, b, a)
```

---

## Performance Optimizations

### CPU Optimizations

**1. Minimize Allocations**
```zig
// Pre-allocate per-frame storage
frame_states: []FrameState,
instance_data: []Instance,  // Reused every frame

// Avoid per-glyph allocations
fn queueQuad(self: *TextRenderer, quad: TextQuad) !void {
    // Direct write to pre-allocated buffer
    self.instance_data[self.frame_states[frame_idx].instance_count] = quad;
    self.frame_states[frame_idx].instance_count += 1;
}
```

**2. Cache Descriptor Updates**
```zig
// Only update when changed
if (needs_upload) {
    vkUpdateDescriptorSets(...);
    needs_upload = false;
}
```

**3. Command Buffer Reuse**
```zig
// Record once, submit many times (when possible)
if (!scene_changed) {
    vkQueueSubmit(cached_command_buffer);
} else {
    recordCommands();
}
```

### GPU Optimizations

**1. Instanced Rendering**
```
Instead of:  1000 draw calls × 6 vertices = overhead!
Use:         1 draw call × 6 vertices × 1000 instances = fast!
```

**2. Pipeline Barriers (minimal)**
```zig
// Only transition when necessary
if (old_layout != new_layout) {
    vkCmdPipelineBarrier(...);
}
```

**3. Push Constants for Per-Draw Data**
```zig
// Faster than uniform buffer updates
vkCmdPushConstants(cmd, layout, offset, size, &data);
```

### Memory Optimizations

**1. Texture Compression (future)**
```
Current: R8_UNORM (1 byte/pixel)
Future:  BC4 (0.5 bytes/pixel) or ETC2 (mobile)
```

**2. Atlas Eviction (LRU)**
```zig
// When atlas full, evict least recently used glyphs
// Track access time per glyph
// Prioritize frequently used glyphs (ASCII, common Unicode)
```

---

## Testing Strategy

### Unit Tests
Each module has embedded `test` blocks:
```zig
test "buffer creation" {
    const device = try createMockDevice();
    const buffer = try Buffer.init(device, 1024, .VERTEX_BUFFER_BIT);
    defer buffer.deinit();

    try std.testing.expect(buffer.size == 1024);
}
```

### Integration Tests
Phase 5 includes end-to-end frame API test:
```zig
test "text renderer frame lifecycle" {
    var renderer = try TextRenderer.init(...);
    defer renderer.deinit();

    try renderer.beginFrame(0);
    try renderer.setProjection(0, &projection);
    try renderer.queueQuad(.{ ... });
    try renderer.encode(cmd, 0);
    renderer.endFrame();
}
```

### Validation Layers
Debug builds automatically enable:
```
VK_LAYER_KHRONOS_validation
  - Core validation
  - Thread safety
  - Parameter validation
  - Object lifetime tracking
```

---

## Error Handling

### Vulkan Errors → Zig Errors
```zig
pub const Error = error{
    OutOfHostMemory,
    OutOfDeviceMemory,
    DeviceLost,
    SurfaceLost,
    // ... all VkResult errors
};

fn checkResult(result: VkResult) Error!void {
    return switch (result) {
        .SUCCESS => {},
        .ERROR_OUT_OF_HOST_MEMORY => error.OutOfHostMemory,
        // ...
    };
}
```

### Error Context
```zig
// Provide context for debugging
return error.OutOfDeviceMemory; // Which allocation failed?

// Better:
std.log.err("Failed to allocate atlas image ({}x{}, {} bytes)",
    .{width, height, size});
return error.OutOfDeviceMemory;
```

---

## Future Improvements

### Phase 6: Performance
- Parallel command buffer recording (multi-threaded)
- SIMD glyph batching (AVX2/AVX-512)
- Async compute for atlas uploads

### Phase 7: Robustness
- Device lost recovery (driver crashes)
- Out-of-memory fallbacks (reduce atlas size)
- Swapchain suboptimal handling (resolution changes)

### Phase 8: Grim Integration
- FreeType rasterization
- Subpixel antialiasing (RGB LCD)
- Font fallback chains

### Post-MVP
- SDF fonts (scalable text)
- HDR color spaces
- Multi-monitor support
- Android backend

---

## References

- **Vulkan 1.3 Spec:** https://www.khronos.org/registry/vulkan/specs/1.3/html/
- **Vulkan Best Practices:** https://github.com/KhronosGroup/Vulkan-Samples
- **NVIDIA Vulkan Guide:** https://developer.nvidia.com/vulkan-driver
- **Zig Documentation:** https://ziglang.org/documentation/master/

---

**Last Updated:** 2025-10-31
