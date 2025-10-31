const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const image = @import("image.zig");
const buffer = @import("buffer.zig");
const loader = @import("loader.zig");

pub const GlyphKey = struct {
    font_id: u32,
    glyph_id: u32,
    variant: u16 = 0,
    subpixel: u8 = 0,

    pub fn eql(a: GlyphKey, b: GlyphKey) bool {
        return std.meta.eql(a, b);
    }

    pub fn hash(self: GlyphKey) u64 {
        var h = std.hash.XxHash64.init(0);
        h.update(std.mem.asBytes(&self.font_id));
        h.update(std.mem.asBytes(&self.glyph_id));
        h.update(std.mem.asBytes(&self.variant));
        h.update(std.mem.asBytes(&self.subpixel));
        return h.final();
    }
};

pub const GlyphMetrics = struct {
    advance: f32,
    bearing: types.VkOffset2D,
    size: types.VkExtent2D,
};

pub const GlyphRect = struct {
    origin: types.VkOffset2D,
    size: types.VkExtent2D,
};

pub const GlyphInfo = struct {
    key: GlyphKey,
    rect: GlyphRect,
    uv_min: [2]f32,
    uv_max: [2]f32,
    advance: f32,
    bearing: types.VkOffset2D,
};

pub const RasterRequest = struct {
    key: GlyphKey,
    size: types.VkExtent2D,
};

pub const RasterCallback = *const fn (?*anyopaque, RasterRequest, []u8) errors.Error!void;

pub const GrowthCallback = *const fn (?*anyopaque, *GlyphAtlas, types.VkExtent2D) errors.Error!void;

pub const UploadTarget = struct {
    staging: buffer.ManagedBuffer,
    rect: GlyphRect,
};

const default_padding: u32 = 1;
const default_extent = types.VkExtent2D{ .width = 512, .height = 512 };

pub const Options = struct {
    extent: types.VkExtent2D = default_extent,
    format: types.VkFormat = .R8_UNORM,
    padding: u32 = default_padding,
    rasterizer: ?RasterCallback = null,
    raster_context: ?*anyopaque = null,
    growth_callback: ?GrowthCallback = null,
    growth_context: ?*anyopaque = null,
};

const Shelf = struct {
    y: u32,
    height: u32,
    cursor_x: u32,
};

const PendingUpload = struct {
    staging: buffer.ManagedBuffer,
    rect: GlyphRect,
};

