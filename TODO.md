# Zeus Vulkan Library - Development Roadmap

**Status:** Phase 5 Complete � Moving to Phase 6 (Optimization & High Refresh Rate Polish)

**Target:** Production-ready Vulkan text rendering for Grim editor on NVIDIA + Wayland @ 144-360Hz

---

## Phase 1: Core Vulkan Foundations  COMPLETE

### Dynamic Loader & Type System
- [x] Dynamic library loading (`libvulkan.so`, `vulkan-1.dll`, `libvulkan.dylib`)
- [x] Function pointer tables (instance-level, device-level)
- [x] `vkGetInstanceProcAddr` / `vkGetDeviceProcAddr` dispatch
- [x] Core Vulkan types (handles, enums, flags, structs)
- [x] VkResult � Zig error mapping
- [x] Bitfield helpers with packed structs

**Deliverables:** `loader.zig`, `types.zig`, `error.zig`
**Line Count:** ~1,530 lines
**Test Coverage:**  Unit tests passing

---

## Phase 2: Instance, Device & Surface  COMPLETE

### Vulkan Device Setup
- [x] Instance creation with validation layers (debug builds)
- [x] Physical device enumeration and selection
- [x] Queue family discovery (graphics, present, transfer)
- [x] Logical device creation
- [x] Extension enumeration and enabling
- [x] Feature checking (VkPhysicalDeviceFeatures)
- [x] Debug messenger (VK_EXT_debug_utils)

### Surface & Presentation
- [x] Surface creation (Wayland, X11, Windows, macOS)
- [x] Surface format selection
- [x] Present mode selection (fifo, mailbox, immediate)
- [x] Swapchain creation (VK_KHR_swapchain)
- [x] Image acquisition / present queue submission
- [x] Swapchain recreation on resize

**Deliverables:** `instance.zig`, `device.zig`, `physical_device.zig`, `surface.zig`, `swapchain.zig`
**Line Count:** ~1,160 lines
**Test Coverage:**  Unit tests passing

---

## Phase 3: Resource Management  COMPLETE

### Memory & Buffers
- [x] Memory type selection (device-local, host-visible, etc.)
- [x] Memory pool allocator for small allocations
- [x] Buffer creation (vertex, index, uniform, staging)
- [x] Buffer memory binding
- [x] Transfer queue operations
- [x] Buffer copying and updates
- [x] Dynamic uniform buffers

### Images & Samplers
- [x] Image creation (2D textures, render targets)
- [x] Image view creation
- [x] Image layout transitions
- [x] Sampler creation (linear, nearest, anisotropic)
- [x] Format support queries
- [x] Barrier types (memory, buffer, image)
- [x] Pipeline stage/access flags

### Descriptors
- [x] Descriptor pool creation
- [x] Descriptor set layout creation
- [x] Descriptor set allocation
- [x] Descriptor writes (buffers, images)
- [x] Descriptor caching

**Deliverables:** `memory.zig`, `buffer.zig`, `image.zig`, `sampler.zig`, `descriptor.zig`
**Line Count:** ~1,850 lines
**Test Coverage:**  Unit tests passing

---

## Phase 4: Render Pipeline  COMPLETE

### Shaders & Pipeline Creation
- [x] SPIR-V shader module loading from embedded bytecode
- [x] Shader module creation
- [x] Shader stage info builders
- [x] Render pass creation
- [x] Attachment descriptions
- [x] Subpass dependencies
- [x] Framebuffer creation

### Graphics Pipeline
- [x] Pipeline layout creation
- [x] Graphics pipeline creation
- [x] Vertex input state (instanced rendering)
- [x] Input assembly state
- [x] Rasterization state
- [x] Multisample state
- [x] Blend state (alpha blending)
- [x] Dynamic state (viewport, scissor)
- [x] Pipeline cache support

### Command Buffers & Synchronization
- [x] Command pool creation (per-thread pools)
- [x] Command buffer allocation
- [x] Command buffer recording helpers
- [x] Command buffer submission
- [x] Fence creation and waiting
- [x] Semaphore creation and signaling
- [x] Pipeline barriers
- [x] Memory barriers

**Deliverables:** `shader.zig`, `render_pass.zig`, `pipeline.zig`, `commands.zig`, `sync.zig`
**Line Count:** ~1,280 lines
**Test Coverage:**  Unit tests passing

---

## Phase 5: Text Renderer Integration  COMPLETE

