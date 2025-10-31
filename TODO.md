# Vulkan Library for Zig 0.16.0-dev - Implementation Plan

## Overview
Build a full-fledged Vulkan rendering library specifically for Grim editor, optimized for text rendering with GPU acceleration. This will replace the current stub implementation in `ui-tui/vulkan_renderer.zig`.

## Project Goals
1. **Zero external dependencies** - Pure Zig implementation
2. **Text rendering optimized** - Glyph atlas, instanced quads, subpixel rendering
3. **Modern Vulkan 1.3** - Use latest features and best practices
4. **Memory efficient** - Pool allocators, staging buffers, descriptor caching
5. **Error handling** - Full integration with Zig's error system
6. **Cross-platform** - Linux (Wayland/X11), Windows, macOS (MoltenVK)

---

## Phase 1: Core Vulkan Bindings (Foundation)

### 1.1 Vulkan Loader & Dynamic Loading
**File:** `lib/vulkan/loader.zig`

- [ ] Dynamic library loading (`libvulkan.so`, `vulkan-1.dll`, `libvulkan.dylib`)
- [ ] vkGetInstanceProcAddr and vkGetDeviceProcAddr
- [ ] Function pointer tables (instance-level, device-level)
- [ ] Lazy loading with caching
- [ ] Platform-specific library paths

**Priority:** HIGH - Everything depends on this

### 1.2 Type Definitions
**File:** `lib/vulkan/types.zig`

Core types:
- [ ] Handles (VkInstance, VkDevice, VkQueue, VkCommandBuffer, etc.)
- [ ] Enums (VkFormat, VkPresentModeKHR, VkResult, etc.)
- [ ] Flags (VkBufferUsageFlags, VkImageUsageFlags, etc.)
- [ ] Structs (VkApplicationInfo, VkDeviceCreateInfo, etc.)
- [ ] Bitfield helpers using packed structs
- [ ] String conversion utilities

**Priority:** HIGH

### 1.3 Instance & Device Management
**File:** `lib/vulkan/instance.zig`, `lib/vulkan/device.zig`

- [ ] Instance creation with validation layers (debug builds)
- [ ] Physical device enumeration and selection
- [ ] Queue family discovery (graphics, present, transfer)
- [ ] Logical device creation
- [ ] Extension enumeration and enabling
- [ ] Feature checking (VkPhysicalDeviceFeatures)

**Priority:** HIGH

### 1.4 Error Handling
**File:** `lib/vulkan/error.zig`

- [ ] VkResult → Zig error mapping
- [ ] Debug messenger (VK_EXT_debug_utils)
- [ ] Validation layer integration
- [ ] Error context tracking
- [ ] Human-readable error messages

**Priority:** MEDIUM

---

## Phase 2: Swapchain & Presentation

### 2.1 Surface Creation
**File:** `lib/vulkan/surface.zig`

Platform-specific surface creation:
- [ ] Wayland: VK_KHR_wayland_surface
- [ ] X11: VK_KHR_xlib_surface
- [ ] Windows: VK_KHR_win32_surface
- [ ] macOS: VK_EXT_metal_surface (MoltenVK)
- [ ] Surface format selection
- [ ] Present mode selection (fifo, mailbox, immediate)

**Priority:** HIGH

### 2.2 Swapchain Management
**File:** `lib/vulkan/swapchain.zig`

- [ ] Swapchain creation (VK_KHR_swapchain)
- [ ] Image acquisition (vkAcquireNextImageKHR)
- [ ] Present queue submission (vkQueuePresentKHR)
- [ ] Swapchain recreation on resize
- [ ] Double/triple buffering
- [ ] VSync control

**Priority:** HIGH

---

## Phase 3: Resource Management

### 3.1 Memory Allocator
**File:** `lib/vulkan/memory.zig`

- [ ] Memory type selection (device-local, host-visible, etc.)
- [ ] VkMemoryAllocateInfo helpers
- [ ] Memory pool allocator for small allocations
- [ ] Staging buffer management
- [ ] Memory mapping utilities
- [ ] Alignment helpers

**Priority:** HIGH - Critical for performance

### 3.2 Buffer Management
**File:** `lib/vulkan/buffer.zig`

- [ ] Buffer creation (vertex, index, uniform, staging)
- [ ] Buffer memory binding
- [ ] Transfer queue operations
- [ ] Buffer copying and updates
- [ ] Dynamic uniform buffers
- [ ] Push constants

**Priority:** HIGH

### 3.3 Image & Sampler Management
**File:** `lib/vulkan/image.zig`, `lib/vulkan/sampler.zig`

- [ ] Image creation (2D textures, render targets)
- [ ] Image view creation
- [ ] Image layout transitions
- [ ] Sampler creation (linear, nearest, anisotropic)
- [ ] Mipmap generation
- [ ] Format support queries

