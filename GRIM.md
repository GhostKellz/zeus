# Zeus Requirements for Grim Integration

**Purpose:** Documents what Zeus (the library) must provide for Grim editor integration.

This file focuses on **Zeus's responsibilities only**. Grim-side integration work is documented in `/data/projects/grim/zeus_integration.md`.

---

## Zeus Library Responsibilities

### 1. Public API Surface

Zeus must expose these core types and functions for Grim to consume:

```zig
// lib/vulkan/mod.zig - Public exports

// Core initialization
pub const Instance = @import("instance.zig").Instance;
pub const Device = @import("device.zig").Device;
pub const PhysicalDevice = @import("physical_device.zig").PhysicalDevice;
pub const Surface = @import("surface.zig").Surface;
pub const Swapchain = @import("swapchain.zig").Swapchain;

// Text rendering (primary use case)
pub const TextRenderer = @import("text_renderer.zig").TextRenderer;
pub const GlyphAtlas = @import("glyph_atlas.zig").GlyphAtlas;

// Resource management
pub const Buffer = @import("buffer.zig").Buffer;
pub const Image = @import("image.zig").Image;

// Types for Grim to use
pub const Error = @import("error.zig").Error;
pub const types = @import("types.zig");
```

### 2. TextRenderer API Contract

**Grim expects this exact API:**

```zig
pub const TextRenderer = struct {
    // Initialization
    pub fn init(
        allocator: std.mem.Allocator,
        device: *Device,
        config: TextRendererConfig,
    ) Error!*TextRenderer;

    pub fn deinit(self: *TextRenderer) void;

    // Frame lifecycle (called every frame by Grim)
    pub fn beginFrame(self: *TextRenderer, frame_index: u32) Error!void;
    pub fn endFrame(self: *TextRenderer) void;

    // Projection matrix (set once per frame or on resize)
    pub fn setProjection(
        self: *TextRenderer,
        frame_index: u32,
        matrix: *const [16]f32,
    ) Error!void;

    // Glyph rendering (called many times per frame)
    pub fn queueQuad(
        self: *TextRenderer,
        quad: GlyphQuad,
    ) Error!void;

    // Optional Phase 6 optimization: batch multiple quads with AVX2 acceleration
    pub fn queueQuads(
        self: *TextRenderer,
        quads: []const GlyphQuad,
    ) Error!void;

    // Command encoding (submit to GPU)
    pub fn encode(
        self: *TextRenderer,
        command_buffer: types.VkCommandBuffer,
        frame_index: u32,
    ) Error!void;

    // Atlas management (Grim uploads rasterized glyphs)
    pub fn glyphAtlas(self: *TextRenderer) *GlyphAtlas;
};

pub const TextRendererConfig = struct {
    extent: types.VkExtent2D,
    surface_format: types.VkFormat,
    memory_props: types.VkPhysicalDeviceMemoryProperties,
    frames_in_flight: u32,
    max_instances: u32,
};

pub const GlyphQuad = struct {
    position: [2]f32,           // Screen-space position (pixels)
    size: [2]f32,               // Glyph dimensions (pixels)
    atlas_rect: [4]f32,         // UV coordinates (normalized 0-1)
    color: [4]f32,              // RGBA color (normalized 0-1)
};
```

**Status:** ✅ Already implemented in `lib/vulkan/text_renderer.zig:45-120`

### 3. GlyphAtlas API Contract

**Grim needs these methods to upload rasterized glyphs:**

```zig
pub const GlyphAtlas = struct {
    // Reserve space in atlas (returns UV coordinates)
    pub fn reserveRect(
        self: *GlyphAtlas,
        width: u32,
        height: u32,
    ) Error!AtlasRect;

    // Upload glyph bitmap to reserved region
    pub fn upload(
        self: *GlyphAtlas,
        rect: AtlasRect,
        data: []const u8,  // R8_UNORM grayscale alpha channel
    ) Error!void;

    // Query atlas state
    pub fn getSize(self: *GlyphAtlas) types.VkExtent2D;
    pub fn getFormat(self: *GlyphAtlas) types.VkFormat;
};

pub const AtlasRect = struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,

    // Helper to convert to UV coordinates
    pub fn toUV(self: AtlasRect, atlas_width: u32, atlas_height: u32) [4]f32 {
        return .{
            @as(f32, @floatFromInt(self.x)) / @as(f32, @floatFromInt(atlas_width)),
            @as(f32, @floatFromInt(self.y)) / @as(f32, @floatFromInt(atlas_height)),
            @as(f32, @floatFromInt(self.x + self.width)) / @as(f32, @floatFromInt(atlas_width)),
            @as(f32, @floatFromInt(self.y + self.height)) / @as(f32, @floatFromInt(atlas_height)),
        };
    }
};
```