### Glyph Atlas Management
- [x] Dynamic atlas texture (growable)
- [x] Glyph rectangle packing algorithm
- [x] Atlas texture upload to GPU
- [x] Overflow guards and growth callbacks
- [x] R8_UNORM format support (grayscale alpha)
- [x] Padding support for glyph isolation

### Text Rendering Pipeline
- [x] `TextRenderer` struct with full lifecycle
- [x] Instanced quad rendering
- [x] Per-glyph vertex generation
- [x] Uniform buffer for projection matrix
- [x] Alpha blending for antialiasing
- [x] Frame API (`beginFrame`, `queueQuad`, `encode`, `endFrame`)
- [x] Dynamic viewport/scissor management
- [x] Per-frame CPU storage with safe uploads
- [x] Pipeline/descriptor binding automation

### Shaders
- [x] Vertex shader (`shaders/text.vert`)
  - Quad vertex generation from instance data
  - Screen-space transformation
  - UV coordinate calculation
- [x] Fragment shader (`shaders/text.frag`)
  - Atlas texture sampling
  - Alpha blending
  - Color modulation
- [x] SPIR-V compilation and embedding (`@embedFile`)

**Deliverables:** `text_renderer.zig`, `glyph_atlas.zig`, `shaders/text.{vert,frag}.spv`
**Line Count:** ~998 lines (text_renderer + glyph_atlas)
**Test Coverage:**  End-to-end frame API test passing

**Current Total:** ~6,818 lines across 22 modules

---

## Phase 6: High Refresh Rate Optimization =� NEXT

### Current Sprint Focus (Nov 2025)
- [x] Instanced rendering batch size tuning → instrument glyph/draw ratios and auto-tune per-frame batch limits (`TextRenderer.updateAutoBatching`, profiler HUD glyph ratios ✅ Nov 2025)
- [x] Atlas upload pipeline barrier audit → collapse redundant barriers and tighten stage/access masks (`GlyphAtlas.recordUploads` single transition ✅ Nov 2025)
- [x] Transfer queue async path → stage atlas uploads on dedicated queue gated by timeline semaphores (`TransferQueueOptions` + timeline waits ✅ Nov 2025)
- [x] Frame pacing telemetry → record encode/submit durations and surface stats via CLI/debug overlay (`FrameTelemetry.submit_cpu_ns`, HUD submit metrics ✅ Nov 2025)

### Target Performance Metrics
- **144Hz @ 1440p** - 6.9ms frame budget (minimum viable)
- **240Hz @ 1440p** - 4.16ms frame budget (target)
- **270Hz @ 1440p** - 3.7ms frame budget (stretch goal)
- **360Hz @ 1440p** - 2.77ms frame budget (competitive gaming)
- **240Hz @ 4K** - 4.16ms frame budget (future hardware)

### Frame Pacing & VSync Control
- [x] Frame time tracking and telemetry
- [x] Adaptive VSync (VK_PRESENT_MODE_FIFO_RELAXED_KHR)
- [x] Mailbox mode for triple buffering (VK_PRESENT_MODE_MAILBOX_KHR)
- [x] Immediate mode for latency-sensitive scenarios
- [x] Frame rate limiter (cap at 144/240/270/360 Hz)
- [x] Present timing extension (VK_GOOGLE_display_timing)
- [x] Wayland presentation time feedback

### GPU Optimization
- [x] Command buffer pre-recording and reuse
- [x] Descriptor set caching (avoid redundant updates)
- [x] Push constants for per-draw data (vs uniform buffers)
  - Projection now pushed per draw; update `TextRenderer` docs/tests to reflect push-constant APIs (✅ Oct 2025)
- [x] Instanced rendering batch size tuning **(current focus)**
  - [x] Instrument per-frame draw count vs glyph count; target ≤1 draw/512 glyphs while holding atlas residency (`ProfilerSummary.glyphs_per_draw`, FrameTelemetry ratios ✅ Nov 2025)
  - [x] Auto-adjust batch size based on `max_instances` and swapchain extent to avoid overflow (`TextRenderer.updateAutoBatching` feedback loop ✅ Nov 2025)
- [x] Pipeline barrier optimization (minimize stalls) **(current focus)**
  - [x] Audit current atlas upload barriers; collapse into single image barrier per frame where possible (verified single `ensureLayout` invocation ✅ Nov 2025)
  - [x] Replace full pipeline sync with stage-specific flags (`TRANSFER`→`FRAGMENT`) (already using scoped stage/access masks ✅ Nov 2025)
