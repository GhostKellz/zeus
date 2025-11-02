//! Wayland DMA-BUF support for zero-copy composition

const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const instance_mod = @import("instance.zig");
const image_allocator = @import("image_allocator.zig");

const log = std.log.scoped(.dmabuf_support);

/// DMA-BUF plane information
pub const DmaBufPlane = struct {
    fd: i32,
    offset: u32,
    stride: u32,
    modifier: u64,
};

/// DMA-BUF image descriptor
pub const DmaBufImageInfo = struct {
    width: u32,
    height: u32,
    format: u32, // DRM fourcc format
    num_planes: u32,
    planes: [4]DmaBufPlane,

    pub fn init(width: u32, height: u32, format: u32) DmaBufImageInfo {
        return .{
            .width = width,
            .height = height,
            .format = format,
            .num_planes = 0,
            .planes = undefined,
        };
    }

    pub fn addPlane(self: *DmaBufImageInfo, fd: i32, offset: u32, stride: u32, modifier: u64) void {
        if (self.num_planes >= 4) return;
        self.planes[self.num_planes] = .{
            .fd = fd,
            .offset = offset,
            .stride = stride,
            .modifier = modifier,
        };
        self.num_planes += 1;
    }
};

/// DRM format modifier properties
pub const DrmFormatModifier = struct {
    modifier: u64,
    plane_count: u32,
    format_features: types.VkFormatFeatureFlags,

    /// Linear (no tiling)
    pub const LINEAR: u64 = 0x0;

    /// Intel X-tiled
    pub const INTEL_X_TILED: u64 = 0x0100000000000001;

    /// Intel Y-tiled
    pub const INTEL_Y_TILED: u64 = 0x0100000000000002;

    /// AMD GFX9+ tiling
    pub const AMD_GFX9_64K_S: u64 = 0x0200000000000001;
};

/// DMA-BUF capability detection
pub const DmaBufSupport = struct {
    allocator: std.mem.Allocator,
    instance: *instance_mod.Instance,
    device: *device_mod.Device,
    has_external_memory_fd: bool,
    has_external_memory_dmabuf: bool,
    has_image_drm_format_modifier: bool,
    supported_modifiers: std.ArrayList(DrmFormatModifier),

    pub fn init(
        allocator: std.mem.Allocator,
        instance: *instance_mod.Instance,
        device: *device_mod.Device,
    ) !*DmaBufSupport {
        const self = try allocator.create(DmaBufSupport);
        self.* = .{
            .allocator = allocator,
            .instance = instance,
            .device = device,
            .has_external_memory_fd = false,
            .has_external_memory_dmabuf = false,
            .has_image_drm_format_modifier = false,
            .supported_modifiers = std.ArrayList(DrmFormatModifier).init(allocator),
        };

        try self.detectCapabilities();

        return self;
    }

    pub fn deinit(self: *DmaBufSupport) void {
        self.supported_modifiers.deinit();
        self.allocator.destroy(self);
    }

    /// Detect DMA-BUF capabilities
    fn detectCapabilities(self: *DmaBufSupport) !void {
        // Check for VK_KHR_external_memory_fd
        self.has_external_memory_fd = self.device.hasExtension("VK_KHR_external_memory_fd");

        // Check for VK_EXT_external_memory_dma_buf
        self.has_external_memory_dmabuf = self.device.hasExtension("VK_EXT_external_memory_dma_buf");

        // Check for VK_EXT_image_drm_format_modifier
        self.has_image_drm_format_modifier = self.device.hasExtension("VK_EXT_image_drm_format_modifier");

        log.info("DMA-BUF capabilities: fd={}, dmabuf={}, drm_modifier={}", .{
            self.has_external_memory_fd,
            self.has_external_memory_dmabuf,
            self.has_image_drm_format_modifier,
        });
    }

    /// Check if DMA-BUF is fully supported
    pub fn isSupported(self: *DmaBufSupport) bool {
        return self.has_external_memory_fd and self.has_external_memory_dmabuf;
    }

    /// Query supported DRM format modifiers for a format
    pub fn queryFormatModifiers(
        self: *DmaBufSupport,
        physical_device: types.VkPhysicalDevice,
        format: types.VkFormat,
    ) ![]DrmFormatModifier {
        if (!self.has_image_drm_format_modifier) {
            return &[_]DrmFormatModifier{};
        }

        self.supported_modifiers.clearRetainingCapacity();

        // Query DRM format properties
        var drm_properties = types.VkDrmFormatModifierPropertiesListEXT{
            .sType = .DRM_FORMAT_MODIFIER_PROPERTIES_LIST_EXT,
            .pNext = null,
            .drmFormatModifierCount = 0,
            .pDrmFormatModifierProperties = null,
        };

        var format_properties = types.VkFormatProperties2{
            .sType = .FORMAT_PROPERTIES_2,
            .pNext = &drm_properties,
            .formatProperties = undefined,
        };

        self.instance.dispatch.get_physical_device_format_properties_2(
            physical_device,
            format,
            &format_properties,
        );

        if (drm_properties.drmFormatModifierCount == 0) {
            return &[_]DrmFormatModifier{};
        }

        // Allocate and query modifier properties
        const modifier_properties = try self.allocator.alloc(
            types.VkDrmFormatModifierPropertiesEXT,
            drm_properties.drmFormatModifierCount,
        );
        defer self.allocator.free(modifier_properties);

        drm_properties.pDrmFormatModifierProperties = modifier_properties.ptr;
        self.instance.dispatch.get_physical_device_format_properties_2(
            physical_device,
            format,
            &format_properties,
        );

        // Convert to our format
        for (modifier_properties) |prop| {
            try self.supported_modifiers.append(.{
                .modifier = prop.drmFormatModifier,
                .plane_count = prop.drmFormatModifierPlaneCount,
                .format_features = prop.drmFormatModifierTilingFeatures,
            });
        }

        log.debug("Found {} DRM format modifiers for format {}", .{
            self.supported_modifiers.items.len,
            format,
        });

        return self.supported_modifiers.items;
    }

    /// Check if a specific modifier is supported
    pub fn supportsModifier(self: *DmaBufSupport, modifier: u64) bool {
        for (self.supported_modifiers.items) |mod| {
            if (mod.modifier == modifier) {
                return true;
            }
        }
        return false;
    }
};

