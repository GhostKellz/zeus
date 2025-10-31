Design principles (so it doesn’t sprawl)


Two layers: vk-sys thin FFI + safe Basalt API (handles lifetime & error sets).


No macros, no codegen at build time beyond SPIR-V—keep Zig readable.


Allocator-first: every API takes *Allocator; offer arena for frame temps.


Hot path: persistent mapped staging ring + device-local big buffers; suballoc.


Resizes: idempotent recreateSwapchain(); never panic on VK_ERROR_OUT_OF_DATE_KHR.


Text: one bindless glyph atlas, batched per font face → one pipeline.


Validation: compile-time flags: debug_validation, trace_labels, gpu_markers.



MVP scope (6–8 weeks realistic)


Instance/device, swapchain, command submission, descriptor cache.


One graphics pipeline (glyphs), one compute (atlas build).


SDF/MSDF packing + basic HarfBuzz integration hook.


UTF-8 text draw (drawText(TextSpan[])) with baseline metrics, subpixel AA.


Resizable surface for Wayland/X11 with wlroots/SDL2 glue behind a tiny shim.



Nice extras (after MVP)


Timeline semaphores for frame pacing.


Shader hot-reload (file watcher → pipeline re-create).


Multi-queue (transfer/compute) with barriers in a micro frame-graph.


HDR/ICC tonemapping pass for crisp text on wide-gamut displays.



Version & crates


Zig 0.16-dev target; tag v0.1.0 once swapchain+text MVP lands.


Publish as basalt and glyphon (or zulkan / runetext) on your org.


If you want, I’ll sketch the public API for Basalt.init() + Glyphon.draw() next, and a tiny demo (grim_textview.zig) that renders a 10k-line buffer at 144 Hz.