pub const GlyphAtlas = struct {
    allocator: std.mem.Allocator,
    device: *device_mod.Device,
    memory_props: types.VkPhysicalDeviceMemoryProperties,
    options: Options,

    atlas: image.ManagedImage,
    shelves: std.ArrayList(Shelf),
    next_y: u32,
    glyphs: std.AutoHashMap(GlyphKey, GlyphInfo),

    pending_uploads: std.ArrayList(PendingUpload),
    in_flight_uploads: std.ArrayList(buffer.ManagedBuffer),

    rasterizer: RasterCallback,
    raster_context: *anyopaque,

    pub fn init(allocator: std.mem.Allocator, device: *device_mod.Device, memory_props: types.VkPhysicalDeviceMemoryProperties, options: Options) errors.Error!GlyphAtlas {
        var opts = options;
        const raster_cb = opts.rasterizer orelse defaultRasterizer;
        const raster_ctx = opts.raster_context;
        if (opts.padding == 0) opts.padding = default_padding;

        var extent = opts.extent;
        if (extent.width == 0 or extent.height == 0) {
            extent = default_extent;
        }

        opts.extent = extent;

        const atlas_image = try image.createManagedImage(device, memory_props, .{
            .image = .{
                .format = opts.format,
                .extent = .{ .width = extent.width, .height = extent.height, .depth = 1 },
                .usage = types.VK_IMAGE_USAGE_SAMPLED_BIT | types.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
                .initial_layout = types.VkImageLayout.UNDEFINED,
            },
            .aspect_mask = types.VK_IMAGE_ASPECT_COLOR_BIT,
            .view_type = .@"2D",
        });

        var shelves = std.ArrayList(Shelf).init(allocator);
        try shelves.append(.{ .y = 0, .height = 0, .cursor_x = 0 });

        return GlyphAtlas{
            .allocator = allocator,
            .device = device,
            .memory_props = memory_props,
            .options = opts,
            .atlas = atlas_image,
            .shelves = shelves,
            .next_y = 0,
            .glyphs = std.AutoHashMap(GlyphKey, GlyphInfo).init(allocator),
            .pending_uploads = std.ArrayList(PendingUpload).init(allocator),
            .in_flight_uploads = std.ArrayList(buffer.ManagedBuffer).init(allocator),
            .rasterizer = raster_cb,
            .raster_context = raster_ctx,
        };
    }

    pub fn deinit(self: *GlyphAtlas) void {
        var it = self.glyphs.iterator();
        while (it.next()) |_| {}
        self.glyphs.deinit();

        for (self.pending_uploads.items) |*pending| {
            pending.staging.deinit();
        }
        self.pending_uploads.deinit();

        for (self.in_flight_uploads.items) |*buffer_obj| {
            buffer_obj.deinit();
        }
        self.in_flight_uploads.deinit();

        self.shelves.deinit();
        self.atlas.deinit();
    }

    pub fn managedImage(self: *GlyphAtlas) *image.ManagedImage {
        return &self.atlas;
    }

    pub fn lookup(self: *GlyphAtlas, key: GlyphKey) ?GlyphInfo {
        if (self.glyphs.get(key)) |info| return info;
        return null;
    }

    pub fn ensure(self: *GlyphAtlas, key: GlyphKey, metrics: GlyphMetrics) errors.Error!GlyphInfo {
        if (self.glyphs.get(key)) |info| return info;

        const rect = try self.reserveRect(metrics.size);
        const pixel_count = @as(usize, rect.size.width) * @as(usize, rect.size.height);
        const pixels = try self.allocator.alloc(u8, pixel_count);
        defer self.allocator.free(pixels);

        const request = RasterRequest{ .key = key, .size = metrics.size };
        try self.rasterizer(self.raster_context, request, pixels);

        var staging = try buffer.createManagedBuffer(
            self.device,
            self.memory_props,
            @intCast(pixel_count),
            types.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            .{
                .filter = .{
                    .required_flags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT,
                    .preferred_flags = types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                },
            },
        );
        errdefer staging.deinit();

        try staging.write(pixels, 0);

        try self.pending_uploads.append(.{ .staging = staging, .rect = rect });

        const uv_min = .{ @as(f32, @floatFromInt(rect.origin.x)) / @as(f32, @floatFromInt(self.atlas.extent.width)), @as(f32, @floatFromInt(rect.origin.y)) / @as(f32, @floatFromInt(self.atlas.extent.height)) };
        const uv_max = .{ @as(f32, @floatFromInt(rect.origin.x + @as(i32, @intCast(rect.size.width)))) / @as(f32, @floatFromInt(self.atlas.extent.width)), @as(f32, @floatFromInt(rect.origin.y + @as(i32, @intCast(rect.size.height)))) / @as(f32, @floatFromInt(self.atlas.extent.height)) };

        const glyph_info = GlyphInfo{
            .key = key,
            .rect = rect,
            .uv_min = uv_min,
            .uv_max = uv_max,
            .advance = metrics.advance,
            .bearing = metrics.bearing,
        };
        try self.glyphs.put(key, glyph_info);
        return glyph_info;
    }

    fn reserveRect(self: *GlyphAtlas, size: types.VkExtent2D) errors.Error!GlyphRect {
        const padding_twice = std.math.mul(u32, self.options.padding, 2) catch return errors.Error.FeatureNotPresent;
        const padded_width = std.math.add(u32, size.width, padding_twice) catch return errors.Error.FeatureNotPresent;
        const padded_height = std.math.add(u32, size.height, padding_twice) catch return errors.Error.FeatureNotPresent;
        std.debug.assert(padded_width > 0 and padded_height > 0);

        if (padded_width > self.atlas.extent.width or padded_height > self.atlas.extent.height) {
            try self.requestGrowth(padded_width, padded_height);
            if (padded_width > self.atlas.extent.width or padded_height > self.atlas.extent.height) {
                return errors.Error.FeatureNotPresent;
            }
            return self.reserveRect(size);
        }

        var best_index: ?usize = null;
        var best_y: u32 = std.math.maxInt(u32);

        for (self.shelves.items, 0..) |shelf, idx| {
            const shelf_end = std.math.add(u32, shelf.cursor_x, padded_width) catch continue;
            if (shelf_end > self.atlas.extent.width) continue;
            if (shelf.height != 0 and padded_height > shelf.height) continue;
            if (shelf.y < best_y) {
                best_y = shelf.y;
                best_index = idx;
            }
        }

        if (best_index) |index| {
            var shelf = &self.shelves.items[index];
            if (shelf.height == 0) {
                shelf.height = padded_height;
            }

            const rect = GlyphRect{
                .origin = .{
                    .x = @as(i32, @intCast(shelf.cursor_x + self.options.padding)),
                    .y = @as(i32, @intCast(shelf.y + self.options.padding)),
                },
                .size = size,
            };
            shelf.cursor_x = std.math.add(u32, shelf.cursor_x, padded_width) catch return errors.Error.FeatureNotPresent;
            return rect;
        }

        const needed_height = std.math.add(u32, self.next_y, padded_height) catch return errors.Error.FeatureNotPresent;
        if (needed_height > self.atlas.extent.height) {
            try self.requestGrowth(padded_width, padded_height);
            if (padded_height > self.atlas.extent.height) {
                return errors.Error.FeatureNotPresent;
            }
            return self.reserveRect(size);
        } else {
            const new_shelf_y = self.next_y;
            self.next_y = needed_height;
            try self.shelves.append(.{ .y = new_shelf_y, .height = padded_height, .cursor_x = padded_width });

            return GlyphRect{
                .origin = .{ .x = @as(i32, @intCast(self.options.padding)), .y = @as(i32, @intCast(new_shelf_y + self.options.padding)) },
                .size = size,
            };
        }
    }

    fn requestGrowth(self: *GlyphAtlas, width: u32, height: u32) errors.Error!void {
        if (self.options.growth_callback) |cb| {
            const new_extent = suggestGrowth(self.atlas.extent, width, height);
            try cb(self.options.growth_context, self, new_extent);
            return;
        }
        return errors.Error.FeatureNotPresent;
    }

    pub fn resize(self: *GlyphAtlas, new_image: image.ManagedImage) void {
        self.atlas.deinit();
        self.atlas = new_image;
        self.shelves.clearRetainingCapacity();
        self.glyphs.clearRetainingCapacity();
        self.next_y = 0;
        _ = self.shelves.append(.{ .y = 0, .height = 0, .cursor_x = 0 }) catch unreachable;
    }

    pub fn flushUploads(self: *GlyphAtlas, cmd: types.VkCommandBuffer) errors.Error!bool {
        if (self.pending_uploads.items.len == 0) return false;

        try self.atlas.ensureLayout(cmd, .TRANSFER_DST_OPTIMAL, .{
            .range = null,
            .src_stage = types.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
            .dst_stage = types.VK_PIPELINE_STAGE_TRANSFER_BIT,
            .src_access = types.VK_ACCESS_SHADER_READ_BIT,
            .dst_access = types.VK_ACCESS_TRANSFER_WRITE_BIT,
        });

        for (self.pending_uploads.items) |pending| {
            const buffer_copy = types.VkBufferImageCopy{
                .bufferOffset = 0,
                .bufferRowLength = pending.rect.size.width,
                .bufferImageHeight = pending.rect.size.height,
                .imageSubresource = .{
                    .aspectMask = types.VK_IMAGE_ASPECT_COLOR_BIT,
                    .mipLevel = 0,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
                .imageOffset = .{
                    .x = pending.rect.origin.x,
                    .y = pending.rect.origin.y,
                    .z = 0,
                },
                .imageExtent = .{
                    .width = pending.rect.size.width,
                    .height = pending.rect.size.height,
                    .depth = 1,
                },
            };
            self.device.dispatch.cmd_copy_buffer_to_image(cmd, pending.staging.buffer, self.atlas.image, .TRANSFER_DST_OPTIMAL, 1, &buffer_copy);
            try self.in_flight_uploads.append(pending.staging);
        }

        self.pending_uploads.clearRetainingCapacity();

        try self.atlas.ensureLayout(cmd, .SHADER_READ_ONLY_OPTIMAL, .{
            .range = null,
            .src_stage = types.VK_PIPELINE_STAGE_TRANSFER_BIT,
            .dst_stage = types.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
            .src_access = types.VK_ACCESS_TRANSFER_WRITE_BIT,
            .dst_access = types.VK_ACCESS_SHADER_READ_BIT,
        });

        return true;
    }

    pub fn releaseUploads(self: *GlyphAtlas) void {
        for (self.in_flight_uploads.items) |*upload| {
            upload.deinit();
        }
        self.in_flight_uploads.clearRetainingCapacity();
    }
};

fn suggestGrowth(current: types.VkExtent2D, width: u32, height: u32) types.VkExtent2D {
    var new_width = current.width;
    var new_height = current.height;
    if (width > current.width) new_width = std.math.min(current.width * 2, 4096);
    if (height > current.height) new_height = std.math.min(current.height * 2, 4096);
    if (new_width == current.width and new_height == current.height) {
        new_width = std.math.min(current.width * 2, 4096);
        new_height = std.math.min(current.height * 2, 4096);
    }
    return .{ .width = new_width, .height = new_height };
}

fn defaultRasterizer(_: *anyopaque, request: RasterRequest, out_pixels: []u8) errors.Error!void {
    const width = request.size.width;
    const height = request.size.height;
    if (width == 0 or height == 0) return;
    const stride = @as(usize, width);
    for (0..height) |y| {
        const row_start = y * stride;
        for (0..width) |x| {
            const value = if ((x ^ y) & 1 == 0) 255 else 180;
            out_pixels[row_start + x] = @intCast(value);
        }
    }
}

// --------------------- Tests ---------------------

const builtin = @import("builtin");

test "GlyphAtlas packs glyphs and enqueues uploads" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    TestCapture.reset();
    var device = makeTestDevice(alloc);

    var atlas = try GlyphAtlas.init(alloc, &device, makeMemoryProps(), .{});
    defer atlas.deinit();

    const key = GlyphKey{ .font_id = 1, .glyph_id = 42 };
    const info = try atlas.ensure(key, .{
        .advance = 10.0,
        .bearing = .{ .x = 1, .y = 2 },
        .size = .{ .width = 16, .height = 16 },
    });
    try std.testing.expectEqual(key.glyph_id, info.key.glyph_id);
    try std.testing.expectEqual(@as(usize, 1), atlas.pending_uploads.items.len);

    const cmd = fake_command_buffer;
    try atlas.flushUploads(cmd);
    try std.testing.expectEqual(@as(usize, 0), atlas.pending_uploads.items.len);
    try std.testing.expectEqual(@as(usize, 1), atlas.in_flight_uploads.items.len);
    try std.testing.expectEqual(@as(usize, 1), TestCapture.copy_calls);
    try std.testing.expect(TestCapture.last_copy != null);

    atlas.releaseUploads();
    try std.testing.expectEqual(@as(usize, 0), atlas.in_flight_uploads.items.len);
}

