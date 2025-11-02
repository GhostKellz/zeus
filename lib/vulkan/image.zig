const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const loader = @import("loader.zig");
const memory = @import("memory.zig");
const buffer = @import("buffer.zig");

pub const ImageCreateOptions = struct {
    type: types.VkImageType = .@"2D",
    format: types.VkFormat,
    extent: types.VkExtent3D,
    usage: types.VkImageUsageFlags,
    mip_levels: u32 = 1,
    array_layers: u32 = 1,
    samples: types.VkSampleCountFlagBits = types.VK_SAMPLE_COUNT_1_BIT,
    tiling: types.VkImageTiling = .OPTIMAL,
    flags: types.VkImageCreateFlags = 0,
    sharing_mode: types.VkSharingMode = .EXCLUSIVE,
    queue_family_indices: []const u32 = &.{},
    initial_layout: types.VkImageLayout = .UNDEFINED,
};

pub fn createImage(device: *device_mod.Device, options: ImageCreateOptions) errors.Error!types.VkImage {
    const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;

    var queue_indices_ptr: ?[*]const u32 = null;
    if (options.queue_family_indices.len > 0) {
        queue_indices_ptr = options.queue_family_indices.ptr;
    }

    var create_info = types.VkImageCreateInfo{
        .flags = options.flags,
        .imageType = options.type,
        .format = options.format,
        .extent = options.extent,
        .mipLevels = options.mip_levels,
        .arrayLayers = options.array_layers,
        .samples = options.samples,
        .tiling = options.tiling,
        .usage = options.usage,
        .sharingMode = options.sharing_mode,
        .queueFamilyIndexCount = @intCast(options.queue_family_indices.len),
        .pQueueFamilyIndices = queue_indices_ptr,
        .initialLayout = options.initial_layout,
    };

    var image: types.VkImage = undefined;
    try errors.ensureSuccess(device.dispatch.create_image(device_handle, &create_info, device.allocation_callbacks, &image));
    return image;
}

pub const ManagedImage = struct {
    device: *device_mod.Device,
    image: types.VkImage,
    allocation: memory.Allocation,
    view: ?types.VkImageView,
    extent: types.VkExtent3D,
    format: types.VkFormat,
    mip_levels: u32,
    array_layers: u32,
    usage: types.VkImageUsageFlags,
    aspect_mask: types.VkImageAspectFlags,
    memory_type_index: u32,
    memory_flags: types.VkMemoryPropertyFlags,
    current_layout: types.VkImageLayout,

    pub fn deinit(self: *ManagedImage) void {
        self.destroyView();
        const device_handle = self.device.handle orelse return;
        self.device.dispatch.destroy_image(device_handle, self.image, self.device.allocation_callbacks);
        self.allocation.destroy();
        self.image = @ptrFromInt(@as(usize, 0));
    }

    fn destroyView(self: *ManagedImage) void {
        if (self.view) |view_handle| {
            const device_handle = self.device.handle orelse return;
            self.device.dispatch.destroy_image_view(device_handle, view_handle, self.device.allocation_callbacks);
            self.view = null;
        }
    }

    pub fn createView(self: *ManagedImage, view_type: types.VkImageViewType, format: ?types.VkFormat, aspect_mask: ?types.VkImageAspectFlags) errors.Error!types.VkImageView {
        self.destroyView();
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;
        const used_format = format orelse self.format;
        const used_aspect = aspect_mask orelse self.aspect_mask;
        const subresource = types.VkImageSubresourceRange{
            .aspectMask = used_aspect,
            .baseMipLevel = 0,
            .levelCount = self.mip_levels,
            .baseArrayLayer = 0,
            .layerCount = self.array_layers,
        };
        const create_info = types.VkImageViewCreateInfo{
            .image = self.image,
            .viewType = view_type,
            .format = used_format,
            .subresourceRange = subresource,
        };
        var view: types.VkImageView = undefined;
        try errors.ensureSuccess(self.device.dispatch.create_image_view(device_handle, &create_info, self.device.allocation_callbacks, &view));
        self.view = view;
        return view;
    }

    pub fn ensureLayout(self: *ManagedImage, cmd: types.VkCommandBuffer, new_layout: types.VkImageLayout, options: buffer.TransitionOptions) errors.Error!void {
        if (self.current_layout == new_layout) return;
        var transition_options = options;
        transition_options.device = self.device;
        transition_options.range = options.range orelse types.VkImageSubresourceRange{
            .aspectMask = self.aspect_mask,
            .baseMipLevel = 0,
            .levelCount = self.mip_levels,
            .baseArrayLayer = 0,
            .layerCount = self.array_layers,
        };
        try buffer.transitionImageLayout(cmd, self.image, self.current_layout, new_layout, transition_options);
        self.current_layout = new_layout;
    }
};