- [x] Transfer queue utilization (background atlas uploads) **(current focus)**
  - [x] Optional transfer queue submission path for atlas uploads (synchronous baseline)
  - [x] Prototype staging copies on transfer queue with timeline semaphores gating graphics usage (`TransferSubmission` timeline wiring exercised in tests ✅ Nov 2025)
  - [x] Defer atlas transitions until just before draw during encode step (graphics path only transitions when uploads pending ✅ Nov 2025)
- [ ] NVIDIA-specific optimizations (see `REFERENCE_MATERIAL.md` §1)
  - [x] ReBAR detection for large host-visible allocations (RTX 4090 optimization)
    - [x] `physical_device.Selection.hasReBAR()` helper with >256MB host-visible device-local threshold
    - [x] Scoped memory logs highlighting ReBAR vs staging strategies during allocations
  - Memory allocation flags (device-local + host-visible preferred)
  - [x] Pipeline cache warming (precompile + serialize cache blobs after first run) (`pipeline_cache.PipelineCache.persist` + renderer test ✅ Nov 2025)
  - Async compute queue usage (if beneficial)
  - [x] DRM modesetting validation for 144-360Hz displays (`system_validation.logDrmHighRefresh` logging ✅ Nov 2025)

### CPU Optimization
- [ ] Parallel command buffer recording (multi-threaded)
- [ ] Lock-free frame data structures
- [x] SIMD glyph quad batching (see `REFERENCE_MATERIAL.md` §3.2)
  - [x] AVX2-accelerated slice uploads via `TextRenderer.queueQuads`
  - [x] Batch submission API for precomputed glyph quads
  - [ ] Additional SoA layout exploration for further cache wins
- [ ] Cache-friendly memory layout (SoA vs AoS)
  - Profile `TextRenderer.queueQuads` cache misses with perf; experiment with AoS→SoA conversion tables
- [ ] Zero-copy glyph data paths
  - Investigate mapping atlas staging buffers directly into FreeType raster output to avoid memcpy
- [ ] Reduced allocations in hot paths
  - Pool `TextQuad` scratch buffers per frame; benchmark allocator pressure pre/post

### Code Quality & Validation
- [x] Verify SPIR-V 4-byte alignment (see `REFERENCE_MATERIAL.md` §2.2)
  - [x] Ensure `@embedFile` shader bytecode is properly aligned
  - [x] Compile-time assertions guarding shader slices in `text_renderer.zig`
  - [x] Alignment regression test in `shader.zig`
- [x] Kernel parameter validation (`system_validation.validateKernelParameters` + boot log wiring ✅ Nov 2025)
  - [x] Confirm `vm.max_map_count=16777216` for descriptor sets
  - [x] Verify BORE scheduler active (`kernel.sched_bore=1`)
  - [x] Check ReBAR enabled in BIOS/UEFI (for RTX 4090 optimal performance)
- [x] Frame pacing telemetry **(current focus)**
  - [x] Add lightweight profiler to record frame encode + submit time histograms during tests (`ProfilerSummary.submit_hist`, encode/transfer histograms ✅ Nov 2025)
  - [x] Surface stats via CLI or debug HUD to validate 144/240/360 Hz budgets (`ProfilerHud.writeLine` encode/submit metrics ✅ Nov 2025)
  - [x] Expose `TextRenderer` frame stats callback with glyph batching/upload flush counters

**Deliverables:** `frame_pacing.zig`, `profiling.zig`, `threading.zig`, SIMD optimizations
**Target Line Count:** ~800 lines (added SIMD + validation)
**Test Coverage:** Benchmark suite + frame time histograms + SIMD unit tests

---

## Reference Material Insights (Cross-Phase)

**Source:** `REFERENCE_MATERIAL.md` - Comprehensive analysis of archived repositories

### Key Takeaways for Zeus Development

#### 1. NVIDIA Open GPU Kernel Modules (v580) - §1
- ✅ **UVM Memory Strategy** - Zeus already uses optimal DEVICE_LOCAL + HOST_VISIBLE (ReBAR)
- ✅ **Phase 6**: ReBAR detection for large host-visible allocations
- ✅ **Phase 6**: DRM modesetting validation for 144-360Hz displays
- 🚀 **Post-MVP**: Multi-GPU peer memory for dual-monitor setups

#### 2. Vulkan-zig Binding Patterns - §2
- ✅ **Dispatch Tables** - Zeus already uses three-tier loading pattern
- ✅ **Phase 6**: Verified SPIR-V 4-byte alignment (`@embedFile` shader bytecode)
- ✅ **Error Handling** - Zeus uses minimal error set (focused API surface)

