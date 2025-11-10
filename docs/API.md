# Zeus API Reference

**Version:** 0.1.5 (Phase 8 Complete)
**Zig Version:** 0.16.0-dev.164+ (Fully compatible with 0.16.0-dev.1225+)
**Last Updated:** 2025-01-10
**Target:** High-performance Vulkan 1.3/1.4 text rendering for terminal emulators

This document provides a comprehensive API reference for the Zeus Vulkan library focusing on the high-level Context API and text rendering pipeline.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Core Types](#core-types)
3. [Context API (High-Level, Recommended)](#context-api-high-level-recommended)
4. [Instance & Device Management (Low-Level)](#instance--device-management-low-level)
5. [Surface & Swapchain](#surface--swapchain)
6. [Text Rendering](#text-rendering)
7. [Resource Management](#resource-management)
8. [Synchronization](#synchronization)
9. [System Validation](#system-validation)
10. [Frame Pacing](#frame-pacing)
11. [Error Handling](#error-handling)

---

## Quick Start

### Simple Context Creation

```zig
const std = @import("std");
const zeus = @import("zeus");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create Vulkan context with defaults
    var ctx = try zeus.Context.init(allocator);
    defer ctx.deinit();

    std.log.info("Vulkan initialized successfully!", .{});
}
```

### Context with Builder Pattern (Recommended)

```zig
const std = @import("std");
const zeus = @import("zeus");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Build context with custom configuration
    var ctx = try zeus.Context.builder(allocator)
        .setAppName("My Terminal")
        .setAppVersion(1, 0, 0)
        .setApiVersion(1, 3, 0)
        .enableValidation()  // Debug builds only
        .addInstanceExtensions(&.{
            "VK_KHR_surface",
            "VK_KHR_wayland_surface",
        })
        .addDeviceExtensions(&.{
            "VK_KHR_swapchain",
        })
        .build();
    defer ctx.deinit();

    std.log.info("Graphics queue family: {d}", .{ctx.graphics_family});
}
```

### Complete Rendering Example

```zig
const std = @import("std");
const zeus = @import("zeus");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. Initialize Vulkan context
    var ctx = try zeus.Context.builder(allocator)
        .setAppName("Ghostshell")
        .setAppVersion(1, 0, 0)
        .addInstanceExtensions(&.{"VK_KHR_surface", "VK_KHR_wayland_surface"})
        .addDeviceExtensions(&.{"VK_KHR_swapchain"})
        .build();
    defer ctx.deinit();

    // 2. Create swapchain (platform-specific - see Surface section)
    // ...

    // 3. Create text renderer
    var renderer = try zeus.TextRenderer.init(allocator, &ctx, .{
        .render_pass = render_pass,
        .max_quads_per_frame = 10_000,
        .atlas_width = 2048,
        .atlas_height = 2048,
    });
    defer renderer.deinit();

    // 4. Render loop with frame pacing
    var pacer = zeus.FramePacer.init(144); // 144 FPS
    while (running) {
        const delta_ns = pacer.beginFrame();

        // Acquire swapchain image
        const image_index = try swapchain.acquireNextImage(...);

        // Begin rendering
        try renderer.beginFrame(viewport, command_buffer);

        // Queue glyphs
        for (terminal_buffer) |cell| {
            try renderer.queueQuad(.{
                .x = cell.x,
                .y = cell.y,
                .width = glyph_width,
                .height = glyph_height,
                .atlas_u = cell.glyph.u,
                .atlas_v = cell.glyph.v,
                .atlas_w = cell.glyph.w,
                .atlas_h = cell.glyph.h,
                .color = cell.fg_color,
            });
        }

        // Finish frame
        const stats = try renderer.endFrame();
        try swapchain.present(image_index);

        pacer.endFrame();
    }
}
```

---

## Core Types

### VkInstance
**Type:** `types.VkInstance`
**Description:** Opaque handle to a Vulkan instance

### VkPhysicalDevice
**Type:** `types.VkPhysicalDevice`
**Description:** Opaque handle to a physical GPU device

### VkDevice
**Type:** `types.VkDevice`
**Description:** Opaque handle to a logical Vulkan device

### VkSurfaceKHR
**Type:** `types.VkSurfaceKHR`
**Description:** Opaque handle to a Vulkan surface for presentation

### VkSwapchainKHR
**Type:** `types.VkSwapchainKHR`
**Description:** Opaque handle to a Vulkan swapchain

---

## Context API (High-Level, Recommended)

The `Context` provides a unified, high-level API for Vulkan initialization with automatic resource management. This is the **recommended** entry point for Zeus.

### Context

Manages the entire Vulkan lifecycle: loader, instance, physical device, logical device, and queues.

#### `Context.init`
```zig
pub fn init(allocator: std.mem.Allocator) !Context
```

**Description:** Create a Context with default settings (Vulkan 1.3, discrete GPU preference, graphics queue only)

**Parameters:**
- `allocator`: Memory allocator

**Returns:** `Context` with all resources initialized

**Example:**
```zig
var ctx = try zeus.Context.init(allocator);
defer ctx.deinit();
```

#### `Context.builder`
```zig
pub fn builder(allocator: std.mem.Allocator) Context.Builder
```

**Description:** Create a Builder for custom Context configuration

**Returns:** `Context.Builder` instance

**Example:**
```zig
var ctx = try zeus.Context.builder(allocator)
    .setAppName("My App")
    .enableValidation()
    .build();
defer ctx.deinit();
```

#### `Context.deinit`
```zig
pub fn deinit(self: *Context) void
```

**Description:** Cleanup all Vulkan resources (call with `defer`)

#### `Context.waitIdle`
```zig
pub fn waitIdle(self: *Context) !void
```

**Description:** Wait for all device queues to complete operations

#### `Context.waitGraphicsIdle`
```zig
pub fn waitGraphicsIdle(self: *Context) !void
```

**Description:** Wait for graphics queue only

---

### Context.Builder

Fluent API for configuring Context creation.

#### `Builder.init`
```zig
pub fn init(allocator: std.mem.Allocator) Builder
```

**Description:** Initialize a new builder with default settings

#### `Builder.setAppName`
```zig
pub fn setAppName(self: Builder, name: [:0]const u8) Builder
```

**Parameters:**
- `name`: Application name (null-terminated)

**Returns:** Updated builder (chainable)

**Example:**
```zig
.setAppName("Ghostshell")
```

#### `Builder.setAppVersion`
```zig
pub fn setAppVersion(self: Builder, major: u32, minor: u32, patch: u32) Builder
```

**Parameters:**
- `major`, `minor`, `patch`: Semantic version components

**Returns:** Updated builder (chainable)

**Example:**
```zig
.setAppVersion(1, 2, 0)
```

#### `Builder.setApiVersion`
```zig
pub fn setApiVersion(self: Builder, major: u32, minor: u32, patch: u32) Builder
```

**Parameters:**
- `major`, `minor`, `patch`: Vulkan API version (e.g., 1, 3, 0 for Vulkan 1.3)

**Returns:** Updated builder (chainable)

**Default:** Vulkan 1.3.0

**Example:**
```zig
.setApiVersion(1, 4, 0)  // Request Vulkan 1.4
```

#### `Builder.enableValidation`
```zig
pub fn enableValidation(self: Builder) Builder
```

**Description:** Enable Vulkan validation layers (requires `VK_LAYER_KHRONOS_validation`)

**Returns:** Updated builder (chainable)

**Note:** Only enable in debug builds - significant performance overhead

**Example:**
```zig
.enableValidation()
```

#### `Builder.requireComputeQueue`
```zig
pub fn requireComputeQueue(self: Builder) Builder
```

**Description:** Require a compute queue (fails if unavailable)

**Returns:** Updated builder (chainable)

#### `Builder.requireTransferQueue`
```zig
pub fn requireTransferQueue(self: Builder) Builder
```

**Description:** Require a dedicated transfer queue (fails if unavailable)

**Returns:** Updated builder (chainable)

#### `Builder.addInstanceExtensions`
```zig
pub fn addInstanceExtensions(self: Builder, extensions: []const [*:0]const u8) Builder
```

**Parameters:**
- `extensions`: Slice of null-terminated extension names

**Returns:** Updated builder (chainable)

**Common Extensions:**
- `VK_KHR_surface` - Required for presentation
- `VK_KHR_wayland_surface` - Wayland support
- `VK_KHR_xcb_surface` - X11 support
- `VK_EXT_debug_utils` - Debug utilities (with validation)

**Example:**
```zig
.addInstanceExtensions(&.{
    "VK_KHR_surface",
    "VK_KHR_wayland_surface",
})
```

#### `Builder.addDeviceExtensions`
```zig
pub fn addDeviceExtensions(self: Builder, extensions: []const [*:0]const u8) Builder
```

**Parameters:**
- `extensions`: Slice of null-terminated device extension names

**Returns:** Updated builder (chainable)

**Common Extensions:**
- `VK_KHR_swapchain` - Required for presentation

**Example:**
```zig
.addDeviceExtensions(&.{
    "VK_KHR_swapchain",
})
```

#### `Builder.build`
```zig
pub fn build(self: Builder) !Context
```

**Description:** Build the Context with all configured options

**Returns:** Initialized `Context`

**Errors:**
- `error.InstanceCreationFailed` - Instance creation failed
- `error.NoVulkanDevices` - No Vulkan-capable GPUs found
- `error.NoGraphicsQueue` - No graphics queue family found
- `error.DeviceCreationFailed` - Logical device creation failed

**Example:**
```zig
var ctx = try builder.build();
defer ctx.deinit();
```

---

### Context Fields

Once built, the Context exposes these public fields:

```zig
pub const Context = struct {
    allocator: std.mem.Allocator,
    loader: Loader,
    instance: VkInstance,
    instance_dispatch: InstanceDispatch,
    physical_device: VkPhysicalDevice,
    device: VkDevice,
    device_dispatch: DeviceDispatch,

    // Queue handles
    graphics_queue: VkQueue,
    compute_queue: ?VkQueue,      // Only if requireComputeQueue()
    transfer_queue: ?VkQueue,     // Only if requireTransferQueue()

    // Queue family indices
    graphics_family: u32,
    compute_family: ?u32,
    transfer_family: ?u32,
};
```

**Usage Example:**
```zig
var ctx = try zeus.Context.builder(allocator)
    .requireComputeQueue()
    .build();
defer ctx.deinit();

std.log.info("Graphics family: {d}", .{ctx.graphics_family});
std.log.info("Compute family: {?d}", .{ctx.compute_family});

// Use device dispatch for Vulkan calls
const cmd_pool_info = zeus.types.VkCommandPoolCreateInfo{
    .sType = .COMMAND_POOL_CREATE_INFO,
    .queueFamilyIndex = ctx.graphics_family,
    .flags = zeus.types.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
};
var cmd_pool: zeus.types.VkCommandPool = undefined;
const result = ctx.device_dispatch.create_command_pool(
    ctx.device,
    &cmd_pool_info,
    null,
    &cmd_pool
);
```

---

## Instance & Device Management (Low-Level)

### Loader

Manages dynamic loading of Vulkan functions.

#### `Loader.init`
```zig
pub fn init(allocator: std.mem.Allocator) !Loader
```

**Parameters:**
- `allocator`: Memory allocator

**Returns:** `Loader` instance

**Errors:**
- `error.LibraryNotFound` - Vulkan library not found on system
- `error.SymbolNotFound` - Required Vulkan symbol missing

**Example:**
```zig
var loader = try zeus.Loader.init(allocator);
defer loader.deinit();
```

---

### Instance

Manages Vulkan instance lifecycle.

#### `Instance.create`
```zig
pub fn create(
    loader_ref: *Loader,
    allocator: std.mem.Allocator,
    options: CreateOptions
) !Instance
```

**Parameters:**
- `loader_ref`: Pointer to Vulkan loader
- `allocator`: Memory allocator
- `options`: Instance creation options

**CreateOptions:**
```zig
pub const CreateOptions = struct {
    application: ?ApplicationInfo = null,
    enabled_layers: []const [:0]const u8 = &.{},
    enabled_extensions: []const [:0]const u8 = &.{},
    allocation_callbacks: ?*const types.VkAllocationCallbacks = null,
};
```

**Returns:** `Instance`

**Example:**
```zig
var instance = try zeus.Instance.create(&loader, allocator, .{
    .application = .{
        .application_name = "MyApp",
        .application_version = zeus.types.makeApiVersion(1, 0, 0),
    },
    .enabled_extensions = &.{
        "VK_KHR_surface",
        "VK_KHR_wayland_surface",
    },
});
defer instance.destroy();
```

#### `Instance.enumeratePhysicalDevices`
```zig
pub fn enumeratePhysicalDevices(
    self: *Instance,
    allocator: std.mem.Allocator
) ![]types.VkPhysicalDevice
```

**Returns:** Slice of physical devices (caller owns memory)

---

### Device

Manages logical device lifecycle.

#### `Device.create`
```zig
pub fn create(
    loader: *Loader,
    instance_dispatch: *const loader.InstanceDispatch,
    allocator: std.mem.Allocator,
    options: Options
) !Device
```

**Options:**
```zig
pub const Options = struct {
    physical_device: types.VkPhysicalDevice,
    queue_family_indices: []const u32,
    enabled_extensions: []const [:0]const u8 = &.{},
    enabled_features: ?*const types.VkPhysicalDeviceFeatures = null,
    allocation_callbacks: ?*const types.VkAllocationCallbacks = null,
};
```

---

## Surface & Swapchain

### Surface

Represents a Vulkan surface for presentation.

#### `Surface.wrap`
```zig
pub fn wrap(
    instance: *Instance,
    surface_handle: types.VkSurfaceKHR,
    allocation_callbacks: ?*const types.VkAllocationCallbacks
) Surface
```

**Parameters:**
- `instance`: Vulkan instance
- `surface_handle`: Native surface handle (e.g., from Wayland)
- `allocation_callbacks`: Optional allocation callbacks

**Returns:** `Surface`

#### `Surface.capabilities`
```zig
pub fn capabilities(
    self: Surface,
    physical_device: types.VkPhysicalDevice
) !types.VkSurfaceCapabilitiesKHR
```

**Returns:** Surface capabilities (min/max extents, image count, etc.)

---

### Swapchain

Manages swapchain lifecycle and image acquisition.

#### `Swapchain.init`
```zig
pub fn init(
    device: *Device,
    allocator: std.mem.Allocator,
    options: Options
) !Swapchain
```

**Options:**
```zig
pub const Options = struct {
    surface: types.VkSurfaceKHR,
    min_image_count: u32,
    image_format: types.VkSurfaceFormatKHR,
    image_extent: types.VkExtent2D,
    present_mode: types.VkPresentModeKHR,
    old_swapchain: ?types.VkSwapchainKHR = null,
};
```

#### `Swapchain.acquireNextImage`
```zig
pub fn acquireNextImage(
    self: *Swapchain,
    timeout_ns: u64,
    semaphore: ?types.VkSemaphore,
    fence: ?types.VkFence
) !AcquireResult
```

**Returns:** `AcquireResult` with image index and status

**Example:**
```zig
const result = try swapchain.acquireNextImage(
    std.math.maxInt(u64), // No timeout
    image_available_semaphore,
    null
);

if (result.status == .suboptimal or result.status == .out_of_date) {
    // Recreate swapchain
}
```

---

## Text Rendering

### TextRenderer

High-performance text rendering system.

#### `TextRenderer.init`
```zig
pub fn init(
    allocator: std.mem.Allocator,
    device: *Device,
    options: InitOptions
) !TextRenderer
```

**InitOptions:**
```zig
pub const InitOptions = struct {
    render_pass: types.VkRenderPass,
    subpass: u32 = 0,
    max_quads_per_frame: u32 = 10_000,
    atlas_width: u32 = 2048,
    atlas_height: u32 = 2048,
    enable_auto_batching: bool = true,
    profiler: ?*const Profiler = null,
};
```

#### `TextRenderer.beginFrame`
```zig
pub fn beginFrame(
    self: *TextRenderer,
    viewport: types.VkViewport,
    command_buffer: types.VkCommandBuffer
) !void
```

**Parameters:**
- `viewport`: Viewport dimensions
- `command_buffer`: Command buffer to record into

#### `TextRenderer.queueQuad`
```zig
pub fn queueQuad(self: *TextRenderer, quad: TextQuad) !void
```

**TextQuad:**
```zig
pub const TextQuad = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    atlas_u: f32,
    atlas_v: f32,
    atlas_w: f32,
    atlas_h: f32,
    color: u32, // RGBA8888
};
```

#### `TextRenderer.endFrame`
```zig
pub fn endFrame(self: *TextRenderer) !FrameStats
```

**Returns:** `FrameStats` with performance metrics

**Complete Example:**
```zig
var renderer = try zeus.TextRenderer.init(allocator, &device, .{
    .render_pass = render_pass,
    .max_quads_per_frame = 20_000,
    .enable_auto_batching = true,
});
defer renderer.deinit();

// Render loop
while (running) {
    try renderer.beginFrame(viewport, command_buffer);

    // Queue text
    for (text_buffer) |char| {
        const glyph = try atlas.getGlyph(char);
        try renderer.queueQuad(.{
            .x = char.x,
            .y = char.y,
            .width = glyph.width,
            .height = glyph.height,
            .atlas_u = glyph.u,
            .atlas_v = glyph.v,
            .atlas_w = glyph.w,
            .atlas_h = glyph.h,
            .color = 0xFFFFFFFF,
        });
    }

    const stats = try renderer.endFrame();
    std.debug.print("Drew {d} quads in {d} draws\n", .{
        stats.quad_count,
        stats.draw_count,
    });
}
```

---

### GlyphAtlas

Manages glyph texture atlas.

#### `GlyphAtlas.init`
```zig
pub fn init(
    allocator: std.mem.Allocator,
    device: *Device,
    width: u32,
    height: u32
) !GlyphAtlas
```

#### `GlyphAtlas.upload`
```zig
pub fn upload(
    self: *GlyphAtlas,
    key: GlyphKey,
    metrics: GlyphMetrics,
    bitmap: []const u8
) !void
```

**GlyphKey:**
```zig
pub const GlyphKey = struct {
    codepoint: u32,
    size_pt: u16,
    style: GlyphStyle,

    pub const GlyphStyle = packed struct {
        bold: bool = false,
        italic: bool = false,
        _padding: u6 = 0,
    };
};
```

---

## Resource Management

### ManagedBuffer

RAII-style buffer management.

#### `ManagedBuffer.init`
```zig
pub fn init(
    device: *Device,
    allocator: std.mem.Allocator,
    size: usize,
    usage: types.VkBufferUsageFlags,
    memory_properties: types.VkMemoryPropertyFlags
) !ManagedBuffer
```

**Example:**
```zig
var buffer = try zeus.ManagedBuffer.init(
    &device,
    allocator,
    1024 * 1024, // 1 MB
    types.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
    types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
    types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT
);
defer buffer.deinit();
```

---

## Synchronization

### Fence

GPU-CPU synchronization primitive.

#### `Fence.init`
```zig
pub fn init(device: *Device, signaled: bool) !Fence
```

#### `Fence.wait`
```zig
pub fn wait(self: *Fence, timeout_ns: u64) !void
```

### Semaphore

GPU-GPU synchronization primitive.

#### `Semaphore.init`
```zig
pub fn init(device: *Device, semaphore_type: SemaphoreType) !Semaphore
```

**SemaphoreType:**
- `.binary` - Traditional binary semaphore
- `.timeline` - Timeline semaphore (Vulkan 1.2+)

---

## System Validation

### System Validation

Validates system configuration for optimal performance.

#### `validateSystem`
```zig
pub fn validateSystem(
    allocator: std.mem.Allocator,
    memory_props: types.VkPhysicalDeviceMemoryProperties,
    options: SystemValidationOptions
) !SystemValidation
```

**SystemValidationOptions:**
```zig
pub const SystemValidationOptions = struct {
    kernel: KernelValidationOptions = .{},
    check_compositor: bool = true,
    check_high_refresh: bool = true,
    target_refresh_hz: u32 = 144,
};
```

**Example:**
```zig
const validation = try zeus.system_validation.validateSystem(
    allocator,
    memory_props,
    .{
        .check_compositor = true,
        .target_refresh_hz = 360,
    }
);
defer validation.deinit(allocator);

zeus.system_validation.logSystemValidation(validation);

if (validation.needsAttention()) {
    std.log.warn("System configuration needs attention", .{});
}
```

---

### Compositor Validation

Detects Wayland compositor and provides quirks information.

#### `detectCompositor`
```zig
pub fn detectCompositor(allocator: std.mem.Allocator) !CompositorInfo
```

**CompositorInfo:**
```zig
pub const CompositorInfo = struct {
    compositor_type: CompositorType,
    detected: bool,
    display_name: ?[]const u8,
    desktop_session: ?[]const u8,
    wayland_socket: ?[]const u8,
    is_tested: bool,
    supports_vulkan: bool,
};
```

**CompositorType:**
- `.hyprland` - Hyprland compositor
- `.kde_plasma` - KDE Plasma Wayland
- `.gnome` - GNOME Shell
- `.sway` - Sway
- `.river` - River
- `.wayfire` - Wayfire
- `.unknown` - Unknown or unsupported

**Example:**
```zig
var comp_info = try zeus.compositor_validation.detectCompositor(allocator);
defer comp_info.deinit(allocator);

const quirks = zeus.CompositorQuirks.forCompositor(comp_info.compositor_type);

if (quirks.requires_mailbox_fallback) {
    present_mode = .FIFO; // Use FIFO instead of MAILBOX
}
```

---

## Frame Pacing

### FramePacer

Maintains consistent frame timing.

#### `FramePacer.init`
```zig
pub fn init(target_fps: u32) FramePacer
```

#### `FramePacer.beginFrame`
```zig
pub fn beginFrame(self: *FramePacer) u64
```

**Returns:** Delta time in nanoseconds since last frame

#### `FramePacer.endFrame`
```zig
pub fn endFrame(self: *FramePacer) void
```

**Example:**
```zig
var pacer = zeus.FramePacer.init(360); // 360 FPS target

while (running) {
    const delta_ns = pacer.beginFrame();

    // Render frame...

    pacer.endFrame(); // Sleeps if frame finished early
}
```

---

## Error Handling

### Error Types

Zeus uses Zig's error unions. Common error types:

```zig
pub const Error = error{
    // Vulkan errors
    InstanceCreationFailed,
    DeviceCreationFailed,
    OutOfMemory,
    SurfaceLost,
    SwapchainOutOfDate,

    // Resource errors
    BufferCreationFailed,
    AllocationFailed,

    // System errors
    LibraryNotFound,
    SymbolNotFound,

    // Validation errors
    NoPhysicalDevices,
    QueueFamilyNotFound,
    ExtensionNotSupported,
};
```

### Error Handling Best Practices

```zig
// 1. Explicit error handling
const device = zeus.Device.create(...) catch |err| {
    std.log.err("Failed to create device: {s}", .{@errorName(err)});
    return err;
};

// 2. Error propagation
pub fn initRenderer() !Renderer {
    const device = try createDevice();
    const renderer = try Renderer.init(&device);
    return renderer;
}

// 3. Cleanup with errdefer
var instance = try Instance.create(...);
errdefer instance.destroy();

var device = try Device.create(...);
errdefer device.destroy();
```

---

## Performance Targets

### Frame Time Budgets

| Refresh Rate | Frame Budget | Status |
|--------------|--------------|--------|
| 60 Hz        | 16.67ms      | ✅ Excellent |
| 144 Hz       | 6.94ms       | ✅ Target |
| 240 Hz       | 4.16ms       | ✅ Optimized |
| 360 Hz       | 2.77ms       | ✅ Validated |

### Memory Usage

- **Atlas:** 4-8 MB (2048x2048 R8 texture)
- **Per-frame buffers:** ~200 KB (10K quads)
- **Overhead:** < 1 MB

### Batching Performance

Zeus achieves ~512 glyphs per draw call with automatic batching, reducing draw call overhead significantly.

---

## Platform Support

### Tested Platforms

| Platform | Compositor | Status |
|----------|------------|--------|
| Linux | KDE Plasma Wayland | ✅ Fully Tested |
| Linux | Hyprland | ✅ Fully Tested |
| Linux | GNOME Shell | 🟡 Compatible (with quirks) |
| Linux | Sway | 🟡 Compatible |

### Required Extensions

**Instance:**
- `VK_KHR_surface`
- `VK_KHR_wayland_surface` (Wayland)

**Device:**
- `VK_KHR_swapchain`

---

## See Also

- [Architecture Documentation](ARCHITECTURE.md)
- [Performance Guide](PERFORMANCE.md)
- [Integration Guide](INTEGRATION.md)
- [Wayland Compositor Compatibility](WAYLAND_COMPOSITOR_COMPATIBILITY.md)
- [Breaking Changes Policy](BREAKING_CHANGES.md)

---

**Last Updated:** 2025-01-10
**Version:** 0.1.5 (Phase 8 Complete)
**License:** MIT