/// DMA-BUF image import/export
pub const DmaBufImage = struct {
    device: *device_mod.Device,
    image: types.VkImage,
    memory: types.VkDeviceMemory,
    fd: i32,
    owned_fd: bool,

    /// Import DMA-BUF as Vulkan image
    pub fn importDmaBuf(
        device: *device_mod.Device,
        info: DmaBufImageInfo,
        vk_format: types.VkFormat,
        usage: types.VkImageUsageFlags,
    ) !*DmaBufImage {
        const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;

        // Create external memory image info
        var external_memory_info = types.VkExternalMemoryImageCreateInfo{
            .sType = .EXTERNAL_MEMORY_IMAGE_CREATE_INFO,
            .pNext = null,
            .handleTypes = types.VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT,
        };

        // Create image
        const image_info = types.VkImageCreateInfo{
            .sType = .IMAGE_CREATE_INFO,
            .pNext = &external_memory_info,
            .flags = 0,
            .imageType = .@"2D",
            .format = vk_format,
            .extent = .{
                .width = info.width,
                .height = info.height,
                .depth = 1,
            },
            .mipLevels = 1,
            .arrayLayers = 1,
            .samples = .@"1",
            .tiling = .DRM_FORMAT_MODIFIER_EXT,
            .usage = usage,
            .sharingMode = .EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
            .initialLayout = .UNDEFINED,
        };

        var image: types.VkImage = undefined;
        try errors.ensureSuccess(device.dispatch.create_image(
            device_handle,
            &image_info,
            device.allocation_callbacks,
            &image,
        ));
        errdefer device.dispatch.destroy_image(device_handle, image, device.allocation_callbacks);

        // Get memory requirements
        var memory_requirements: types.VkMemoryRequirements = undefined;
        device.dispatch.get_image_memory_requirements(device_handle, image, &memory_requirements);

        // Import DMA-BUF FD
        var import_fd_info = types.VkImportMemoryFdInfoKHR{
            .sType = .IMPORT_MEMORY_FD_INFO_KHR,
            .pNext = null,
            .handleType = .DMA_BUF_BIT_EXT,
            .fd = info.planes[0].fd,
        };

        const alloc_info = types.VkMemoryAllocateInfo{
            .sType = .MEMORY_ALLOCATE_INFO,
            .pNext = &import_fd_info,
            .allocationSize = memory_requirements.size,
            .memoryTypeIndex = 0, // Need to find appropriate memory type
        };

        var memory: types.VkDeviceMemory = undefined;
        try errors.ensureSuccess(device.dispatch.allocate_memory(
            device_handle,
            &alloc_info,
            device.allocation_callbacks,
            &memory,
        ));
        errdefer device.dispatch.free_memory(device_handle, memory, device.allocation_callbacks);

        // Bind memory to image
        try errors.ensureSuccess(device.dispatch.bind_image_memory(
            device_handle,
            image,
            memory,
            0,
        ));

        const self = try device.allocator.create(DmaBufImage);
        self.* = .{
            .device = device,
            .image = image,
            .memory = memory,
            .fd = info.planes[0].fd,
            .owned_fd = false,
        };

        log.debug("Imported DMA-BUF image {}x{}", .{ info.width, info.height });

        return self;
    }

    /// Export Vulkan image as DMA-BUF
    pub fn exportDmaBuf(
        device: *device_mod.Device,
        image: types.VkImage,
    ) !*DmaBufImage {
        const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;

        // Get memory requirements
        var memory_requirements: types.VkMemoryRequirements = undefined;
        device.dispatch.get_image_memory_requirements(device_handle, image, &memory_requirements);

        // Allocate exportable memory
        var export_info = types.VkExportMemoryAllocateInfo{
            .sType = .EXPORT_MEMORY_ALLOCATE_INFO,
            .pNext = null,
            .handleTypes = types.VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT,
        };

        const alloc_info = types.VkMemoryAllocateInfo{
            .sType = .MEMORY_ALLOCATE_INFO,
            .pNext = &export_info,
            .allocationSize = memory_requirements.size,
            .memoryTypeIndex = 0, // Need to find appropriate memory type
        };

        var memory: types.VkDeviceMemory = undefined;
        try errors.ensureSuccess(device.dispatch.allocate_memory(
            device_handle,
            &alloc_info,
            device.allocation_callbacks,
            &memory,
        ));
        errdefer device.dispatch.free_memory(device_handle, memory, device.allocation_callbacks);

        // Bind memory to image
        try errors.ensureSuccess(device.dispatch.bind_image_memory(
            device_handle,
            image,
            memory,
            0,
        ));

        // Get FD
        const get_fd_info = types.VkMemoryGetFdInfoKHR{
            .sType = .MEMORY_GET_FD_INFO_KHR,
            .pNext = null,
            .memory = memory,
            .handleType = .DMA_BUF_BIT_EXT,
        };

        var fd: i32 = undefined;
        try errors.ensureSuccess(device.dispatch.get_memory_fd_khr(
            device_handle,
            &get_fd_info,
            &fd,
        ));

        const self = try device.allocator.create(DmaBufImage);
        self.* = .{
            .device = device,
            .image = image,
            .memory = memory,
            .fd = fd,
            .owned_fd = true,
        };

        log.debug("Exported image as DMA-BUF (fd={})", .{fd});

        return self;
    }

    /// Destroy DMA-BUF image
    pub fn destroy(self: *DmaBufImage) void {
        const device_handle = self.device.handle orelse return;

        self.device.dispatch.destroy_image(device_handle, self.image, self.device.allocation_callbacks);
        self.device.dispatch.free_memory(device_handle, self.memory, self.device.allocation_callbacks);

        if (self.owned_fd) {
            _ = std.posix.close(self.fd);
        }

        self.device.allocator.destroy(self);
    }
};

/// Wayland compositor integration hints
pub const WaylandHints = struct {
    /// KDE Plasma Wayland quirks
    pub const plasma = struct {
        /// Prefer explicit sync when available
        pub const prefer_explicit_sync = true;

        /// Use mailbox for smooth composition
        pub const prefer_mailbox = true;

        /// Enable zero-copy path
        pub const enable_zero_copy = true;
    };

    /// GNOME Mutter quirks
    pub const mutter = struct {
        pub const prefer_explicit_sync = false;
        pub const prefer_mailbox = false;
        pub const enable_zero_copy = true;
    };

    /// Sway/wlroots quirks
    pub const wlroots = struct {
        pub const prefer_explicit_sync = true;
        pub const prefer_mailbox = true;
        pub const enable_zero_copy = true;
    };
};
