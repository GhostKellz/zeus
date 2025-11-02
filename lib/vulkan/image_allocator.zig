//! Image allocator with automatic memory binding and layout tracking

const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const image_mod = @import("image.zig");
const allocator_mod = @import("allocator.zig");

const log = std.log.scoped(.image_allocator);

/// Image allocation options
pub const ImageAllocOptions = struct {
    width: u32,
    height: u32,
    depth: u32 = 1,
    mip_levels: u32 = 1,
    array_layers: u32 = 1,
    format: types.VkFormat,
    tiling: types.VkImageTiling = .OPTIMAL,
    usage: types.VkImageUsageFlags,
    initial_layout: types.VkImageLayout = .UNDEFINED,
    memory_usage: allocator_mod.MemoryUsage = .gpu_only,
    flags: allocator_mod.AllocationFlags = .{},
    image_type: types.VkImageType = .@"2D",
    samples: types.VkSampleCountFlagBits = .@"1",
    sharing_mode: types.VkSharingMode = .EXCLUSIVE,
    name: ?[:0]const u8 = null,
};

/// Managed image with automatic memory management and layout tracking
pub const AllocatedImage = struct {
    device: *device_mod.Device,
    allocator: *allocator_mod.Allocator,
    image: types.VkImage,
    allocation: allocator_mod.AllocationHandle,
    current_layout: types.VkImageLayout,
    extent: types.VkExtent3D,
    format: types.VkFormat,
    mip_levels: u32,
    array_layers: u32,
    usage: types.VkImageUsageFlags,

    pub fn deinit(self: *AllocatedImage) void {
        image_mod.destroyImage(self.device, self.image);
        self.allocation.free();
    }

    /// Get VkDeviceMemory for binding
    pub fn getMemory(self: *AllocatedImage) types.VkDeviceMemory {
        return self.allocation.getMemory();
    }

    /// Get memory offset for binding
    pub fn getOffset(self: *AllocatedImage) types.VkDeviceSize {
        return self.allocation.getOffset();
    }

    /// Update tracked layout (call after layout transitions)
    pub fn setLayout(self: *AllocatedImage, new_layout: types.VkImageLayout) void {
        self.current_layout = new_layout;
    }

    /// Get current tracked layout
    pub fn getLayout(self: *AllocatedImage) types.VkImageLayout {
        return self.current_layout;
    }

    /// Create image view for this image
    pub fn createView(
        self: *AllocatedImage,
        view_type: types.VkImageViewType,
        aspect_mask: types.VkImageAspectFlags,
    ) !types.VkImageView {
        return image_mod.createImageView(
            self.device,
            self.image,
            view_type,
            self.format,
            aspect_mask,
            self.mip_levels,
            self.array_layers,
        );
    }

    /// Create default 2D image view
    pub fn createDefaultView(self: *AllocatedImage) !types.VkImageView {
        const aspect = if (isDepthFormat(self.format))
            types.VK_IMAGE_ASPECT_DEPTH_BIT
        else
            types.VK_IMAGE_ASPECT_COLOR_BIT;

        return self.createView(.@"2D", aspect);
    }
};

