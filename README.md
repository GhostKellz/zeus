# Zeus

High-performance Vulkan tooling written in Zig and purpose-built to power the Grim text editor. Zeus provides a modern Vulkan 1.3 stack—loader, device helpers, resource management, and render pipeline utilities—optimized for glyph atlas rendering and instanced text drawing.

## Project status

Zeus is currently in **Phase 5 (integration)** of its roadmap.

- ✅ Phases 1‑4 delivered the Vulkan foundations: dynamic loader, core types, device/swapchain utilities, descriptor management, image/buffer helpers, shader support, render pass construction, and a text-focused graphics pipeline.
- 🚧 Phase 5 focuses on wiring those building blocks into a production text renderer and validating it end-to-end before dropping into Grim.
- 🔜 Later phases will expand into glyph atlas management, hot reload, performance profiling, and full Grim integration.

## Highlights

- **Pure Zig implementation** targeting Zig 0.16.0-dev—no external runtime dependencies.
- **Modular Vulkan wrappers** under `lib/vulkan/` covering loaders, devices, swapchains, synchronization, descriptors, buffers/images, shaders, render passes, and graphics pipelines.
- **Text rendering focus** with instanced quad layouts, alpha blending defaults, and a dedicated pipeline ready for glyph atlas sampling.
- **Frame-oriented text pipeline** with `TextRenderer.beginFrame`, `setProjection`, `queueQuad`, and `encode` built around the shared `GlyphAtlas` manager.
- **Test-first workflow**: each helper module ships with capture-based unit tests to validate Vulkan dispatch usage.

## Getting started

1. Install [Zig 0.16.0-dev](https://ziglang.org/download/).
2. Clone the repository and run the formatter and unit tests:

```bash
zig fmt src lib
zig build test
```

3. Explore the Vulkan helpers under `lib/vulkan/` and the upcoming text renderer scaffolding in `lib/vulkan/text_renderer.zig` (coming online during Phase 5).

### Workspace layout

```
lib/vulkan/        Core Vulkan helpers and abstractions
src/               (Reserved) higher-level application hooks
examples/          Planned standalone demos (e.g. text_rendering_test.zig)
docs/              Reference material and design notes
TODO.md            Long-form roadmap and implementation checklist
REFERENCE_MATERIAL.md  Vulkan + text rendering research archive
```

## Development workflow

- **Formatting:** `zig fmt src lib`
- **Unit tests:** `zig build test`
- **Module tests:** individual `test` blocks live alongside implementations for fast iteration.
- **Shaders:** placeholder GLSL sources in `shaders/` compile to SPIR-V via `glslangValidator` and are embedded at build time using `@embedFile`.

## Roadmap snapshot

| Phase | Focus | Status | Notes |
| --- | --- | --- | --- |
| 1 | Loader, types, device setup | ✅ Complete | Dynamic loading and core Vk types in place |
| 2 | Surface & swapchain | ✅ Complete | Presentation helpers ready for integration |
| 3 | Resource management | ✅ Complete | Buffers, images, memory, descriptors stabilized |
| 4 | Render pipeline building blocks | ✅ Complete | Shader, render pass, and graphics pipeline helpers prepared |
| 5 | Text renderer wiring | 🚧 In progress | Implement `text_renderer` init/render path and standalone demo |
| 6+ | Glyph atlas, performance, Grim integration | 🔜 Planned | Track details in `TODO.md` |

## Next milestone

Phase 5A focuses on scaffolding `lib/vulkan/text_renderer.zig`, embedding placeholder SPIR-V shaders, and implementing `TextRenderer.init()` using the Phase 4 helpers. Subsequent sub-phases will add command recording (`renderText`), create a standalone `examples/text_rendering_test.zig`, and finally replace Grim's stub renderer once the demo proves stable.

## Contributing

Bug reports, design feedback, and PRs are welcome. Please:

1. Keep code formatted (`zig fmt`).
2. Add or update relevant unit tests (`zig build test`).
3. Reference the roadmap (`TODO.md`) when proposing new features to ensure alignment with upcoming phases.

## License

MIT © 2025 CK Technology LLC. See [`LICENSE`](LICENSE) for details.