**Priority:** MEDIUM

### 3.4 Descriptor Management
**File:** `lib/vulkan/descriptor.zig`

- [ ] Descriptor pool creation
- [ ] Descriptor set layout creation
- [ ] Descriptor set allocation
- [ ] Descriptor writes (buffers, images)
- [ ] Descriptor caching (avoid redundant allocations)
- [ ] Bindless descriptors (if available)

**Priority:** MEDIUM

---

## Phase 4: Rendering Pipeline

### 4.1 Shader Module Management
**File:** `lib/vulkan/shader.zig`

- [ ] SPIR-V loading from embedded bytecode
- [ ] Shader module creation
- [ ] Shader stage info builders
- [ ] Reflection helpers (optional)
- [ ] Embedded shaders for text rendering

**Priority:** HIGH

### 4.2 Render Pass
**File:** `lib/vulkan/render_pass.zig`

- [ ] Render pass creation
- [ ] Attachment descriptions
- [ ] Subpass dependencies
- [ ] Framebuffer creation
- [ ] Clear values management

**Priority:** MEDIUM

### 4.3 Graphics Pipeline
**File:** `lib/vulkan/pipeline.zig`

- [ ] Pipeline layout creation
- [ ] Graphics pipeline creation
- [ ] Vertex input state
- [ ] Input assembly state
- [ ] Rasterization state
- [ ] Multisample state
- [ ] Blend state
- [ ] Dynamic state (viewport, scissor)
- [ ] Pipeline cache

**Priority:** HIGH

---

## Phase 5: Command Buffer Management

### 5.1 Command Pool & Buffers
**File:** `lib/vulkan/command.zig`

- [ ] Command pool creation (per-thread pools)
- [ ] Command buffer allocation
- [ ] Command buffer recording
- [ ] Command buffer submission
- [ ] One-time submit helpers
- [ ] Command buffer reset

**Priority:** HIGH

### 5.2 Synchronization
**File:** `lib/vulkan/sync.zig`

- [ ] Fence creation and waiting
- [ ] Semaphore creation and signaling
- [ ] Pipeline barriers
- [ ] Memory barriers
- [ ] Event management
- [ ] Timeline semaphores (VK_KHR_timeline_semaphore)

**Priority:** MEDIUM

---

## Phase 6: Text Rendering Specialization

### 6.1 Glyph Atlas Manager
**File:** `lib/vulkan/glyph_atlas.zig`

- [ ] Dynamic atlas texture (growable)
- [ ] Glyph packing algorithm (rect packer)
- [ ] Glyph rasterization (FreeType integration)
- [ ] Subpixel rendering (RGB LCD filtering)
- [ ] Atlas texture upload to GPU
- [ ] Glyph cache eviction (LRU)
- [ ] Multi-atlas support (fallback fonts)

**Priority:** HIGH - Core feature for editor

### 6.2 Text Rendering Pipeline
**File:** `lib/vulkan/text_renderer.zig`

- [ ] Instanced quad rendering
- [ ] Per-glyph vertex generation
- [ ] Uniform buffer for view/projection
- [ ] Push constants for color/style
- [ ] Alpha blending for antialiasing
- [ ] Subpixel positioning
- [ ] Cursor rendering
- [ ] Selection highlighting

**Priority:** HIGH

### 6.3 Text Shaders
**File:** `shaders/text.vert`, `shaders/text.frag`

Vertex shader:
- [ ] Quad vertex generation from instance data
- [ ] UV coordinate calculation
- [ ] Screen-space transformation

Fragment shader:
- [ ] Atlas texture sampling
- [ ] Alpha blending
- [ ] Subpixel RGB filtering
- [ ] Gamma correction

**Priority:** HIGH

---

## Phase 7: Advanced Features

### 7.1 Frame Pacing
**File:** `lib/vulkan/frame_pacing.zig`

- [ ] Frame time tracking
- [ ] Adaptive VSync
- [ ] Frame rate limiting
- [ ] Triple buffering management
- [ ] Present timing (VK_GOOGLE_display_timing)

**Priority:** LOW

### 7.2 Performance Monitoring
**File:** `lib/vulkan/profiling.zig`

- [ ] GPU timestamp queries
- [ ] Pipeline statistics
- [ ] Memory usage tracking
- [ ] Draw call counting
- [ ] Performance markers

**Priority:** LOW

### 7.3 Multi-threading
**File:** `lib/vulkan/threading.zig`

- [ ] Per-thread command pools
- [ ] Parallel command buffer recording
- [ ] Thread-safe descriptor allocation
- [ ] Transfer queue background uploads

**Priority:** LOW

---

## Phase 8: Integration with Grim

### 8.1 Replace Stub Implementation
**File:** `ui-tui/vulkan_renderer.zig` (rewrite)

