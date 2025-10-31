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

**Phase 5 COMPLETE** ✅ → Moving to **Phase 6: High Refresh Rate Optimization**

- ✅ **Phases 1-4:** Vulkan foundations (loader, types, device/swapchain, resources, pipeline)
- ✅ **Phase 5:** Text renderer wiring with `GlyphAtlas` and frame API complete
- 🚧 **Phase 6:** 144-360Hz optimization, frame pacing, NVIDIA-specific tuning
- 🔜 **Phase 7:** Production polish, validation, hot reload, profiling tools
- 🎯 **Phase 8:** Grim integration (replace 837 stub lines)

**Current Metrics:**
- **6,818 lines** across 22 modules
- **100% test coverage** of implemented phases
- **Zig 0.16.0-dev** compilation (< 5s builds)
- **SPIR-V shaders** embedded and ready

---

## ✨ Highlights

### Pure Zig Implementation
- Zero external runtime dependencies (only `libvulkan.so` dynamic loading)
- Targeting Zig 0.16.0-dev master branch
- Modern error handling with Zig's error system
- Allocator-aware design throughout

### Modular Vulkan Wrappers
Complete `lib/vulkan/` ecosystem:
- **Core:** loader, types, error handling, instance, device, physical device
- **Resources:** memory, buffer, image, sampler, descriptor
- **Pipeline:** shader, render pass, pipeline, commands, sync
- **Text:** glyph_atlas, text_renderer, surface, swapchain

### Text Rendering Focus
- **Instanced quad rendering** - batch thousands of glyphs per frame
- **Dynamic glyph atlas** - growable R8_UNORM texture with rectangle packing
- **Frame API** - `beginFrame → queueQuad → encode → endFrame` workflow
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
├── examples/             # Standalone demos (coming in Phase 6)
│   └── text_test.zig     # Planned: text rendering demo
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
});
defer renderer.deinit();

// 2. Begin frame
try renderer.beginFrame(frame_index);

// 3. Set projection matrix
const projection = orthoMatrix(0, 1920, 0, 1080);
try renderer.setProjection(frame_index, &projection);

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
try renderer.encode(command_buffer, frame_index);

// 6. End frame (cleanup)
renderer.endFrame();
```

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
- **Post-MVP:** SDF fonts, ligatures, HDR, multi-monitor, Android

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