const fake_device_handle = @as(types.VkDevice, @ptrFromInt(@as(usize, 0x1010)));
const fake_image_handle = @as(types.VkImage, @ptrFromInt(@as(usize, 0x2020)));
const fake_image_view = @as(types.VkImageView, @ptrFromInt(@as(usize, 0x3030)));
const fake_buffer_handle = @as(types.VkBuffer, @ptrFromInt(@as(usize, 0x4040)));
const fake_memory_handle = @as(types.VkDeviceMemory, @ptrFromInt(@as(usize, 0x5050)));
const fake_command_buffer = @as(types.VkCommandBuffer, @ptrFromInt(@as(usize, 0x6060)));

const TestCapture = struct {
    pub var create_image_calls: usize = 0;
    pub var destroy_image_calls: usize = 0;
    pub var create_buffer_calls: usize = 0;
    pub var destroy_buffer_calls: usize = 0;
    pub var bind_calls: usize = 0;
    pub var copy_calls: usize = 0;
    pub var barrier_calls: usize = 0;
    pub var last_copy: ?types.VkBufferImageCopy = null;
    pub var last_barrier: ?types.VkImageMemoryBarrier = null;
    pub var mapped_storage: [4096]u8 = [_]u8{0} ** 4096;

    pub fn reset() void {
        create_image_calls = 0;
        destroy_image_calls = 0;
        create_buffer_calls = 0;
        destroy_buffer_calls = 0;
        bind_calls = 0;
        copy_calls = 0;
        barrier_calls = 0;
        last_copy = null;
        last_barrier = null;
        std.mem.set(u8, mapped_storage[0..], 0);
    }
};