- [ ] Remove stub types
- [ ] Import `lib/vulkan/*` modules
- [ ] Implement VulkanRenderer using real API
- [ ] Integrate with existing Editor widget
- [ ] Handle window resize events
- [ ] Implement render() method

**Priority:** HIGH

### 8.2 Phantom Integration
**File:** `ui-tui/vulkan_integration.zig` (update)

- [ ] Surface creation from Phantom window
- [ ] Resize handling
- [ ] VSync configuration from settings
- [ ] Swap interval control
- [ ] Error reporting to UI

**Priority:** HIGH

### 8.3 Performance Testing
**Files:** Create test suite

- [ ] Frame time benchmarks
- [ ] Memory usage profiling
- [ ] Large file rendering (10K+ lines)
- [ ] Rapid scrolling performance
- [ ] Atlas cache efficiency
- [ ] GPU memory tracking

**Priority:** MEDIUM

---

## Shaders to Implement

### text.vert (Vertex Shader)
```glsl
#version 450

// Per-vertex
layout(location = 0) in vec2 in_position;  // Quad corner (0,0 to 1,1)

// Per-instance
layout(location = 1) in vec2 in_glyph_pos;     // Screen position
layout(location = 2) in vec2 in_glyph_size;    // Glyph dimensions
layout(location = 3) in vec4 in_atlas_rect;    // UV coords in atlas
layout(location = 4) in vec4 in_color;         // Text color

layout(set = 0, binding = 0) uniform Uniforms {
    mat4 projection;
    vec2 viewport_size;
} uniforms;

layout(location = 0) out vec2 frag_uv;
layout(location = 1) out vec4 frag_color;

void main() {
    vec2 screen_pos = in_glyph_pos + (in_position * in_glyph_size);
    vec2 ndc = (screen_pos / uniforms.viewport_size) * 2.0 - 1.0;

    gl_Position = vec4(ndc, 0.0, 1.0);

    frag_uv = in_atlas_rect.xy + (in_position * in_atlas_rect.zw);
    frag_color = in_color;
}
```

### text.frag (Fragment Shader)
```glsl
#version 450

layout(set = 0, binding = 1) uniform sampler2D atlas_texture;

layout(location = 0) in vec2 frag_uv;
layout(location = 1) in vec4 frag_color;

layout(location = 0) out vec4 out_color;

void main() {
    float alpha = texture(atlas_texture, frag_uv).r;
    out_color = vec4(frag_color.rgb, frag_color.a * alpha);
}
```

Compile with:
```bash
glslangValidator -V text.vert -o text.vert.spv
glslangValidator -V text.frag -o text.frag.spv
```

---

## Build Integration

### build.zig Changes

```zig
// Add Vulkan library module
const vulkan = b.addModule("vulkan", .{
    .root_source_file = b.path("lib/vulkan/mod.zig"),
});

// Link Vulkan loader (dynamic)
exe.linkSystemLibrary("vulkan");

// Add shader compilation step
const compile_shaders = b.addSystemCommand(&.{
    "glslangValidator",
    "-V",
    "shaders/text.vert",
    "-o",
    "shaders/text.vert.spv",
});
compile_shaders.step.name = "Compile shaders";
exe.step.dependOn(&compile_shaders.step);

// Embed shader SPIR-V in binary
exe.root_module.addAnonymousImport("text_vert_spv", .{
    .root_source_file = b.path("shaders/text.vert.spv"),
});
```

---

## Directory Structure

```
lib/vulkan/
├── mod.zig              # Main module exports
├── loader.zig           # Dynamic library loading
├── types.zig            # Vulkan type definitions
├── instance.zig         # Instance management
├── device.zig           # Device management
├── surface.zig          # Surface creation
├── swapchain.zig        # Swapchain management
├── memory.zig           # Memory allocator
├── buffer.zig           # Buffer management
├── image.zig            # Image management
├── sampler.zig          # Sampler creation
├── descriptor.zig       # Descriptor management
├── shader.zig           # Shader modules
├── render_pass.zig      # Render pass
├── pipeline.zig         # Pipeline creation
├── command.zig          # Command buffers
├── sync.zig             # Synchronization
├── error.zig            # Error handling
├── glyph_atlas.zig      # Glyph atlas manager
├── text_renderer.zig    # Text rendering
├── frame_pacing.zig     # Frame pacing (optional)
├── profiling.zig        # Profiling (optional)
└── threading.zig        # Multi-threading (optional)

shaders/
├── text.vert            # Text vertex shader (GLSL)
├── text.frag            # Text fragment shader (GLSL)
├── text.vert.spv        # Compiled SPIR-V
└── text.frag.spv        # Compiled SPIR-V

ui-tui/
├── vulkan_renderer.zig  # Rewrite using lib/vulkan
└── vulkan_integration.zig  # Updated Phantom integration
```

