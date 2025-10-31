# Grim Knowledge Base for Zeus

## What is Grim?

**Grim** - Lightweight Vim-like editor/IDE built in Zig 0.16.0-dev
- **Repository:** https://github.com/ghostkellz/grim 
- **Location:** (read only references) /data/projects/grim

ghostshell reference (if needed)
/data/projects/ghostshell
https://github.com/ghostkellz/ghostshell 
=

wayland zig 
/data/projects/wzl 
https://github.com/ghostkellz/wzl
## Core Architecture

### Text Rendering Stack
Grim uses **Phantom** (wzl + flare + gcode) for rendering:
- **wzl** - Wayland compositor framework
- **flare** - OpenGL/Vulkan renderer abstraction
- **gcode** - Unicode text shaping library
- **Phantom** - TUI framework combining all three

Currently has **STUB** Vulkan renderer at:
- `ui-tui/vulkan_renderer.zig` (495 lines - all stubs)
- `ui-tui/vulkan_integration.zig` (342 lines - stub types)

**THIS IS WHERE ZEUS COMES IN** - Replace stubs with real Vulkan implementation.

### Text Editor Core
- **Rope data structure** - Efficient large file handling
- **Modal editing** - Vim keybindings (normal/insert/visual/command)
- **Tree-sitter** - Syntax highlighting (14 languages via Grove)
- **LSP client** - Language server protocol support
- **Ghostlang plugins** - Typed plugin system (alternative to Lua)

### Key Dependencies
```zig
// From build.zig.zon
.phantom      // TUI framework (wzl + flare + gcode)
.wzl          // Wayland compositor
.gcode        // Unicode shaping
.flare        // Renderer abstraction
.zsync        // Async I/O runtime
.ghostlang    // Plugin language
.zigzag       // Zigzag allocator
```

## Rendering Flow (Current State)

```
GrimApp (ui-tui/grim_app.zig)
  └─> LayoutManager (ui-tui/layout_manager.zig)
      └─> GrimEditorWidget (ui-tui/grim_editor_widget.zig)
          └─> Editor (ui-tui/editor.zig)
              └─> Rope (core/rope.zig)

Phantom Event Loop
  └─> grimEventHandler()
      └─> GrimApp.handleEvent()
          └─> render()
              └─> VulkanRenderer (STUB!)
```

## What Grim Needs from Zeus

### 1. Glyph Atlas Rendering
- Rasterize glyphs to GPU texture atlas
- Handle dynamic atlas growth
- LRU cache for glyph eviction
- Subpixel antialiasing (RGB LCD)

### 2. Instanced Quad Rendering
- Batch thousands of glyphs per frame
- Per-instance data: position, UV, color
- Minimal draw calls (1-2 per frame)

### 3. Integration Points
```zig
// Zeus should provide:
pub const TextRenderer = struct {
    pub fn init(allocator, surface, width, height) !*TextRenderer;
    pub fn uploadGlyphs(atlas_data: []u8) !void;
    pub fn renderText(quads: []TextQuad) !void;
    pub fn present() !void;
    pub fn resize(width, height) !void;
};

pub const TextQuad = struct {
    screen_pos: [2]f32,
    glyph_size: [2]f32,
    atlas_uv: [4]f32,  // x, y, w, h
    color: [4]f32,
};
```

### 4. Performance Requirements
- **144Hz target** - 6.9ms frame budget
- **<100MB GPU memory** - For 10K line files
- **<1 frame latency** - Input to pixels
- **Smooth scrolling** - 60fps minimum

## Ghostshell Connection

**Ghostshell** - Terminal emulator (Ghostty fork)
- **Repository:** https://github.com/ghostkellz/ghostshell
- **Location:** /data/projects/ghostshell
- **Rendering:** Also uses Phantom (wzl + flare + gcode)

**Shared rendering needs:**
- Both need GPU-accelerated text rendering
- Both use glyph atlas + instanced quads
- Both target 144Hz on NVIDIA
- Advanced target - 240hz & 360hz support on NVIDIA so we'll want a maximum 360hz performance path for high end OLED 1440p + 360hz support and 240 hz. Also 4k 240hz support on high end Nvidia GPU's.
-Support for both AMD & Nvidia graphics but Nvidia is precendence 
- Excellent Arch Linux Support since grim and other apps are built for linux, mainly arch.
- Expand to Windows and macOS
- Nvidia open Kernel module Nvidia open driver (the open source one not noveau driver) is preferred 580+ 

**Zeus can serve both projects!**

## Technical Specs

### Grim Text Rendering Requirements

**Glyph Atlas:**
- Format: R8 (grayscale alpha)
- Size: Start 1024x1024, grow to 4096x4096
- Packing: Rectangle packing algorithm
- Upload: Staging buffer to GPU

**Text Shaders:**
```glsl
// Vertex: Transform quad corners to screen space
// Fragment: Sample atlas texture, apply color

layout(set = 0, binding = 0) uniform Uniforms {
    mat4 projection;
    vec2 viewport_size;
};
layout(set = 0, binding = 1) uniform sampler2D atlas;
```

**Vertex Data:**
- 6 vertices per glyph (2 triangles)
- OR 4 vertices + index buffer
- Instanced rendering preferred

### Current File Structure

```
grim/
├── core/
│   ├── rope.zig              # Text buffer
│   ├── session.zig           # Workspace state
│   ├── snippets.zig          # Code snippets
│   └── ...
├── ui-tui/
│   ├── grim_app.zig          # Main app
│   ├── editor.zig            # Editor logic
│   ├── vulkan_renderer.zig   # STUB - Replace with Zeus
│   └── vulkan_integration.zig # STUB - Replace with Zeus
├── lsp/                      # LSP client
├── runtime/                  # Plugin runtime
└── syntax/                   # Tree-sitter
```

## Integration Steps for Zeus

### Phase 1: Basic Rendering (Week 1)
1. Create Zeus text renderer module
2. Initialize Vulkan from Phantom surface
3. Create glyph atlas texture
4. Render single glyph

### Phase 2: Instanced Rendering (Week 2)
1. Instanced quad rendering
2. Batch multiple glyphs
3. Proper blending and antialiasing

### Phase 3: Grim Integration (Week 3)
1. Replace `ui-tui/vulkan_renderer.zig` with Zeus
2. Hook up to GrimEditorWidget
3. Handle resize/vsync

### Phase 4: Polish (Week 4)
1. Performance tuning
2. Memory optimization
3. Error handling

## Key Contacts & Links

- **Grim Repo:** https://github.com/ghostkellz/grim
- **Ghostshell Repo:** https://github.com/ghostkellz/ghostshell
- **Phantom (TUI):** Uses wzl + flare + gcode
- **Author:** Christopher Kelley <ckelley@ghostkellz.sh>

## Notes for Zeus Implementation

1. **Surface from Phantom** - Zeus gets VkSurfaceKHR from Phantom/wzl
2. **No window creation** - Phantom handles that
3. **Coordinate system** - Top-left origin, Y-down
4. **Resize events** - Phantom sends resize → Zeus recreates swapchain
5. **VSync control** - Phantom provides preferred present mode

## Quick Reference

**Zeus replaces:**
- `ui-tui/vulkan_renderer.zig` (495 lines of stubs)
- `ui-tui/vulkan_integration.zig` (342 lines of stubs)

**Zeus provides:**
- Real Vulkan instance/device/swapchain
- Glyph atlas texture management
- Instanced text rendering pipeline
- 144Hz GPU-accelerated rendering

**Goal:** Make Grim the fastest Vim-like editor on the planet.