fn makeTestDevice(allocator: std.mem.Allocator) device_mod.Device {
    var device = device_mod.Device{
        .allocator = allocator,
        .loader = undefined,
        .dispatch = std.mem.zeroes(loader.DeviceDispatch),
        .handle = fake_device_handle,
        .allocation_callbacks = null,
    };

    device.dispatch.create_image = stubCreateImage;
    device.dispatch.destroy_image = stubDestroyImage;
    device.dispatch.get_image_memory_requirements = stubImageRequirements;
    device.dispatch.bind_image_memory = stubBindImageMemory;
    device.dispatch.create_image_view = stubCreateImageView;
    device.dispatch.destroy_image_view = stubDestroyImageView;

    device.dispatch.create_buffer = stubCreateBuffer;
    device.dispatch.destroy_buffer = stubDestroyBuffer;
    device.dispatch.get_buffer_memory_requirements = stubBufferRequirements;
    device.dispatch.bind_buffer_memory = stubBindBufferMemory;

    device.dispatch.allocate_memory = stubAllocateMemory;
    device.dispatch.free_memory = stubFreeMemory;
    device.dispatch.map_memory = stubMapMemory;
    device.dispatch.unmap_memory = stubUnmapMemory;
    device.dispatch.flush_mapped_memory_ranges = stubFlushMemory;
    device.dispatch.invalidate_mapped_memory_ranges = stubInvalidateMemory;

    device.dispatch.cmd_copy_buffer_to_image = stubCopyBufferToImage;
    device.dispatch.cmd_pipeline_barrier = stubPipelineBarrier;

    return device;
}

