# Grim Integration Guide

**How to replace Grim's stub Vulkan renderer with Zeus**

---

## Overview

This guide covers Phase 8: Integrating Zeus into the [Grim](https://github.com/ghostkellz/grim) text editor to replace the stub Vulkan renderer with real GPU-accelerated text rendering.

**Files to Replace:**
- `ui-tui/vulkan_renderer.zig` (495 lines of stubs)
- `ui-tui/vulkan_integration.zig` (342 lines of stubs)

**Total Reduction:** 837 stub lines → Zeus library import

---

## Prerequisites

- Zeus Phase 5 complete (TextRenderer + GlyphAtlas working)
- Grim builds successfully on your system
- Phantom TUI framework functional (wzl + flare + gcode)

---

## Step 1: Add Zeus as Dependency

### Update `build.zig.zon`

```zig
.{
    .name = "grim",
    .version = "0.1.0",
    .dependencies = .{
        // ... existing dependencies ...

        .zeus = .{
            .path = "../zeus",  // Local path during development
            // OR remote once published:
            // .url = "https://github.com/ghostkellz/zeus/archive/v0.1.0.tar.gz",
            // .hash = "...",
        },
    },
}
```

### Update `build.zig`

```zig
const exe = b.addExecutable(.{
    .name = "grim",
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
});

// Add Zeus module
const zeus = b.dependency("zeus", .{
    .target = target,
    .optimize = optimize,
}).module("zeus");

exe.root_module.addImport("zeus", zeus);

// Link Vulkan (required by Zeus)
exe.linkSystemLibrary("vulkan");
```

---

## Step 2: Remove Stub Files

```bash
cd /data/projects/grim

# Back up stubs (optional)
mkdir -p archive/vulkan-stubs
mv ui-tui/vulkan_renderer.zig archive/vulkan-stubs/
mv ui-tui/vulkan_integration.zig archive/vulkan-stubs/

# Or just delete them
# rm ui-tui/vulkan_renderer.zig ui-tui/vulkan_integration.zig
```

---

## Step 3: Create Vulkan Bridge Module

**File:** `ui-tui/vulkan_bridge.zig`

This bridges Phantom's surface/events with Zeus's renderer.

```zig
const std = @import("std");
const zeus = @import("zeus");
const phantom = @import("phantom");
const core = @import("core");

pub const VulkanBridge = struct {
    allocator: std.mem.Allocator,

    // Zeus components
    instance: *zeus.Instance,
    device: *zeus.Device,
    surface: *zeus.Surface,
    swapchain: *zeus.Swapchain,
    text_renderer: *zeus.TextRenderer,

    // Phantom window handle
    window: *phantom.Window,

    pub fn init(allocator: std.mem.Allocator, window: *phantom.Window) !*VulkanBridge {
        var self = try allocator.create(VulkanBridge);
        errdefer allocator.destroy(self);

        self.allocator = allocator;
        self.window = window;

        // 1. Create Vulkan instance
        self.instance = try zeus.Instance.init(allocator, .{
            .app_name = "Grim Editor",
            .app_version = zeus.makeApiVersion(0, 1, 0),
            .enable_validation = @import("builtin").mode == .Debug,
        });
        errdefer self.instance.deinit();

        // 2. Create surface from Phantom window
        self.surface = try zeus.Surface.initFromWindow(
            self.instance,
            window.native_handle,
            window.platform,
        );
        errdefer self.surface.deinit();

        // 3. Select physical device (prefer NVIDIA discrete GPU)
        const physical_device = try zeus.PhysicalDevice.select(
            self.instance,
            self.surface,
        );

        // 4. Create logical device
        self.device = try zeus.Device.init(allocator, physical_device, .{
            .graphics_queue = true,
            .present_queue = true,
            .transfer_queue = false,  // Use graphics queue for now
        });
        errdefer self.device.deinit();

        // 5. Create swapchain
        const window_size = window.getSize();
        self.swapchain = try zeus.Swapchain.init(
            self.device,
            self.surface,
            .{
                .width = window_size.width,
                .height = window_size.height,
                .present_mode = .MAILBOX,  // Triple buffering for low latency
                .image_count = 3,
            },
        );
        errdefer self.swapchain.deinit();

        // 6. Create text renderer
        self.text_renderer = try zeus.TextRenderer.init(allocator, self.device, .{
            .extent = .{
                .width = window_size.width,
                .height = window_size.height,
            },
            .surface_format = self.swapchain.format,
            .memory_props = physical_device.memory_properties,
            .frames_in_flight = 3,
            .max_instances = 10000,  // Max glyphs per frame
        });
        errdefer self.text_renderer.deinit();

        return self;
    }

    pub fn deinit(self: *VulkanBridge) void {
        self.text_renderer.deinit();
        self.swapchain.deinit();
        self.device.deinit();
        self.surface.deinit();
        self.instance.deinit();
        self.allocator.destroy(self);
    }

    pub fn resize(self: *VulkanBridge, width: u32, height: u32) !void {
        // Wait for GPU idle
        try self.device.waitIdle();

        // Recreate swapchain
        try self.swapchain.recreate(width, height);

        // Resize text renderer
        try self.text_renderer.resize(width, height);
    }

    pub fn renderFrame(
        self: *VulkanBridge,
        glyphs: []const GlyphQuad,
        projection: *const [16]f32,
    ) !void {
        // Acquire swapchain image
        const image_index = try self.swapchain.acquireNextImage();

        // Begin frame
        try self.text_renderer.beginFrame(image_index);

        // Set projection matrix
        try self.text_renderer.setProjection(image_index, projection);

        // Queue all glyphs
        for (glyphs) |glyph| {
            try self.text_renderer.queueQuad(glyph);
        }

        // Get command buffer
        const cmd_buffer = self.device.getCommandBuffer(image_index);

        // Encode draw commands
        try self.text_renderer.encode(cmd_buffer, image_index);

        // Submit and present
        try self.device.submit(cmd_buffer);
        try self.swapchain.present(image_index);

        // End frame
        self.text_renderer.endFrame();
    }
};

pub const GlyphQuad = zeus.TextQuad;
```

---

## Step 4: Integrate into GrimEditorWidget

**File:** `ui-tui/grim_editor_widget.zig`

```zig
const VulkanBridge = @import("vulkan_bridge.zig").VulkanBridge;

pub const GrimEditorWidget = struct {
    // ... existing fields ...

    vulkan_bridge: ?*VulkanBridge,

    pub fn init(allocator: Allocator, window: *phantom.Window) !*GrimEditorWidget {
        var self = try allocator.create(GrimEditorWidget);

        // ... existing init ...

        // Initialize Vulkan
        self.vulkan_bridge = try VulkanBridge.init(allocator, window);
        errdefer if (self.vulkan_bridge) |vb| vb.deinit();

        return self;
    }

    pub fn deinit(self: *GrimEditorWidget) void {
        if (self.vulkan_bridge) |vb| vb.deinit();
        // ... existing cleanup ...
    }

    pub fn render(self: *GrimEditorWidget) !void {
        if (self.vulkan_bridge) |vb| {
            // Convert editor text to glyph quads
            const glyphs = try self.buildGlyphQuads();
            defer self.allocator.free(glyphs);

            // Build orthographic projection matrix
            const projection = self.buildProjectionMatrix();

            // Render via Zeus
            try vb.renderFrame(glyphs, &projection);
        }
    }

    fn buildGlyphQuads(self: *GrimEditorWidget) ![]GlyphQuad {
        var quads = std.ArrayList(GlyphQuad).init(self.allocator);
        errdefer quads.deinit();

        // Iterate visible lines
        const visible_lines = self.editor.getVisibleLines();
        var y_pos: f32 = 0;

        for (visible_lines) |line, line_idx| {
            var x_pos: f32 = 0;

            // Iterate graphemes in line
            for (line.graphemes) |grapheme| {
                const glyph_id = self.font.getGlyphId(grapheme.codepoint);
                const metrics = self.font.getGlyphMetrics(glyph_id);

                // Get atlas UV coordinates
                const atlas_rect = try self.getAtlasUV(glyph_id);

                try quads.append(.{
                    .position = .{ x_pos, y_pos },
                    .size = .{ metrics.width, metrics.height },
                    .atlas_rect = atlas_rect,
                    .color = self.getGlyphColor(line_idx, grapheme),
                });

                x_pos += metrics.advance_x;
            }

            y_pos += self.font.line_height;
        }

        return quads.toOwnedSlice();
    }

    fn buildProjectionMatrix(self: *GrimEditorWidget) [16]f32 {
        const width = @as(f32, @floatFromInt(self.width));
        const height = @as(f32, @floatFromInt(self.height));

        // Orthographic projection (2D screen space)
        return .{
            2.0 / width,  0.0,           0.0, -1.0,
            0.0,          -2.0 / height, 0.0,  1.0,
            0.0,          0.0,           1.0,  0.0,
            0.0,          0.0,           0.0,  1.0,
        };
    }

    fn getGlyphColor(self: *GrimEditorWidget, line_idx: usize, grapheme: Grapheme) [4]f32 {
        // Use syntax highlighting colors from tree-sitter
        const highlight = self.syntax_highlighter.getHighlight(line_idx, grapheme.offset);

        return switch (highlight) {
            .keyword => .{ 0.8, 0.4, 0.6, 1.0 },
            .function => .{ 0.4, 0.6, 0.8, 1.0 },
            .string => .{ 0.6, 0.8, 0.4, 1.0 },
            .comment => .{ 0.5, 0.5, 0.5, 1.0 },
            else => .{ 1.0, 1.0, 1.0, 1.0 },  // Default white
        };
    }
};
```

---

## Step 5: Handle Window Events

```zig
pub fn handleEvent(self: *GrimEditorWidget, event: phantom.Event) !void {
    switch (event) {
        .resize => |size| {
            if (self.vulkan_bridge) |vb| {
                try vb.resize(size.width, size.height);
            }
        },
        // ... other events ...
    }
}
```

---

## Step 6: Glyph Rasterization (FreeType Integration)

**File:** `core/font_rasterizer.zig`

```zig
const freetype = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
});

pub const FontRasterizer = struct {
    library: freetype.FT_Library,
    face: freetype.FT_Face,

    pub fn init(font_path: []const u8, size: u32) !FontRasterizer {
        var library: freetype.FT_Library = undefined;
        if (freetype.FT_Init_FreeType(&library) != 0) {
            return error.FreeTypeInitFailed;
        }

        var face: freetype.FT_Face = undefined;
        if (freetype.FT_New_Face(library, font_path.ptr, 0, &face) != 0) {
            freetype.FT_Done_FreeType(library);
            return error.FreeTypeFaceLoadFailed;
        }

        if (freetype.FT_Set_Pixel_Sizes(face, 0, size) != 0) {
            freetype.FT_Done_Face(face);
            freetype.FT_Done_FreeType(library);
            return error.FreeTypeSetSizeFailed;
        }

        return FontRasterizer{ .library = library, .face = face };
    }

    pub fn deinit(self: *FontRasterizer) void {
        freetype.FT_Done_Face(self.face);
        freetype.FT_Done_FreeType(self.library);
    }

    pub fn rasterizeGlyph(self: *FontRasterizer, codepoint: u32) !GlyphBitmap {
        const glyph_index = freetype.FT_Get_Char_Index(self.face, codepoint);

        if (freetype.FT_Load_Glyph(self.face, glyph_index, freetype.FT_LOAD_RENDER) != 0) {
            return error.FreeTypeLoadGlyphFailed;
        }

        const bitmap = self.face.*.glyph.*.bitmap;

        return GlyphBitmap{
            .width = bitmap.width,
            .height = bitmap.rows,
            .data = bitmap.buffer[0..@as(usize, bitmap.width * bitmap.rows)],
            .advance_x = @floatFromInt(self.face.*.glyph.*.advance.x >> 6),
            .bearing_x = @floatFromInt(self.face.*.glyph.*.bitmap_left),
            .bearing_y = @floatFromInt(self.face.*.glyph.*.bitmap_top),
        };
    }
};

pub const GlyphBitmap = struct {
    width: u32,
    height: u32,
    data: []const u8,
    advance_x: f32,
    bearing_x: f32,
    bearing_y: f32,
};
```

---

## Step 7: Upload Glyphs to Atlas

```zig
fn getAtlasUV(self: *GrimEditorWidget, glyph_id: u32) ![ 4]f32 {
    // Check if already in atlas
    if (self.glyph_cache.get(glyph_id)) |uv| {
        return uv;
    }

    // Rasterize glyph
    const bitmap = try self.font_rasterizer.rasterizeGlyph(glyph_id);

    // Reserve space in atlas
    const rect = try self.vulkan_bridge.?.text_renderer.glyphAtlas().reserveRect(
        bitmap.width,
        bitmap.height,
    );

    // Upload bitmap to atlas
    try self.vulkan_bridge.?.text_renderer.glyphAtlas().upload(rect, bitmap.data);

    // Calculate UV coordinates
    const atlas_size = self.vulkan_bridge.?.text_renderer.glyphAtlas().extent;
    const uv = [4]f32{
        @as(f32, @floatFromInt(rect.x)) / @as(f32, @floatFromInt(atlas_size.width)),
        @as(f32, @floatFromInt(rect.y)) / @as(f32, @floatFromInt(atlas_size.height)),
        @as(f32, @floatFromInt(rect.width)) / @as(f32, @floatFromInt(atlas_size.width)),
        @as(f32, @floatFromInt(rect.height)) / @as(f32, @floatFromInt(atlas_size.height)),
    };

    // Cache for future use
    try self.glyph_cache.put(glyph_id, uv);

    return uv;
}
```

---

## Step 8: Build and Test

```bash
cd /data/projects/grim

# Build with Zeus
zig build -Doptimize=ReleaseFast

# Run Grim
./zig-out/bin/grim test_file.zig

# Verify GPU rendering is active
# Should see smooth 144Hz+ rendering with no tearing
```

---

## Performance Validation

### Expected Metrics
- **Frame time:** < 6.9ms @ 144Hz
- **Input latency:** < 1 frame (7ms)
- **GPU memory:** < 100MB for 10K line files
- **Smooth scrolling:** No dropped frames

### Profiling
```bash
# Enable validation layers
VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation ./zig-out/bin/grim

# Check GPU utilization
nvidia-smi dmon -s u
```

---

## Troubleshooting

### Black Screen
**Cause:** Swapchain format mismatch

**Fix:** Check surface formats in `VulkanBridge.init`

### Flickering
**Cause:** Incorrect frame synchronization

**Fix:** Verify fence/semaphore logic in `renderFrame`

### Slow Rendering
**Cause:** CPU-bound glyph batching

**Fix:** Profile with `std.time.nanoTimestamp()`, optimize hot paths

### Crashes
**Cause:** Vulkan validation errors

**Fix:** Enable validation layers, read error messages

---

## Next Steps

After successful integration:
1. Test with large files (10K+ lines)
2. Benchmark frame times at 144/240/270Hz
3. Profile GPU/CPU usage
4. Iterate on performance (Phase 6/7)

---

**Built with Zig**