**Status:** ✅ Already implemented in `lib/vulkan/glyph_atlas.zig:35-90`

### 4. Surface Creation Support

**Zeus must support Wayland surface creation from Phantom/wzl:**

```zig
pub const Surface = struct {
    pub fn initWayland(
        instance: *Instance,
        display: *anyopaque,  // wl_display
        surface: *anyopaque,  // wl_surface
    ) Error!*Surface;

    pub fn deinit(self: *Surface) void;

    // Query capabilities
    pub fn getCapabilities(
        self: *Surface,
        physical_device: *PhysicalDevice,
    ) Error!types.VkSurfaceCapabilitiesKHR;

    pub fn getFormats(
        self: *Surface,
        physical_device: *PhysicalDevice,
        allocator: std.mem.Allocator,
    ) Error![]types.VkSurfaceFormatKHR;

    pub fn getPresentModes(
        self: *Surface,
        physical_device: *PhysicalDevice,
        allocator: std.mem.Allocator,
    ) Error![]types.VkPresentModeKHR;
};
```

**Status:** ✅ Already implemented in `lib/vulkan/surface.zig:55-78` (Wayland support)

### 5. Swapchain Resize Support

**Zeus must handle window resize gracefully:**

```zig
pub const Swapchain = struct {
    pub fn recreate(
        self: *Swapchain,
        new_extent: types.VkExtent2D,
    ) Error!void;

    pub fn acquireNextImage(
        self: *Swapchain,
        semaphore: types.VkSemaphore,
        fence: types.VkFence,
    ) Error!u32;

    pub fn present(
        self: *Swapchain,
        queue: types.VkQueue,
        image_index: u32,
        wait_semaphore: types.VkSemaphore,
    ) Error!void;
};
```

**Status:** ✅ Already implemented in `lib/vulkan/swapchain.zig:120-180`

### 6. Error Handling Contract

**Zeus must provide clear error types:**

```zig
pub const Error = error{
    // Initialization errors
    VulkanNotFound,
    InstanceCreationFailed,
    DeviceCreationFailed,
    SurfaceCreationFailed,

    // Memory errors
    OutOfHostMemory,
    OutOfDeviceMemory,

    // Runtime errors
    DeviceLost,
    SurfaceLost,
    OutOfDate,  // Swapchain needs recreation

    // Generic
    VulkanError,
};
```

**Status:** ✅ Already implemented in `lib/vulkan/error.zig:10-35`

---

## Zeus Build Configuration

### build.zig.zon (Package Metadata)

**Grim will depend on Zeus via:**

```zig
// In Grim's build.zig.zon
.dependencies = .{
    .zeus = .{
        .url = "https://github.com/ghostkellz/zeus/archive/<commit-hash>.tar.gz",
        .hash = "<hash>",
    },
},
```

**Zeus Phase 8 Task:**
- [ ] Create proper `build.zig.zon` with semantic versioning
- [ ] Tag stable releases (e.g., `v0.1.0-alpha`)
- [ ] Document minimum Zig version requirement (0.16.0-dev)

### build.zig (Library Module)

**Zeus must export as a Zig module:**

```zig
// Zeus's build.zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Zeus library module
    const zeus_module = b.addModule("zeus", .{
        .root_source_file = b.path("lib/vulkan/mod.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Embed shaders
    zeus_module.addAnonymousImport("text.vert.spv", .{
        .root_source_file = b.path("shaders/text.vert.spv"),
    });
    zeus_module.addAnonymousImport("text.frag.spv", .{
        .root_source_file = b.path("shaders/text.frag.spv"),
    });

    // Dynamic Vulkan loading (no static linking)
    zeus_module.link_libc = false;  // Pure Zig
}
```