fn makeMemoryProps() types.VkPhysicalDeviceMemoryProperties {
    var props: types.VkPhysicalDeviceMemoryProperties = std.mem.zeroes(types.VkPhysicalDeviceMemoryProperties);
    props.memoryTypeCount = 2;
    props.memoryTypes[0] = .{ .propertyFlags = types.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, .heapIndex = 0 };
    props.memoryTypes[1] = .{ .propertyFlags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | types.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, .heapIndex = 1 };
    props.memoryHeapCount = 2;
    props.memoryHeaps[0] = .{ .size = 1024 * 1024 * 1024, .flags = types.VK_MEMORY_HEAP_DEVICE_LOCAL_BIT };
    props.memoryHeaps[1] = .{ .size = 256 * 1024 * 1024, .flags = 0 };
    return props;
}

fn stubCreateImage(_: types.VkDevice, _: *const types.VkImageCreateInfo, _: ?*const types.VkAllocationCallbacks, out_image: *types.VkImage) callconv(.C) types.VkResult {
    TestCapture.create_image_calls += 1;
    out_image.* = fake_image_handle;
    return .SUCCESS;
}

fn stubDestroyImage(_: types.VkDevice, _: types.VkImage, _: ?*const types.VkAllocationCallbacks) callconv(.C) void {
    TestCapture.destroy_image_calls += 1;
}

fn stubImageRequirements(_: types.VkDevice, _: types.VkImage, reqs: *types.VkMemoryRequirements) callconv(.C) void {
    reqs.* = types.VkMemoryRequirements{
        .size = 4096,
        .alignment = 256,
        .memoryTypeBits = 0b10,
    };
}