/// Image allocator managing textures and render targets
pub const ImageAllocator = struct {
    device: *device_mod.Device,
    allocator: *allocator_mod.Allocator,

    pub fn init(device: *device_mod.Device, allocator: *allocator_mod.Allocator) ImageAllocator {
        return .{
            .device = device,
            .allocator = allocator,
        };
    }

    /// Create image with automatic memory allocation and binding
    pub fn createImage(self: *ImageAllocator, options: ImageAllocOptions) !AllocatedImage {
        const device_handle = self.device.handle orelse return errors.Error.DeviceCreationFailed;

        // Create image
        const extent = types.VkExtent3D{
            .width = options.width,
            .height = options.height,
            .depth = options.depth,
        };

        const create_info = types.VkImageCreateInfo{
            .imageType = options.image_type,
            .format = options.format,
            .extent = extent,
            .mipLevels = options.mip_levels,
            .arrayLayers = options.array_layers,
            .samples = options.samples,
            .tiling = options.tiling,
            .usage = options.usage,
            .sharingMode = options.sharing_mode,
            .initialLayout = options.initial_layout,
            .flags = 0,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
        };

        var image: types.VkImage = undefined;
        try errors.ensureSuccess(self.device.dispatch.create_image(device_handle, &create_info, self.device.allocation_callbacks, &image));
        errdefer image_mod.destroyImage(self.device, image);

        // Get memory requirements
        var requirements: types.VkMemoryRequirements = undefined;
        self.device.dispatch.get_image_memory_requirements(device_handle, image, &requirements);

        // Allocate memory
        const allocation = try self.allocator.allocateMemory(requirements, options.memory_usage, options.flags);
        errdefer allocation.free();

        // Bind image to memory
        try errors.ensureSuccess(self.device.dispatch.bind_image_memory(
            device_handle,
            image,
            allocation.getMemory(),
            allocation.getOffset(),
        ));

        log.debug("Created image: {}x{}x{}, mips={}, format={s}, usage=0x{x}", .{
            options.width,
            options.height,
            options.depth,
            options.mip_levels,
            @tagName(options.format),
            options.usage,
        });

        return AllocatedImage{
            .device = self.device,
            .allocator = self.allocator,
            .image = image,
            .allocation = allocation,
            .current_layout = options.initial_layout,
            .extent = extent,
            .format = options.format,
            .mip_levels = options.mip_levels,
            .array_layers = options.array_layers,
            .usage = options.usage,
        };
    }

    /// Create 2D texture optimized for sampling
    pub fn createTexture2D(
        self: *ImageAllocator,
        width: u32,
        height: u32,
        format: types.VkFormat,
        mip_levels: u32,
    ) !AllocatedImage {
        return self.createImage(.{
            .width = width,
            .height = height,
            .format = format,
            .mip_levels = mip_levels,
            .usage = types.VK_IMAGE_USAGE_TRANSFER_DST_BIT |
                types.VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
                types.VK_IMAGE_USAGE_SAMPLED_BIT,
            .memory_usage = .gpu_only,
        });
    }

    /// Create render target (color attachment)
    pub fn createRenderTarget(
        self: *ImageAllocator,
        width: u32,
        height: u32,
        format: types.VkFormat,
    ) !AllocatedImage {
        return self.createImage(.{
            .width = width,
            .height = height,
            .format = format,
            .usage = types.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
                types.VK_IMAGE_USAGE_SAMPLED_BIT |
                types.VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
            .memory_usage = .gpu_only,
        });
    }

    /// Create depth/stencil buffer
    pub fn createDepthBuffer(
        self: *ImageAllocator,
        width: u32,
        height: u32,
        format: types.VkFormat,
    ) !AllocatedImage {
        return self.createImage(.{
            .width = width,
            .height = height,
            .format = format,
            .usage = types.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
            .memory_usage = .gpu_only,
            .initial_layout = .UNDEFINED,
        });
    }

    /// Create storage image (compute shader read/write)
    pub fn createStorageImage(
        self: *ImageAllocator,
        width: u32,
        height: u32,
        format: types.VkFormat,
    ) !AllocatedImage {
        return self.createImage(.{
            .width = width,
            .height = height,
            .format = format,
            .usage = types.VK_IMAGE_USAGE_STORAGE_BIT |
                types.VK_IMAGE_USAGE_SAMPLED_BIT |
                types.VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
            .memory_usage = .gpu_only,
        });
    }

    /// Create staging image (CPU-accessible, linear tiling)
    pub fn createStagingImage(
        self: *ImageAllocator,
        width: u32,
        height: u32,
        format: types.VkFormat,
    ) !AllocatedImage {
        return self.createImage(.{
            .width = width,
            .height = height,
            .format = format,
            .tiling = .LINEAR,
            .usage = types.VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
            .memory_usage = .cpu_to_gpu,
            .flags = .{ .mapped = true },
            .initial_layout = .PREINITIALIZED,
        });
    }
};

/// Check if format is a depth format
fn isDepthFormat(format: types.VkFormat) bool {
    return switch (format) {
        .D16_UNORM,
        .D32_SFLOAT,
        .D16_UNORM_S8_UINT,
        .D24_UNORM_S8_UINT,
        .D32_SFLOAT_S8_UINT,
        => true,
        else => false,
    };
}