---

## Implementation Strategy

### Week 1: Foundation (Phase 1-2)
- [ ] Vulkan loader and function pointer loading
- [ ] Type definitions and error handling
- [ ] Instance and device creation
- [ ] Surface and swapchain setup

**Milestone:** Can create a window with Vulkan swapchain (no rendering yet)

### Week 2: Resources (Phase 3)
- [ ] Memory allocator
- [ ] Buffer and image management
- [ ] Descriptor sets
- [ ] Command buffer recording

**Milestone:** Can allocate GPU resources and submit commands

### Week 3: Rendering (Phase 4-5)
- [ ] Shader modules and pipeline creation
- [ ] Render pass and framebuffers
- [ ] Command buffer submission
- [ ] Synchronization primitives

**Milestone:** Can render a single triangle

### Week 4: Text Rendering (Phase 6)
- [ ] Glyph atlas implementation
- [ ] Instanced quad rendering
- [ ] Text shaders (GLSL → SPIR-V)
- [ ] Integration with Editor

**Milestone:** Can render text with proper glyph atlas

### Week 5: Polish (Phase 7-8)
- [ ] Performance optimization
- [ ] Error handling polish
- [ ] Multi-threading (if needed)
- [ ] Testing and validation

**Milestone:** Production-ready text renderer

---

## Key Design Decisions

### 1. No vulkan-zig dependency
**Rationale:** Full control over API surface, easier debugging, no external breakage

### 2. Dynamic loading only
**Rationale:** No static libvulkan.a linking, works on all platforms, smaller binary

### 3. Error types over optionals
**Rationale:** Integrate with Zig's error handling, better error context

### 4. Pool allocators
**Rationale:** Reduce allocation overhead, better cache locality

### 5. Instanced rendering
**Rationale:** Minimize draw calls, batch thousands of glyphs per frame

---

## Testing Plan

### Unit Tests
- [ ] Loader: Dynamic library loading
- [ ] Types: Bitfield packing
- [ ] Memory: Allocator correctness
- [ ] Atlas: Glyph packing algorithm

### Integration Tests
- [ ] Instance: Create/destroy lifecycle
- [ ] Device: Queue family discovery
- [ ] Swapchain: Resize handling
- [ ] Pipeline: Shader compilation

### Validation Layers
Enable in debug builds:
```zig
const layers = [_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
};
```

### Performance Benchmarks
- [ ] Frame time: Target 144Hz (6.9ms)
- [ ] Memory: < 100MB for 10K line file
- [ ] Latency: < 1 frame input lag

---

## Resources & References

### Vulkan Specification
- https://www.khronos.org/registry/vulkan/specs/1.3/html/
- https://registry.khronos.org/vulkan/specs/1.3-extensions/man/html/

### Tutorials
- https://vulkan-tutorial.com/
- https://vkguide.dev/
- https://github.com/KhronosGroup/Vulkan-Samples

### Zig Examples
- https://github.com/Snektron/vulkan-zig (reference, not dependency)
- https://github.com/hexops/mach-gpu-dawn (WebGPU alternative)

### Text Rendering
- https://github.com/Chlumsky/msdfgen (SDF fonts)
- https://github.com/mapbox/tiny-sdf (Tiny SDF)
- FreeType documentation: https://freetype.org/freetype2/docs/

---

## Success Criteria

### Performance
- [x] 144Hz stable frame rate (6.9ms budget)
- [x] < 1 frame input latency
- [x] Smooth scrolling at 10K+ lines
- [x] < 100MB GPU memory for typical files

### Quality
- [x] Crisp text at all sizes
- [x] Subpixel antialiasing
- [x] Proper gamma correction
- [x] No tearing (VSync)

### Compatibility
- [x] Linux (Wayland + X11)
- [x] Vulkan 1.1+ support (no 1.3 exclusive features)
- [x] Integrated + dedicated GPUs
- [x] Graceful fallback on missing features

---

## Notes

- Start with **minimum viable pipeline** (Phases 1-6)
- Add advanced features (Phase 7) only if needed
- Profile early and often
- Validation layers in debug builds mandatory
- Keep shader code simple (readability > cleverness)
- Document every VkResult error path

## Questions to Answer During Implementation

1. **Memory strategy**: Single large allocation vs many small?
2. **Staging buffers**: One shared vs per-frame?
3. **Descriptor sets**: Per-frame vs cached?
4. **Command buffers**: Re-record every frame vs reuse?
5. **Atlas format**: R8 vs RGBA8? Signed distance fields?
6. **Transfer queue**: Dedicated vs graphics queue?

---

**Start Date:** TBD
**Target Completion:** 4-5 weeks
**Owner:** @user
**Status:** Planning

---

Generated with Claude Code - Sprint 18 Option B (Vulkan Integration Research)