fn stubBindImageMemory(_: types.VkDevice, _: types.VkImage, _: types.VkDeviceMemory, _: types.VkDeviceSize) callconv(.C) types.VkResult {
    TestCapture.bind_calls += 1;
    return .SUCCESS;
}

fn stubCreateImageView(_: types.VkDevice, _: *const types.VkImageViewCreateInfo, _: ?*const types.VkAllocationCallbacks, out_view: *types.VkImageView) callconv(.C) types.VkResult {
    out_view.* = fake_image_view;
    return .SUCCESS;
}

fn stubDestroyImageView(_: types.VkDevice, _: types.VkImageView, _: ?*const types.VkAllocationCallbacks) callconv(.C) void {}

fn stubCreateBuffer(_: types.VkDevice, _: *const types.VkBufferCreateInfo, _: ?*const types.VkAllocationCallbacks, out_buffer: *types.VkBuffer) callconv(.C) types.VkResult {
    TestCapture.create_buffer_calls += 1;
    out_buffer.* = fake_buffer_handle;
    return .SUCCESS;
}

fn stubDestroyBuffer(_: types.VkDevice, _: types.VkBuffer, _: ?*const types.VkAllocationCallbacks) callconv(.C) void {
    TestCapture.destroy_buffer_calls += 1;
}

fn stubBufferRequirements(_: types.VkDevice, _: types.VkBuffer, reqs: *types.VkMemoryRequirements) callconv(.C) void {
    reqs.* = types.VkMemoryRequirements{
        .size = 256,
        .alignment = 64,
        .memoryTypeBits = 0b10,
    };
}

fn stubBindBufferMemory(_: types.VkDevice, _: types.VkBuffer, _: types.VkDeviceMemory, _: types.VkDeviceSize) callconv(.C) types.VkResult {
    TestCapture.bind_calls += 1;
    return .SUCCESS;
}

fn stubAllocateMemory(_: types.VkDevice, _: *const types.VkMemoryAllocateInfo, _: ?*const types.VkAllocationCallbacks, out_memory: *types.VkDeviceMemory) callconv(.C) types.VkResult {
    out_memory.* = fake_memory_handle;
    return .SUCCESS;
}

fn stubFreeMemory(_: types.VkDevice, _: types.VkDeviceMemory, _: ?*const types.VkAllocationCallbacks) callconv(.C) void {}

fn stubMapMemory(_: types.VkDevice, _: types.VkDeviceMemory, _: types.VkDeviceSize, _: types.VkDeviceSize, _: types.VkMemoryMapFlags, data: *?*anyopaque) callconv(.C) types.VkResult {
    data.* = @as(*anyopaque, @ptrCast(&TestCapture.mapped_storage));
    return .SUCCESS;
}

fn stubUnmapMemory(_: types.VkDevice, _: types.VkDeviceMemory) callconv(.C) void {}

fn stubFlushMemory(_: types.VkDevice, _: u32, _: [*]const types.VkMappedMemoryRange) callconv(.C) types.VkResult {
    return .SUCCESS;
}

fn stubInvalidateMemory(_: types.VkDevice, _: u32, _: [*]const types.VkMappedMemoryRange) callconv(.C) types.VkResult {
    return .SUCCESS;
}

fn stubCopyBufferToImage(_: types.VkCommandBuffer, _: types.VkBuffer, _: types.VkImage, _: types.VkImageLayout, _: u32, regions: ?[*]const types.VkBufferImageCopy) callconv(.C) void {
    TestCapture.copy_calls += 1;
    if (regions) |ptr| {
        TestCapture.last_copy = ptr[0];
    }
}

fn stubPipelineBarrier(_: types.VkCommandBuffer, _: types.VkPipelineStageFlags, _: types.VkPipelineStageFlags, _: types.VkDependencyFlags, _: u32, _: ?[*]const types.VkMemoryBarrier, _: u32, _: ?[*]const types.VkBufferMemoryBarrier, count: u32, barriers: ?[*]const types.VkImageMemoryBarrier) callconv(.C) void {
    TestCapture.barrier_calls += 1;
    if (count > 0 and barriers != null) {
        TestCapture.last_barrier = barriers.?[0];
    }
}
