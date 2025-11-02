# Zeus Vulkan Library – Phase 9–18 Roadmap

**Status:** Phase 8 Complete ✅ | Wayland compositor compatibility shipped | Focus: Integration & release readiness

**Reference Stack:** `PHASE8_SUMMARY.md`, `docs/WAYLAND_COMPOSITOR_COMPATIBILITY.md`, `REFERENCE_MATERIAL.md`

---

## Phase 9 · Integration Test Gauntlet (⚙️ Active)

### Objectives
- Simulate Grim’s production workloads under Zig 0.16.
- Establish reproducible long-run stability and memory safety checks.
- Capture frame pacing and glyph throughput metrics under stress.

### Tasks
- [ ] Stand up `tests/integration/` harness with deterministic repro seeds.
- [ ] Author `grim_rendering_pattern_test.zig` (10k glyph burst + atlas churn).
- [ ] Add swapchain resize & recreation regression (`swapchain_recreation_test.zig`).
- [ ] Integrate leak detector + valgrind hooks for 1k-frame burn-in.
- [ ] Produce `docs/testing/integration.md` with run/triage instructions.

### Deliverables
- Integration test suite, CLI entry (`zig build integration-test`).
- Metrics export JSON for later perf diffing.

---

## Phase 10 · Grim Embedding & API Hardening (🚀 Next Up)

### Objectives
- Finalize the public Zig API consumed by Grim.
- Provide ergonomic helpers and migration docs from the Grim prototype bindings.
- Validate compositor quirks flow inside Grim’s render loop.

### Tasks
- [ ] Publish `docs/API.md` covering public structs, error sets, and lifecycles.
- [ ] Ship `examples/grim_embed.zig` showing full init → frame → teardown.
- [ ] Harden error propagation (`errors.ensureSuccess` → dedicated error unions).
- [ ] Lock down allocator & threading contracts (documented + tested).
- [ ] Align compositor quirks plumbing with Grim configuration pipeline.

### Deliverables
- Public header docs, sample embedding project, Grim integration checklist.

---

## Phase 11 · Toolchain & Zig 0.16 Stabilization (🛠️ In Planning)

### Objectives
- Eliminate remaining deprecated std APIs (`std.mem.fill`, `std.meta.errorSetUnion`, etc.).
- Update loader + error surfaces for Zig 0.16 switch semantics.
- Ensure build/test runs on nightly + forthcoming stable 0.16 release.

### Tasks
- [ ] Replace legacy mem helpers with 0.16 equivalents (`std.mem.zeroes`, custom fillers).
- [ ] Refactor loader error handling to new `switch` + `error{}` idioms.
- [ ] Audit pointer qualifiers (`*`, `?*`, `[*]`) across Vulkan stubs.
- [ ] Update `build.zig` to enforce Zig ≥ 0.16.0-dev.200.
- [ ] Refresh CI scripts / local tooling to pin compiler hash.

### Deliverables
- "Green" `zig test` across modules, compatibility note in `README.md`.

---

## Phase 12 · Performance Regression Harness (📊 Planned)

### Objectives
- Track encode/submit timing deltas across versions and hardware.
- Automate perf budgeting for 144/240/360 Hz targets.
- Surface regressions early via dashboards.

### Tasks
- [ ] Build `tools/perf-runner.zig` with JSON + CSV outputs.
- [ ] Record baseline metrics (RTX 4090, KDE Plasma 360 Hz).
- [ ] Add tolerance thresholds + alerting diff script.
- [ ] Integrate perf run into nightly cron (manual for now, CI later).
- [ ] Document workflow in `docs/performance.md` (link to Profiling § in reference material).

### Deliverables
- Baseline perf dataset, automation scripts, documentation.

---

## Phase 13 · Telemetry & Observability 2.0 (🔍 Planned)

### Objectives
- Expand runtime telemetry for encode/submit, queue depth, atlas health.
- Provide optional HUD + CLI exporters for Grim developers.

