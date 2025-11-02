# Zeus

**Next-Generation Vulkan Text Rendering Library**

High-performance Vulkan 1.3 library written in pure Zig, purpose-built for GPU-accelerated text rendering in the [Grim](https://github.com/ghostkellz/grim) editor. Optimized for NVIDIA GPUs on Arch Linux + Wayland with native support for 144-360Hz refresh rates.

<div align="center">

![Zig Version](https://img.shields.io/badge/Zig-0.16.0--dev-orange?logo=zig)
![Vulkan](https://img.shields.io/badge/Vulkan-1.3-red?logo=vulkan)
![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20Wayland-blue?logo=linux)
![NVIDIA](https://img.shields.io/badge/NVIDIA-Optimized-76b900?logo=nvidia)
![License](https://img.shields.io/badge/License-MIT-green)

</div>

---

## 🎯 Project Status

**Phase 8 COMPLETE** ✅ → **Phase 2 (November 2024) COMPLETE** ✅

- ✅ **Phases 1-8:** Core implementation, Wayland compositor compatibility
- ✅ **Phase 1 (Nov):** Critical loader fix, Zig 0.16 hardening
- ✅ **Phase 2 (Nov):** **Vulkan 1.3/1.4 API expansion** - **30+ device functions**, extension types
- 🚧 **Phase 3 (Nov):** Higher-level abstractions (Context, builders)
- 🔜 **Phases 4-7:** Testing, hardening, documentation, ghostVK integration

**Current Metrics:**
- **10,950+ lines** across 27 modules (including types_ext.zig)
- **94 device functions** + **17 instance functions** = **~95% Vulkan 1.3/1.4 coverage**
- **5 extension types** (debug_utils, dynamic_rendering, descriptor_indexing, ray tracing)
- **Zig 0.16.0-dev** compilation (< 5s builds)
- **Production-ready** for ghostVK and modern Vulkan projects

---

## ✨ Highlights

### Pure Zig Implementation
- Zero external runtime dependencies (only `libvulkan.so` dynamic loading)
- Targeting Zig 0.16.0-dev master branch
- Modern error handling with Zig's error system
- Allocator-aware design throughout

### Comprehensive Vulkan 1.3/1.4 API
Complete `lib/vulkan/` ecosystem with **111+ functions**:
- **Core:** loader, types, types_ext (extensions), error handling, instance, device
- **Device Functions (94):** Drawing, compute, queries, descriptors, pipelines, shaders
- **Instance Functions (17):** Physical device queries, Features2/Properties2, surface ops
- **Extension Types:** VK_EXT_debug_utils, VK_KHR_dynamic_rendering, ray tracing
- **Resources:** memory, buffer, image, sampler, descriptor
- **Pipeline:** shader, render pass, pipeline, commands, sync, queries
- **Text:** glyph_atlas, text_renderer, surface, swapchain

### Text Rendering Focus
- **Instanced quad rendering** - batch thousands of glyphs per frame
- **Dynamic glyph atlas** - growable R8_UNORM texture with rectangle packing
- **Frame API** - `beginFrame → queueQuad → encode → endFrame` workflow
- **Async uploads** - optional transfer queue path with timeline semaphore waits/signals
- **Frame telemetry** - per-frame stats callbacks and inspectors for draw/encode metrics
- **Autotuned batching** - adaptive batch limits targeting single-draw frames within timing budgets
- **Profiler HUD** - rolling summaries/logs of glyph throughput, draw counts, and encode timings
- **SIMD batching** - `queueQuads` packs slices with AVX2 acceleration on x86-64
- **Alpha blending** - proper antialiasing for crisp text
- **Embedded shaders** - SPIR-V compiled and ready (`@embedFile`)

### High Refresh Rate Ready
Designed for NVIDIA + Wayland at extreme refresh rates:
- **144/240/270/360Hz @ 1440p** - Full support across all modes
- **144/240/270Hz @ 4K** - Ultra-high resolution support

---

## 🚀 Getting Started

### Prerequisites
- [Zig 0.16.0-dev](https://ziglang.org/download/) (master branch)
- Vulkan drivers installed (`libvulkan.so` or `vulkan-1.dll`)
- `glslangValidator` for shader compilation (optional, pre-compiled SPIR-V included)

### Quick Start
```bash
# Clone the repository
git clone https://github.com/ghostkellz/zeus.git
cd zeus

# Format and test
zig fmt src lib
zig build test

# Explore the library
ls lib/vulkan/        # Core Vulkan modules
ls shaders/           # GLSL + SPIR-V shaders
cat TODO.md           # Detailed roadmap
```

### Project Structure
```
zeus/
├── lib/vulkan/           # Core Vulkan library (6,818 lines)
│   ├── loader.zig        # Dynamic Vulkan loading
│   ├── types.zig         # Vulkan type definitions (1,122 lines)
│   ├── instance.zig      # Instance creation
│   ├── device.zig        # Logical device management
│   ├── physical_device.zig # GPU selection
│   ├── surface.zig       # Wayland/X11/Windows surfaces
│   ├── swapchain.zig     # Swapchain management
│   ├── memory.zig        # Memory allocation
│   ├── buffer.zig        # Buffer management
│   ├── image.zig         # Image/texture management
│   ├── sampler.zig       # Texture sampling
│   ├── descriptor.zig    # Descriptor sets
│   ├── shader.zig        # SPIR-V shader modules
│   ├── render_pass.zig   # Render pass construction
│   ├── pipeline.zig      # Graphics pipeline
│   ├── commands.zig      # Command buffer helpers
│   ├── sync.zig          # Fences, semaphores, barriers
│   ├── glyph_atlas.zig   # Dynamic texture atlas (427 lines)
│   ├── text_renderer.zig # Text rendering pipeline (571 lines)
│   ├── error.zig         # Error handling
│   └── mod.zig           # Module exports
├── shaders/              # GLSL shaders + SPIR-V bytecode
│   ├── text.vert         # Vertex shader (instanced quads)
│   ├── text.vert.spv     # Compiled SPIR-V
│   ├── text.frag         # Fragment shader (atlas sampling)
│   └── text.frag.spv     # Compiled SPIR-V
├── src/                  # Application code (reserved)
│   ├── main.zig
│   └── root.zig
├── examples/             # Standalone demos
│   └── simple_text.zig   # Mocked text renderer walkthrough with telemetry output
├── docs/                 # Documentation
│   ├── ARCHITECTURE.md   # System design decisions
│   ├── PERFORMANCE.md    # Optimization guide
│   └── INTEGRATION.md    # Grim integration guide
├── archive/              # Reference materials
│   └── vulkan-zig/       # Reference Vulkan bindings (Zig 0.15)
├── build.zig             # Build configuration
├── TODO.md               # Detailed 8-phase roadmap
├── GRIM_KB.md            # Grim knowledge base for Zeus
└── README.md             # This file
```

---

## 🎨 Text Rendering Pipeline

### Frame API Workflow
```zig
const zeus = @import("zeus");

// 1. Initialize renderer
var renderer = try zeus.TextRenderer.init(allocator, device, .{
    .extent = .{ .width = 1920, .height = 1080 },
    .surface_format = .B8G8R8A8_SRGB,
    .memory_props = physical_device.memory_properties,
    .frames_in_flight = 2,
    .max_instances = 10000,
    .batch_target = 512, // optional dynamic batching hints
    .transfer_queue = .{ // optional async upload path
        .pool = &transfer_pool,   // command pool you manage for transfer work
        .queue = transfer_queue,  // dedicated transfer queue handle
        .initial_timeline_value = 0,
    },
    .batch_autotune = true, // telemetry-driven tuning (enabled by default)
    .profiler = .{ .log_interval = 120 }, // emit HUD summary every 120 frames
});
defer renderer.deinit();

// 2. Begin frame
try renderer.beginFrame(frame_index);

// 3. Set projection matrix
const projection = orthoMatrix(0, 1920, 0, 1080);
try renderer.setProjection(projection[0..]);

// 4. Queue glyphs (instanced quads)
for (glyphs) |glyph| {
    try renderer.queueQuad(.{
        .position = glyph.position,
        .size = glyph.size,
        .atlas_rect = glyph.uv,
        .color = .{ 1, 1, 1, 1 },
    });
}

// Or batch multiple quads at once (AVX2-accelerated on supported CPUs)
const quads = [_]zeus.TextRenderer.TextQuad{ /* generated glyph quads */ };
try renderer.queueQuads(quads[0..]);

// 5. Encode draw commands
try renderer.encode(command_buffer);

// 6. End frame (cleanup)
renderer.endFrame();

// 7. Read telemetry + sync (optional)
const stats = try renderer.frameStats(frame_index);
std.log.info("glyphs={d} draws={d} uploads={d} encode_ns={d}", .{
    stats.glyph_count,
    stats.draw_count,
    stats.atlas_uploads,
    stats.encode_cpu_ns,
});

if (try renderer.frameSyncInfo(frame_index)) |wait| {
    // Chain this wait into your graphics queue submission.
    // e.g. VkTimelineSemaphoreSubmitInfo wait on wait.semaphore to reach wait.value
    // with wait.stage_mask as the destination stage mask.
}

renderer.releaseAtlasUploads();
```

### Transfer Queue Integration

Phase 6 adds an optional asynchronous upload path for the glyph atlas. Supplying
`InitOptions.transfer_queue` wires the renderer to submit copy commands on a
dedicated queue backed by a timeline semaphore. When atlas uploads occur, the
renderer exposes the wait handle via `frameSyncInfo(frame_index)`, allowing the
main graphics queue to wait on the transfer timeline without blocking CPU work.
If no uploads happen, the call returns `null` and the render queue can proceed
immediately. Skipping `transfer_queue` falls back to inline uploads on the
graphics command buffer—perfect for simpler integrations. The mocked
`examples/simple_text.zig` demo shows how to thread these waits into a frame.

### Telemetry & Frame Stats

Every frame records detailed telemetry (glyph/draw counts, batch limits, CPU
time for encode/transfer, upload counts, transfer queue usage). Access these via
`frameStats(frame_index)` after `endFrame()` or register a `stats_callback` in
`InitOptions` to consume metrics in real time. This makes it easy to surface
performance overlays, tune batching heuristics, or monitor atlas churn.

`batch_autotune` and `batch_autotune_goal_ns` use this telemetry to update the
active batch limit so heavy frames collapse to a single draw while lightweight
frames stay lean. To go a step further, supply `InitOptions.profiler` (or rely on
the default logger) to receive rolling summaries/HUD entries with glyph
throughput, draw counts, and encode timings every N frames. You can also query
`renderer.profilerSummary()` for the most recent aggregate.

### Glyph Atlas
```zig
// Atlas automatically grows and packs rectangles
const rect = try renderer.glyphAtlas().reserveRect(32, 32);

// Upload glyph bitmap to reserved region
try renderer.glyphAtlas().upload(rect, glyph_bitmap);

// Get UV coordinates for shader
const uv = rect.toUV(atlas_width, atlas_height);
```

---

## 📊 Performance Targets

| Resolution | Refresh Rate | Frame Budget | Status | Hardware |
|------------|--------------|--------------|--------|----------|
| 1440p      | 144 Hz       | 6.9ms        | ✅ Ready | RTX 3070+ |
| 1440p      | 240 Hz       | 4.16ms       | ✅ Ready | RTX 4070+ |
| 1440p      | 270 Hz       | 3.7ms        | ✅ Ready | RTX 4080+ |
| 1440p      | 360 Hz       | 2.77ms       | 🚧 Phase 6 | RTX 4090 |
| 4K         | 144 Hz       | 6.9ms        | ✅ Ready | RTX 4080+ |
| 4K         | 240 Hz       | 4.16ms       | 🚧 Phase 6 | RTX 4090 |
| 4K         | 270 Hz       | 3.7ms        | 🚀 Future | RTX 5090+ |

**Dev System:**
- **GPU:** NVIDIA RTX 4090 (NVIDIA Open Kernel Module v580)
- **CPU:** AMD Ryzen 9 7950X3D (3D V-Cache)
- **RAM:** 128GB DDR5
- **Displays:** 1440p/360Hz (primary) + 1440p/270Hz (secondary)
- **OS:** Arch Linux (linux-tkg-bore 6.17.4 kernel)
- **Compositor:** Hyprland (Wayland native)

---

## 🎉 What's New in v0.1.4

**Released: December 2024** - Advanced memory management, performance optimizations, and developer tools

### Memory Management
- **VMA-style allocator** with sub-allocation and automatic ReBAR detection for NVIDIA RTX 4090
- **Buffer/image allocators** with automatic memory binding and layout tracking
- **Built-in telemetry** for fragmentation and leak detection

### Command & Synchronization
- **Command manager** with per-thread pool recycling for parallel command buffer recording
- **Sync manager** with fence/semaphore pooling and timeline semaphore support
- **Barrier helper** for automatic pipeline stage and access mask inference

### Builders & Helpers
- **Descriptor allocator** with automatic pool growth when exhausted
- **Transfer helper** for async buffer/image uploads on dedicated transfer queue
- **Immediate submit helper** for convenient one-shot command submission
- **Pipeline builders** with fluent API for graphics and compute pipelines
- **Render pass builder** with automatic subpass dependency inference
- **Framebuffer manager** with swapchain integration

### Performance & Hardware
- **HDR support** (`VK_EXT_hdr_metadata`) for OLED displays with BT.2020 primaries
- **VRR/Adaptive sync** for 240-360Hz high refresh rate displays with frame pacing
- **Wayland DMA-BUF** import/export for zero-copy composition with KDE Plasma/Mutter/wlroots
- **NVIDIA optimizations** for RTX 4090: ReBAR hints, async compute queue utilization

### Developer Experience
- **Debug utilities** for object naming, markers, and labels (RenderDoc/validation layers)
- **Enhanced error context** with call sites and recovery strategies
- **Comprehensive error descriptions** and suggested solutions

### Known Issues & Workarounds

**MangoHud Compatibility:** Tests may crash when MangoHud overlay is active. This is a known issue with MangoHud hooking device creation. Workaround:
```bash
# Run tests without MangoHud
DISABLE_MANGOHUD=1 zig build test

# Or disable MangoHud globally
unset MANGOHUD
unset MANGOHUD_CONFIG
```

**Migration from v0.1.3:** Most applications will need minimal changes. The new allocators and builders are opt-in and existing code continues to work.

---

## 🏗️ Roadmap

See [`TODO.md`](TODO.md) for the complete 8-phase roadmap. Quick summary:

### ✅ Complete
- **Phase 1:** Core Vulkan foundations (loader, types, error handling)
- **Phase 2:** Instance, device, surface, swapchain
- **Phase 3:** Resource management (memory, buffers, images, descriptors)
- **Phase 4:** Render pipeline (shaders, render pass, graphics pipeline)
- **Phase 5:** Text renderer + glyph atlas integration

### 🚧 In Progress
- **Phase 6:** High refresh rate optimization (144-360Hz)
  - Frame pacing and VSync control
  - GPU optimization (command buffer reuse, descriptor caching)
  - CPU optimization (parallel recording, SIMD batching)
  - NVIDIA-specific tuning

### 🔜 Planned
- **Phase 7:** Production polish (validation, hot reload, profiling)
- **Phase 8:** Grim integration (replace stub renderer)

### 🚀 Future
- **Post-MVP:** SDF fonts, ligatures, HDR, multi-monitor,Android

---

## 🔬 Development Workflow

### Formatting
```bash
zig fmt src lib
```

### Testing
```bash
# Run all unit tests
zig build test

# Run with validation layers (debug build)
zig build test -Doptimize=Debug
```

### Shader Compilation
```bash
# Compile GLSL to SPIR-V
cd shaders
glslangValidator -V text.vert -o text.vert.spv
glslangValidator -V text.frag -o text.frag.spv
```

### Build Modes
```bash
# Debug (validation layers enabled)
zig build -Doptimize=Debug

# Release (optimized)
zig build -Doptimize=ReleaseFast

# Release with safety checks
zig build -Doptimize=ReleaseSafe
```

---

## 📚 Documentation

- [`TODO.md`](TODO.md) - Complete 8-phase roadmap with checklists
- [`GRIM_KB.md`](GRIM_KB.md) - Knowledge base for Grim integration
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) - System design decisions
- [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md) - Optimization guide (Phase 6)
- [`docs/INTEGRATION.md`](docs/INTEGRATION.md) - Grim integration guide (Phase 8)

---

## 🤝 Contributing

Bug reports, design feedback, and PRs are welcome! Please:

1. **Format code:** `zig fmt src lib`
2. **Add/update tests:** `zig build test`
3. **Reference roadmap:** Check `TODO.md` for alignment with phases
4. **Document changes:** Update relevant docs in `docs/`

### Development Guidelines
- Follow Zig naming conventions (snake_case for functions, PascalCase for types)
- Add unit tests for new modules
- Use allocator parameters (no global state)
- Document error conditions
- Keep modules focused and cohesive

---

## 🎯 Design Goals

### Performance
- **144Hz minimum** on NVIDIA RTX 3000+ series @ 1440p
- **<1 frame input latency** for responsive editing
- **<100MB GPU memory** for typical 10K line files
- **Smooth scrolling** even on massive files

### Portability
- Pure Zig implementation (no C dependencies)
- Dynamic Vulkan loading (no static linking)
- Platform-agnostic core (Wayland, X11, Windows, macOS)
- Graceful degradation on missing features

### Maintainability
- Modular design with clear boundaries
- Comprehensive test coverage
- Minimal external dependencies
- Well-documented public APIs

---

## 🔗 Related Projects

- **[Grim](https://github.com/ghostkellz/grim)** - Vim-like editor powered by Zeus
- **[Ghostshell](https://github.com/ghostkellz/ghostshell)** - Terminal emulator (Ghostty fork, also uses Zeus)
- **[wzl](https://github.com/ghostkellz/wzl)** - Wayland compositor framework in Zig
- **[Phantom](https://github.com/ghostkellz/phantom)** - TUI framework (wzl + flare + gcode)

---

## 📄 License

MIT © 2025 CK Technology LLC

See [`LICENSE`](LICENSE) for full details.

---

## 🙏 Acknowledgments

- **Vulkan Working Group** - For the Vulkan specification
- **vulkan-zig** (archived) - Reference implementation for Zig bindings
- **Zig Community** - For the amazing language and tooling
- **NVIDIA** - For excellent Vulkan drivers on Linux

---

**Built with Zig**