pub const ManagedImageOptions = struct {
    image: ImageCreateOptions,
    filter: memory.MemoryTypeFilter = .{},
    aspect_mask: types.VkImageAspectFlags = types.VK_IMAGE_ASPECT_COLOR_BIT,
    view_type: ?types.VkImageViewType = .@"2D",
    view_format: ?types.VkFormat = null,
};

pub fn createManagedImage(
    device: *device_mod.Device,
    memory_props: types.VkPhysicalDeviceMemoryProperties,
    options: ManagedImageOptions,
) errors.Error!ManagedImage {
    const image = try createImage(device, options.image);
    errdefer {
        destroyImageOnly(device, image);
    }

    const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;
    var requirements: types.VkMemoryRequirements = undefined;
    device.dispatch.get_image_memory_requirements(device_handle, image, &requirements);

    const type_index = try memory.findMemoryTypeIndex(memory_props, requirements, options.filter);
    var allocation = try memory.allocate(device, requirements, type_index);
    errdefer allocation.destroy();

    try errors.ensureSuccess(device.dispatch.bind_image_memory(device_handle, image, allocation.memory.?, 0));
    const flags = memory_props.memoryTypes[type_index].propertyFlags;

    var managed = ManagedImage{
        .device = device,
        .image = image,
        .allocation = allocation,
        .view = null,
        .extent = options.image.extent,
        .format = options.image.format,
        .mip_levels = options.image.mip_levels,
        .array_layers = options.image.array_layers,
        .usage = options.image.usage,
        .aspect_mask = options.aspect_mask,
        .memory_type_index = type_index,
        .memory_flags = flags,
        .current_layout = options.image.initial_layout,
    };

    if (options.view_type) |view_type| {
        try managed.createView(view_type, options.view_format, options.aspect_mask);
    }

    return managed;
}

fn destroyImageOnly(device: *device_mod.Device, image: types.VkImage) void {
    const device_handle = device.handle orelse return;
    device.dispatch.destroy_image(device_handle, image, device.allocation_callbacks);
}

// Test support and stubs ----------------------------------------------------

const fake_image_handle = @as(types.VkImage, @ptrFromInt(@as(usize, 0xAAA)));
const fake_image_view = @as(types.VkImageView, @ptrFromInt(@as(usize, 0xBBB)));