### Tasks
- [ ] Extend `frame_pacing.FramePacer` with adaptive smoothing + histograms.
- [ ] Emit structured telemetry via `std.log.ScopedJSON` or similar.
- [ ] Build lightweight HUD overlay (toggle via API) for glyph throughput insights.
- [ ] Add exporter hooks (e.g., write to Prometheus/OpenMetrics file).
- [ ] Update `docs/telemetry.md` with usage + integration recipes.

### Deliverables
- Telemetry API, HUD module, documentation + sample outputs.

---

## Phase 14 · Platform Certification & QA Matrix (🌍 Planned)

### Objectives
- Certify Zeus on additional GPU/OS stacks beyond NVIDIA + Wayland.
- Document quirks and fallback strategies per platform.

### Tasks
- [ ] Validate RADV (RX 7900 XTX) + Linux/Wayland (apply §4 guidance from Reference Material).
- [ ] Exercise NVIDIA + X11 fallback path (mailbox/immediate modes).
- [ ] Smoke test Windows + DXGI surface creation (optional stretch).
- [ ] Expand `docs/WAYLAND_COMPOSITOR_COMPATIBILITY.md` → `docs/PLATFORM_MATRIX.md`.
- [ ] Capture GPU/driver metadata in validation logs.

### Deliverables
- Platform certification matrix, archived perf traces, updated validation toolkit.

---

## Phase 15 · Release Engineering & Distribution (📦 Planned)

### Objectives
- Automate build/test/release for tags (v0.8.0-alpha → v1.0.0).
- Produce reproducible package artifacts for Zig package manager + Grim.

### Tasks
- [ ] Script release pipeline (`tools/release.zig` or shell) including fingerprinting.
- [ ] Define changelog template and release notes workflow.
- [ ] Add artifact signing / checksum generation.
- [ ] Wire optional CI hooks (GitHub Actions or local runner) for build/test.
- [ ] Document release process in `docs/releasing.md`.

### Deliverables
- Automated release scripts, documented checklist, signed artifacts rationale.

---

## Phase 16 · Developer Experience & Documentation (📚 Planned)

### Objectives
- Provide first-class docs, tutorials, and DX tooling for contributors.
- Reduce onboarding friction for new integrators.

### Tasks
- [ ] Flesh out module-level documentation comments (`///`) across public APIs.
- [ ] Generate HTML docs via `zig build docs` (ensure site-ready styling).
- [ ] Produce quickstart guide + FAQ in `docs/` (link back to Reference Material sections).
- [ ] Introduce linting/format hooks (`zig fmt`, spell check, lint scripts).
- [ ] Curate example gallery (Wayland demo, headless benchmark, debug HUD showcase).

### Deliverables
- Comprehensive docs site, sample apps, contributor guide.

---

## Phase 17 · Advanced Text Features (🖋️ Future)

### Objectives
- Push rendering quality via SDF/MSDF pipelines and color font support.
- Maintain performance targets while expanding typography options.

### Tasks
- [ ] Prototype MSDF glyph baking pipeline (reference §5 Research in Reference Material).
- [ ] Explore compute-based distance field generation for animated glyphs.
- [ ] Add color font (CBDT/COLR) handling to atlas + shaders.
- [ ] Benchmark visual quality vs performance trade-offs.
- [ ] Document integration guidance + fallback strategies.

### Deliverables
- Experimental renderer branches, comparative benchmarks, design notes.

---

## Phase 18 · Rendering R&D & Ecosystem (🔮 Future)

### Objectives
- Investigate forward-looking capabilities to keep Zeus competitive.
- Foster ecosystem integrations and tooling.

### Tasks
- [ ] Evaluate compute-driven glyph rasterization (Pathfinder-style) for future pipeline.
- [ ] Research HDR + wide color (VK_EXT_swapchain_colorspace) feasibility.
- [ ] Prototype multi-GPU / device-group support for dual-display setups.
- [ ] Collaborate with Grim team on plugin hooks + telemetry ingestion.
- [ ] Maintain archive of findings in `docs/research/` with decision logs.

### Deliverables
- R&D reports, prototype branches, partnership notes.

---

## Progress Tracking
- Phase 9 is the current focus; revisit roadmap monthly post-integration runs.
- Keep `PHASE8_SUMMARY.md` as historical log; update summaries when phases close.
- Use this document as the single source of truth for planning conversations.