#### 3. Linux Kernel Optimizations - §3
- ✅ **BORE Scheduler** - Already leveraged via linux-tkg-bore 6.17.4 kernel
  - Perfect for text rendering (bursty I/O workload: input → render → VSync)
  - Prioritizes tasks with low CPU burst scores (interactive tasks)
- 🔜 **Phase 6**: AVX2 SIMD glyph batching (x86-64-v4 on Ryzen 9 7950X3D)
  - **8x throughput**: 8 glyphs/iteration vs 1 glyph/iteration
  - **~435μs savings/frame** @ 240Hz (10.4% of 4.16ms budget)
- ✅ **Kernel Parameters** - `vm.max_map_count=16777216` for descriptor sets

#### 4. AMD GPU Support Strategy - §4
- 🔜 **Phase 7**: RADV-specific memory paths (separate staging vs NVIDIA ReBAR)
- 🚀 **Post-MVP**: Test on AMD RX 7900 XTX for validation

#### 5. Future Research Areas - §5
- 🚀 **Vulkan 1.4**: maintenance7 (descriptor overhead reduction)
- 🚀 **GPU Rasterization**: Compute shader glyph rendering (Slug/Pathfinder)
- 🚀 **HDR Support**: VK_EXT_swapchain_colorspace, 10-bit color

**Cross-References:**
- Each TODO item above links to specific sections in `REFERENCE_MATERIAL.md`
- Use `§N` notation to jump to relevant analysis (e.g., `§3.2` = SIMD optimizations)

---

## Phase 7: Production Polish & Validation = PLANNED

### Robustness & Error Handling
- [x] Comprehensive validation layer integration
- [x] Debug naming for all Vulkan objects (VK_EXT_debug_utils)
- [x] Graceful degradation (missing extensions/features)
- [x] Out-of-memory handling strategies
- [x] Swapchain recreation on window resize
- [x] Device lost recovery (NVIDIA driver crashes)
- [x] Wayland compositor compatibility testing

### Memory Management
- [x] Memory pool statistics and reporting
- [x] GPU memory budget tracking (VK_EXT_memory_budget)
- [x] Leak detection in debug builds
- [x] Defragmentation hints
- [x] Staging buffer recycling
- [x] Atlas eviction policies (LRU)
- [x] AMD GPU memory optimization (see `REFERENCE_MATERIAL.md` §4)
  - RADV-specific staging buffer paths (AMD prefers separate staging vs NVIDIA ReBAR)
  - Memory type selection fallback for non-ReBAR systems
  - Test on AMD RX 7900 XTX for validation

### Quality of Life
- [x] Hot shader reload (development mode)
- [x] Pipeline statistics queries
- [x] GPU timestamp profiling
- [x] Render graph visualization
- [x] Performance overlay (FPS, frame time, GPU memory)
- [x] Debug UI for atlas inspection

### Documentation
- [x] API reference docs (Zig docgen)
- [x] Architecture decision records (ADRs)
- [x] Performance tuning guide
- [x] Integration guide for Grim
- [x] Wayland compositor compatibility matrix
- [x] NVIDIA driver version testing

**Deliverables:** `docs/`, validation suite, profiling tools
**Target Line Count:** ~800 lines + documentation
**Test Coverage:** Stress tests, memory leak tests, multi-monitor tests

---

## Phase 8: Library Release & Grim Readiness <� GOAL

**Note:** Grim-side integration work is documented in `/data/projects/grim/zeus_integration.md`

### Library Module Export
- [ ] Finalize `build.zig` for library module export
  - Export `zeus` module with proper root source file
  - Embed SPIR-V shaders as anonymous imports
  - Document module dependencies (pure Zig, no libc)
- [ ] Create `build.zig.zon` package metadata
  - Semantic versioning (v1.0.0 for stable release)
  - Minimum Zig version requirement (0.16.0-dev)
  - Package description and license
- [ ] Tag stable release
  - v0.1.0-alpha (Phase 6 complete)
  - v0.2.0-beta (Phase 7 complete)
  - v1.0.0 (Phase 8 complete, production ready)

### API Stability & Documentation
- [ ] API reference documentation (`docs/API.md`)
  - All public types, functions, error codes
  - Example usage patterns for common scenarios
  - Migration guide from stub implementations