const Capture = struct {
    pub var create_info: ?types.VkImageCreateInfo = null;
    pub var view_info: ?types.VkImageViewCreateInfo = null;
    pub var destroy_image_called: usize = 0;
    pub var destroy_view_called: usize = 0;
    pub var bind_calls: usize = 0;
    pub var last_barrier: ?types.VkImageMemoryBarrier = null;
    pub var last_src_stage: types.VkPipelineStageFlags = 0;
    pub var last_dst_stage: types.VkPipelineStageFlags = 0;

    pub fn reset() void {
        create_info = null;
        view_info = null;
        destroy_image_called = 0;
        destroy_view_called = 0;
        bind_calls = 0;
        last_barrier = null;
        last_src_stage = 0;
        last_dst_stage = 0;
    }

    pub fn stubCreateImage(_: types.VkDevice, info: *const types.VkImageCreateInfo, _: ?*const types.VkAllocationCallbacks, image: *types.VkImage) callconv(.c) types.VkResult {
        create_info = info.*;
        image.* = fake_image_handle;
        return .SUCCESS;
    }

    pub fn stubDestroyImage(_: types.VkDevice, _: types.VkImage, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {
        destroy_image_called += 1;
    }

    pub fn stubGetImageRequirements(_: types.VkDevice, _: types.VkImage, reqs: *types.VkMemoryRequirements) callconv(.c) void {
        reqs.* = types.VkMemoryRequirements{
            .size = 8192,
            .alignment = 256,
            .memoryTypeBits = 0b10,
        };
    }

    pub fn stubBindImageMemory(_: types.VkDevice, _: types.VkImage, _: types.VkDeviceMemory, _: types.VkDeviceSize) callconv(.c) types.VkResult {
        bind_calls += 1;
        return .SUCCESS;
    }

    pub fn stubCreateImageView(_: types.VkDevice, info: *const types.VkImageViewCreateInfo, _: ?*const types.VkAllocationCallbacks, view: *types.VkImageView) callconv(.c) types.VkResult {
        view_info = info.*;
        view.* = fake_image_view;
        return .SUCCESS;
    }

    pub fn stubDestroyImageView(_: types.VkDevice, _: types.VkImageView, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {
        destroy_view_called += 1;
    }

    pub fn stubPipelineBarrier(_: types.VkCommandBuffer, src_stage: types.VkPipelineStageFlags, dst_stage: types.VkPipelineStageFlags, _: types.VkDependencyFlags, _: u32, _: ?[*]const types.VkMemoryBarrier, _: u32, _: ?[*]const types.VkBufferMemoryBarrier, count: u32, barriers: ?[*]const types.VkImageMemoryBarrier) callconv(.c) void {
        std.debug.assert(count == 1);
        last_barrier = barriers.?[0];
        last_src_stage = src_stage;
        last_dst_stage = dst_stage;
    }
};

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

fn memoryStubAllocate(_: types.VkDevice, info: *const types.VkMemoryAllocateInfo, _: ?*const types.VkAllocationCallbacks, out_memory: *types.VkDeviceMemory) callconv(.c) types.VkResult {
    _ = info;
    out_memory.* = @as(types.VkDeviceMemory, @ptrFromInt(@as(usize, 0x900)));
    return .SUCCESS;
}

fn memoryStubFree(_: types.VkDevice, _: types.VkDeviceMemory, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {}

fn makeFakeDevice() device_mod.Device {
    var device = device_mod.Device{
        .allocator = std.testing.allocator,
        .loader = undefined,
        .dispatch = std.mem.zeroes(loader.DeviceDispatch),
        .handle = @as(types.VkDevice, @ptrFromInt(@as(usize, 0x10))),
        .allocation_callbacks = null,
    };

    device.dispatch.create_image = Capture.stubCreateImage;
    device.dispatch.destroy_image = Capture.stubDestroyImage;
    device.dispatch.get_image_memory_requirements = Capture.stubGetImageRequirements;
    device.dispatch.bind_image_memory = Capture.stubBindImageMemory;
    device.dispatch.create_image_view = Capture.stubCreateImageView;
    device.dispatch.destroy_image_view = Capture.stubDestroyImageView;
    device.dispatch.allocate_memory = memoryStubAllocate;
    device.dispatch.free_memory = memoryStubFree;
    device.dispatch.map_memory = memoryStubMap;
    device.dispatch.unmap_memory = memoryStubUnmap;
    device.dispatch.flush_mapped_memory_ranges = memoryStubFlush;
    device.dispatch.invalidate_mapped_memory_ranges = memoryStubInvalidate;
    device.dispatch.cmd_pipeline_barrier = Capture.stubPipelineBarrier;

    return device;
}

fn memoryStubMap(_: types.VkDevice, _: types.VkDeviceMemory, _: types.VkDeviceSize, _: types.VkDeviceSize, _: types.VkMemoryMapFlags, _: *?*anyopaque) callconv(.c) types.VkResult {
    return .SUCCESS;
}

fn memoryStubUnmap(_: types.VkDevice, _: types.VkDeviceMemory) callconv(.c) void {}

fn memoryStubFlush(_: types.VkDevice, _: u32, _: [*]const types.VkMappedMemoryRange) callconv(.c) types.VkResult {
    return .SUCCESS;
}

fn memoryStubInvalidate(_: types.VkDevice, _: u32, _: [*]const types.VkMappedMemoryRange) callconv(.c) types.VkResult {
    return .SUCCESS;
}

fn makeExtent(width: u32, height: u32, depth: u32) types.VkExtent3D {
    return types.VkExtent3D{ .width = width, .height = height, .depth = depth };
}

test "createManagedImage allocates and binds memory" {
    Capture.reset();
    var device = makeFakeDevice();
    const managed = try createManagedImage(&device, makeMemoryProps(), .{
        .image = .{
            .format = .R8G8B8A8_UNORM,
            .extent = makeExtent(256, 256, 1),
            .usage = types.VK_IMAGE_USAGE_TRANSFER_DST_BIT | types.VK_IMAGE_USAGE_SAMPLED_BIT,
        },
        .filter = .{
            .required_flags = types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT,
        },
    });
    defer managed.deinit();

    try std.testing.expectEqual(fake_image_handle, managed.image);
    const info = Capture.create_info orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(types.VK_IMAGE_USAGE_TRANSFER_DST_BIT | types.VK_IMAGE_USAGE_SAMPLED_BIT, info.usage);
    try std.testing.expectEqual(@as(u32, 1), info.extent.depth);
    try std.testing.expectEqual(@as(u32, 1), managed.mip_levels);
    try std.testing.expectEqual(@as(usize, 1), Capture.bind_calls);
}

test "ManagedImage.createView stores handle" {
    Capture.reset();
    var device = makeFakeDevice();
    var managed = try createManagedImage(&device, makeMemoryProps(), .{
        .image = .{
            .format = .R8G8B8A8_UNORM,
            .extent = makeExtent(512, 512, 1),
            .usage = types.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        },
        .aspect_mask = types.VK_IMAGE_ASPECT_COLOR_BIT,
    });
    defer managed.deinit();

    try std.testing.expectEqual(fake_image_view, managed.view.?);
    try std.testing.expectEqual(@as(usize, 1), Capture.destroy_view_called);
    try managed.createView(.@"2D", null, null);
    try std.testing.expectEqual(fake_image_view, managed.view.?);
    try std.testing.expectEqual(@as(usize, 2), Capture.destroy_view_called);
}

test "ManagedImage.ensureLayout transitions" {
    Capture.reset();
    var device = makeFakeDevice();
    var managed = try createManagedImage(&device, makeMemoryProps(), .{
        .image = .{
            .format = .R8G8B8A8_UNORM,
            .extent = makeExtent(128, 128, 1),
            .usage = types.VK_IMAGE_USAGE_TRANSFER_DST_BIT | types.VK_IMAGE_USAGE_SAMPLED_BIT,
        },
        .aspect_mask = types.VK_IMAGE_ASPECT_COLOR_BIT,
    });
    defer managed.deinit();

    const cmd = @as(types.VkCommandBuffer, @ptrFromInt(@as(usize, 0x55)));
    try managed.ensureLayout(cmd, .TRANSFER_DST_OPTIMAL, .{ .range = null });
    try std.testing.expectEqual(types.VkImageLayout.TRANSFER_DST_OPTIMAL, managed.current_layout);
    try std.testing.expect(Capture.last_barrier != null);
    const barrier = Capture.last_barrier.?;
    try std.testing.expectEqual(types.VkImageLayout.UNDEFINED, barrier.oldLayout);
    try std.testing.expectEqual(types.VkImageLayout.TRANSFER_DST_OPTIMAL, barrier.newLayout);
}