**Status:** 🔜 Phase 8 - Need to finalize build.zig for library export

---

## Zeus Testing Requirements

### Integration Test for Grim Use Case

**Zeus must provide a test simulating Grim's rendering pattern:**

```zig
// lib/vulkan/text_renderer_integration_test.zig

test "Grim rendering pattern - 10K glyphs" {
    const allocator = std.testing.allocator;

    // Simulate Grim's typical frame
    const glyph_count = 10_000;
    var glyphs: [glyph_count]GlyphQuad = undefined;

    // ... setup renderer, device, etc. ...

    try renderer.beginFrame(0);

    // Grim queues thousands of glyphs per frame
    for (glyphs) |glyph| {
        try renderer.queueQuad(glyph);
    }

    try renderer.encode(command_buffer, 0);
    renderer.endFrame();

    // Verify no memory leaks, no crashes
    try std.testing.expect(renderer.instance_count == glyph_count);
}

test "Grim atlas upload pattern" {
    const allocator = std.testing.allocator;

    var atlas = try GlyphAtlas.init(allocator, ...);
    defer atlas.deinit();

    // Grim uploads many glyphs (FreeType rasterization)
    for (0..100) |i| {
        const rect = try atlas.reserveRect(32, 32);
        const glyph_bitmap: [32 * 32]u8 = undefined;  // Simulated FreeType output
        try atlas.upload(rect, &glyph_bitmap);
    }

    // Verify atlas grew correctly, no leaks
}
```

**Status:** 🔜 Phase 7 - Add integration tests

---

## Zeus Performance Guarantees

**Commitments to Grim:**

| Metric | Target | Grim Requirement |
|--------|--------|------------------|
| **Frame time (144Hz)** | < 6.9ms | Text editor must feel instant |
| **Frame time (240Hz)** | < 4.16ms | Competitive editing experience |
| **Glyph throughput** | 10K+ glyphs/frame | Large files (10K lines) |
| **Memory usage** | < 100MB GPU | Typical file sizes |
| **Atlas uploads** | < 200μs/glyph | FreeType rasterization bottleneck |
| **Input latency** | < 1 frame | Keystroke → render → display |

**Zeus Optimization Areas (Phase 6):**
- [ ] AVX2 SIMD glyph batching (~435μs savings @ 240Hz)
- [ ] Command buffer reuse (reduce vkAllocate overhead)
- [ ] Descriptor caching (avoid redundant updates)

---

## Zeus Shader Requirements

### Vertex Shader (`shaders/text.vert`)

**Must generate instanced quads from per-glyph data:**

```glsl
#version 450

// Per-instance data (from Grim's GlyphQuad)
layout(location = 0) in vec2 position;    // Screen-space position
layout(location = 1) in vec2 size;        // Glyph dimensions
layout(location = 2) in vec4 atlas_rect;  // UV coordinates
layout(location = 3) in vec4 color;       // RGBA color

// Uniform buffer (projection matrix)
layout(set = 0, binding = 0) uniform UBO {
    mat4 projection;
} ubo;

// Outputs to fragment shader
layout(location = 0) out vec2 frag_uv;
layout(location = 1) out vec4 frag_color;

void main() {
    // Generate quad vertex (0-3 for corners)
    vec2 corners[4] = vec2[](
        vec2(0.0, 0.0),  // Top-left
        vec2(1.0, 0.0),  // Top-right
        vec2(0.0, 1.0),  // Bottom-left
        vec2(1.0, 1.0)   // Bottom-right
    );

    vec2 corner = corners[gl_VertexIndex];
    vec2 world_pos = position + corner * size;

    gl_Position = ubo.projection * vec4(world_pos, 0.0, 1.0);

    // Interpolate UV coordinates
    frag_uv = mix(atlas_rect.xy, atlas_rect.zw, corner);
    frag_color = color;
}
```

**Status:** ✅ Implemented in `shaders/text.vert`

### Fragment Shader (`shaders/text.frag`)

**Must sample atlas and apply alpha blending:**