- [ ] Performance guarantees documentation
  - Frame time targets (144-360Hz)
  - Memory usage benchmarks
  - Glyph throughput specifications
- [x] Breaking changes policy (`docs/BREAKING_CHANGES.md` SemVer commitments ✅ Nov 2025)
  - Semantic versioning commitment
  - Backward compatibility rules

### Integration Testing for Grim Use Case
- [ ] Grim rendering pattern test (10K+ glyphs/frame)
- [ ] Atlas upload pattern test (FreeType simulation)
- [ ] Resize handling test (swapchain recreation)
- [ ] Multi-frame stress test (1000+ frames)
- [ ] Memory leak validation (valgrind, Zig leak detector)
- [ ] Performance regression tests
  - Frame time histograms
  - GPU memory usage tracking

### Platform Validation
- [ ] Linux + Wayland + NVIDIA (primary target)
  - Hyprland compositor validation
  - KDE Plasma Wayland Session validation
  - 144/240/270/360Hz display modes
  - RTX 3000/4000 series compatibility
- [ ] Linux + X11 + NVIDIA (fallback)
- [ ] AMD GPU validation (RADV driver)
  - RX 6000/7000 series testing
  - RADV-specific memory paths

### Release Preparation
- [ ] CI/CD via local scripts for automated testing leveraging my system rtx 4090 + nvidia Open 580 driver
- [ ] Release notes template
- [ ] Version tagging workflow
- [ ] Package hash generation for Zig package manager

**Deliverables:** Zeus v1.0.0 library ready for Grim consumption
**Test Coverage:** Integration tests simulating Grim's rendering patterns
**Documentation:** `GRIM.md` (Zeus responsibilities), API reference, migration guide

---

## Post-MVP: Advanced Features =� FUTURE

### Text Rendering Enhancements
- [ ] Signed distance field (SDF) fonts
- [ ] MSDF (multi-channel SDF) support
- [ ] Color emoji support (CBDT/COLR tables)
- [ ] Font hinting and grid fitting
- [ ] Ligature support
- [ ] Variable font support
- [ ] GPU-accelerated glyph rasterization (see `REFERENCE_MATERIAL.md` §5.2)
  - Compute shader rasterization (Slug/Pathfinder approach)
  - Dynamic font size support without CPU rasterization

### Effects & Styling
- [ ] Underline/strikethrough rendering
- [ ] Background color spans
- [ ] Wavy underlines (spell check)
- [ ] Text shadows
- [ ] Glow effects for selection

### Multi-Monitor & HDR
- [ ] Per-monitor DPI scaling
- [ ] HDR color space support (see `REFERENCE_MATERIAL.md` §5.3)
  - VK_EXT_swapchain_colorspace for HDR10
  - VK_FORMAT_A2B10G10R10_UNORM_PACK32 swapchain format
  - Wide gamut color rendering (Display P3 / Rec.2020)
- [ ] Multi-GPU support (see `REFERENCE_MATERIAL.md` §1.3)
  - VK_KHR_device_group for dual-GPU rendering
  - NVIDIA peer memory for zero-copy multi-monitor

### Platform Expansion
- [ ] Windows Direct3D 12 backend (alternative to Vulkan)
- [ ] macOS Metal backend (MoltenVK alternative)
- [ ] Linux vulkan and vkd3d-proton support
- [ ] Android support (Low priority)
### Future Vulkan Features
- [ ] Vulkan 1.4 adoption (see `REFERENCE_MATERIAL.md` §5.1)
  - VK_KHR_maintenance7 (reduced CPU overhead for descriptors)
  - VK_KHR_dynamic_rendering_local_read (tile-based GPU optimization)

---

## Performance Targets Summary

| Resolution | Refresh Rate | Frame Budget | Status | Notes |
|------------|--------------|--------------|--------|-------|
| 1080p      | 144 Hz       | 6.9ms        |  Ready | Minimum viable |
| 1440p      | 144 Hz       | 6.9ms        |  Ready | Primary target |
| 1440p      | 240 Hz       | 4.16ms       | =� Phase 6 | Requires optimization |
| 1440p      | 270 Hz       | 3.7ms        | = Phase 6 | Stretch goal |
| 1080p      | 360 Hz       | 2.77ms       | = Phase 7 | Competitive gaming |
| 4K (2160p) | 144 Hz       | 6.9ms        | = Phase 7 | Future hardware |
| 4K (2160p) | 240 Hz       | 4.16ms       | =� Future | Bleeding edge |

**Hardware Baseline:**
- **Minimum:** NVIDIA RTX 3060 Ti + Ryzen 5 5600X
- **Recommended:** NVIDIA RTX 4070 + Ryzen 9 7950X3D
- **Optimal:** NVIDIA RTX 4090 + Ryzen 9 7950X3D (current test system)

---

## Testing Matrix

### Supported Platforms
- [x] Arch Linux + Wayland (Hyprland/Sway) - **Primary**
- [ ] Arch Linux + X11 - **Secondary**
- [ ] Ubuntu 24.04 + Wayland
- [ ] Fedora 40 + Wayland
- [ ] Windows 11 (Vulkan via native driver)
- [ ] macOS (Vulkan via MoltenVK) - **Low priority**

### GPU Compatibility
- [x] NVIDIA RTX 4090 - **Primary test hardware**
- [ ] NVIDIA RTX 4070 Ti
- [ ] NVIDIA RTX 3080
- [ ] AMD RX 7900 XTX - **Important for open-source drivers**
- [ ] AMD RX 6800 XT
- [ ] Intel Arc A770 - **Future consideration**

### Wayland Compositors
- [x] Hyprland 
- [ ] Sway
- [ ] KDE Plasma Wayland **Primary (dev workstation setup)**
- [ ] GNOME Shell Wayland
- [ ] River
- [ ] Wayfire

---

## Development Metrics

**Current Status:**
- **Total Lines:** 6,818 lines (22 modules)
- **Test Coverage:** 100% of implemented phases
- **Compilation:** Zig 0.16.0-dev (master branch)
- **Build Time:** < 5 seconds (incremental)
- **Test Time:** < 2 seconds

**Phase 6 Targets:**
- **Add:** ~600 lines (frame pacing, profiling, threading)
- **Test Coverage:** Benchmark suite with frame time histograms
- **Performance:** 240Hz @ 1440p stable

**Phase 7 Targets:**
- **Add:** ~800 lines + extensive documentation
- **Test Coverage:** Stress tests, leak detection, multi-monitor
- **Validation:** 100% Vulkan validation layers clean

**Phase 8 Targets:**
- **Integrate:** Replace 837 stub lines in Grim
- **Performance:** Input latency < 1 frame, 144Hz minimum
- **Quality:** Production-ready text rendering

---

## References

### Specifications & Official Documentation
- **Vulkan Spec:** https://www.khronos.org/registry/vulkan/specs/1.3/html/
- **Zig Language:** https://ziglang.org/documentation/master/

### Archived Reference Repositories
- **NVIDIA Open GPU Kernel Modules (v580):** `archive/open-gpu-kernel-modules/`
  - UVM memory allocation, DRM modesetting, peer memory access
- **vulkan-zig (Zig 0.13-0.15):** `archive/vulkan-zig/`
  - Dispatch tables, error handling, SPIR-V alignment
- **Linux TKG (Custom Kernel):** `archive/linux-tkg/`
  - BORE/EEVDF/BMQ schedulers, memory tweaks, I/O optimizations
- **BORE Scheduler:** `archive/bore-scheduler/`
  - Burst-oriented task prioritization for interactive workloads
- **CachyOS Kernel:** `archive/linux-cachyos/`
  - x86-64-v3/v4 optimizations (AVX2/AVX-512), NVIDIA compatibility

### Related Projects
- **Grim Editor:** `/data/projects/grim/` (integration target)
- **Ghostshell Terminal:** `/data/projects/ghostshell/` (sibling project using Zeus)
- **wzl (Wayland):** `/data/projects/wzl/` (Wayland compositor framework)
- **Phantom (TUI):** `/data/projects/phantom/` (TUI framework)

### Documentation
- **Reference Material Analysis:** `REFERENCE_MATERIAL.md` (insights from archived repos)
- **Architecture Decisions:** `docs/ARCHITECTURE.md`
- **Performance Guide:** `docs/PERFORMANCE.md`
- **Integration Guide:** `docs/INTEGRATION.md`
- **Grim Integration Requirements:** `GRIM.md` (Zeus's responsibilities for Grim)
- **Grim Knowledge Base:** `GRIM_KB.md` (original integration notes)

---

**Last Updated:** 2025-10-31 (Added GRIM.md, refactored Phase 8 to Zeus-only scope)
**Next Milestone:** Phase 6 - High Refresh Rate Optimization (frame pacing, command reuse; AVX2 + ReBAR + SPIR-V alignment ✅)
**Owner:** CK Technology LLC
**License:** MIT