```glsl
#version 450

layout(location = 0) in vec2 frag_uv;
layout(location = 1) in vec4 frag_color;

layout(set = 0, binding = 1) uniform sampler2D atlas_sampler;

layout(location = 0) out vec4 out_color;

void main() {
    float alpha = texture(atlas_sampler, frag_uv).r;  // R8_UNORM atlas
    out_color = vec4(frag_color.rgb, frag_color.a * alpha);
}
```

**Status:** ✅ Implemented in `shaders/text.frag`

**SPIR-V Compilation:**
```bash
cd shaders
glslangValidator -V text.vert -o text.vert.spv
glslangValidator -V text.frag -o text.frag.spv
```

**Phase 6 Task:**
- [ ] Verify SPIR-V 4-byte alignment (`@embedFile` + `align(@alignOf(u32))`)

---

## Zeus Platform Support

**Minimum requirements for Grim:**

| Platform | Status | Notes |
|----------|--------|-------|
| **Linux + Wayland** | ✅ Primary | Hyprland, Sway, GNOME, KDE |
| **Linux + X11** | 🔜 Phase 7 | Fallback for older systems |
| **NVIDIA GPUs** | ✅ Primary | RTX 3000+ series, 144-360Hz |
| **AMD GPUs** | 🔜 Phase 7 | RADV driver support (RX 6000+) |
| **Intel GPUs** | 🚀 Post-MVP | Arc series (A770+) |
| **Windows** | 🚀 Post-MVP | Via native Vulkan driver |
| **macOS** | 🚀 Post-MVP | Via MoltenVK (low priority) |

**Grim Deployment Target:** Arch Linux + Wayland + NVIDIA (primary)

---

## Zeus Version Compatibility

**Semantic Versioning:**

- **0.1.0-alpha** - Phase 6 complete (high refresh rate optimization)
- **0.2.0-beta** - Phase 7 complete (production polish, AMD support)
- **1.0.0** - Phase 8 complete (Grim integration validated)

**Breaking Changes Policy:**
- Major version bump for API changes
- Minor version for new features (backward compatible)
- Patch version for bug fixes only

**Grim Integration Timeline:**
- **Phase 6** (Zeus): Optimize for 240Hz, finalize API
- **Phase 7** (Zeus): Production hardening, documentation
- **Phase 8** (Zeus): Export as library, tag v1.0.0
- **Grim Integration** (Grim repo): Replace stubs, wire Zeus, validate

---

## Zeus Documentation Deliverables for Grim

**Required for Phase 8:**

1. **API Reference** (`docs/API.md`)
   - All public types, functions, error codes
   - Example usage for common patterns

2. **Integration Guide** (`docs/INTEGRATION.md`) ✅ Already exists
   - Step-by-step Grim integration walkthrough
   - Performance tuning recommendations

3. **Migration Guide** (`docs/MIGRATION.md`)
   - How to replace Grim's stub renderer
   - API mapping (old stubs → Zeus API)

4. **Performance Guide** (`docs/PERFORMANCE.md`) ✅ Already exists
   - Frame budgets for 144-360Hz
   - Profiling tools (RenderDoc, Nsight)

---

## Zeus Responsibilities Summary

### ✅ Already Complete (Phase 5)
- TextRenderer API with frame lifecycle
- GlyphAtlas with rectangle packing
- Wayland surface support
- Swapchain management with resize
- SPIR-V shaders (embedded)

### 🔜 Phase 6 (High Refresh Rate Optimization)
- AVX2 SIMD glyph batching
- ReBAR detection for NVIDIA RTX 4090
- SPIR-V alignment verification
- Frame pacing (144-360Hz)

### 🔜 Phase 7 (Production Polish)
- AMD GPU support (RADV)
- Validation layer integration
- Hot shader reload
- GPU profiling tools
- API documentation

### 🔜 Phase 8 (Library Export)
- Finalize build.zig for library module
- Create build.zig.zon with versioning
- Tag v1.0.0 release
- Integration tests for Grim use case
- Migration guide for Grim

---

**Grim-side integration is documented in:** `/data/projects/grim/zeus_integration.md`

**Built with Zig**
