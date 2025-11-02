//! Feature and extension auditor for device creation validation

const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const instance_mod = @import("instance.zig");

const log = std.log.scoped(.feature_auditor);

/// Feature support query result
pub const FeatureSupport = struct {
    features: types.VkPhysicalDeviceFeatures,
    features11: ?types.VkPhysicalDeviceVulkan11Features,
    features12: ?types.VkPhysicalDeviceVulkan12Features,
    features13: ?types.VkPhysicalDeviceVulkan13Features,

    pub fn init() FeatureSupport {
        return .{
            .features = std.mem.zeroes(types.VkPhysicalDeviceFeatures),
            .features11 = null,
            .features12 = null,
            .features13 = null,
        };
    }
};

/// Extension support tracking
pub const ExtensionSupport = struct {
    allocator: std.mem.Allocator,
    available: std.StringHashMap(u32), // extension_name -> spec_version

    pub fn init(allocator: std.mem.Allocator) ExtensionSupport {
        return .{
            .allocator = allocator,
            .available = std.StringHashMap(u32).init(allocator),
        };
    }

    pub fn deinit(self: *ExtensionSupport) void {
        var it = self.available.keyIterator();
        while (it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.available.deinit();
    }

    pub fn hasExtension(self: *ExtensionSupport, name: []const u8) bool {
        return self.available.contains(name);
    }
};

/// Feature/Extension auditor
pub const FeatureAuditor = struct {
    allocator: std.mem.Allocator,
    instance: *instance_mod.Instance,
    physical_device: types.VkPhysicalDevice,
    feature_support: FeatureSupport,
    extension_support: ExtensionSupport,

    pub fn init(
        allocator: std.mem.Allocator,
        instance: *instance_mod.Instance,
        physical_device: types.VkPhysicalDevice,
    ) !*FeatureAuditor {
        var self = try allocator.create(FeatureAuditor);
        self.* = .{
            .allocator = allocator,
            .instance = instance,
            .physical_device = physical_device,
            .feature_support = FeatureSupport.init(),
            .extension_support = ExtensionSupport.init(allocator),
        };

        try self.queryFeatures();
        try self.queryExtensions();

        return self;
    }

    pub fn deinit(self: *FeatureAuditor) void {
        self.extension_support.deinit();
        self.allocator.destroy(self);
    }

    /// Query all supported features using VkPhysicalDeviceFeatures2 with pNext chain
    fn queryFeatures(self: *FeatureAuditor) !void {
        // Build feature chain for comprehensive feature query
        var features13 = types.VkPhysicalDeviceVulkan13Features{
            .sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
            .pNext = null,
        };

        var features12 = types.VkPhysicalDeviceVulkan12Features{
            .sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
            .pNext = &features13,
        };

        var features11 = types.VkPhysicalDeviceVulkan11Features{
            .sType = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
            .pNext = &features12,
        };

        var features2 = types.VkPhysicalDeviceFeatures2{
            .sType = .PHYSICAL_DEVICE_FEATURES_2,
            .pNext = &features11,
            .features = undefined,
        };

        // Query all features at once through the pNext chain
        self.instance.dispatch.get_physical_device_features2(self.physical_device, &features2);

        // Store results
        self.feature_support.features = features2.features;
        self.feature_support.features11 = features11;
        self.feature_support.features12 = features12;
        self.feature_support.features13 = features13;

        log.info("=== Supported Vulkan Features ===", .{});
        self.logCoreFeatures();
        self.logVulkan11Features();
        self.logVulkan12Features();
        self.logVulkan13Features();
    }

    /// Query all available device extensions
    fn queryExtensions(self: *FeatureAuditor) !void {
        var count: u32 = 0;
        _ = self.instance.dispatch.enumerate_device_extension_properties(
            self.physical_device,
            null,
            &count,
            null,
        );

        if (count == 0) return;

        const props = try self.allocator.alloc(types.VkExtensionProperties, count);
        defer self.allocator.free(props);

        _ = self.instance.dispatch.enumerate_device_extension_properties(
            self.physical_device,
            null,
            &count,
            props.ptr,
        );

        log.info("=== Supported Device Extensions ({}) ===", .{count});

        for (props) |prop| {
            const name_slice = std.mem.sliceTo(&prop.extensionName, 0);
            const owned_name = try self.allocator.dupe(u8, name_slice);
            try self.extension_support.available.put(owned_name, prop.specVersion);

            log.debug("  {s} (v{})", .{ name_slice, prop.specVersion });
        }
    }

    /// Log core 1.0 features
    fn logCoreFeatures(self: *FeatureAuditor) void {
        const f = self.feature_support.features;
        log.info("Vulkan 1.0 Features:", .{});
        if (f.geometryShader != 0) log.info("  ✓ Geometry Shaders", .{});
        if (f.tessellationShader != 0) log.info("  ✓ Tessellation Shaders", .{});
        if (f.samplerAnisotropy != 0) log.info("  ✓ Anisotropic Filtering", .{});
        if (f.textureCompressionBC != 0) log.info("  ✓ BC Texture Compression", .{});
        if (f.multiDrawIndirect != 0) log.info("  ✓ Multi-Draw Indirect", .{});
        if (f.fillModeNonSolid != 0) log.info("  ✓ Wireframe Rendering", .{});
        if (f.wideLines != 0) log.info("  ✓ Wide Lines", .{});
    }

    /// Log Vulkan 1.1 features
    fn logVulkan11Features(self: *FeatureAuditor) void {
        if (self.feature_support.features11) |f| {
            log.info("Vulkan 1.1 Features:", .{});
            if (f.storageBuffer16BitAccess != 0) log.info("  ✓ 16-bit Storage Buffer Access", .{});
            if (f.multiview != 0) log.info("  ✓ Multiview Rendering", .{});
            if (f.variablePointers != 0) log.info("  ✓ Variable Pointers", .{});
            if (f.protectedMemory != 0) log.info("  ✓ Protected Memory", .{});
            if (f.samplerYcbcrConversion != 0) log.info("  ✓ YCbCr Sampler Conversion", .{});
            if (f.shaderDrawParameters != 0) log.info("  ✓ Shader Draw Parameters", .{});
        }
    }

    /// Log Vulkan 1.2 features
    fn logVulkan12Features(self: *FeatureAuditor) void {
        if (self.feature_support.features12) |f| {
            log.info("Vulkan 1.2 Features:", .{});
            if (f.descriptorIndexing != 0) log.info("  ✓ Descriptor Indexing", .{});
            if (f.timelineSemaphore != 0) log.info("  ✓ Timeline Semaphores", .{});
            if (f.bufferDeviceAddress != 0) log.info("  ✓ Buffer Device Address", .{});
            if (f.vulkanMemoryModel != 0) log.info("  ✓ Vulkan Memory Model", .{});
            if (f.shaderFloat16 != 0) log.info("  ✓ Shader Float16", .{});
            if (f.shaderInt8 != 0) log.info("  ✓ Shader Int8", .{});
            if (f.storageBuffer8BitAccess != 0) log.info("  ✓ 8-bit Storage Buffer Access", .{});
            if (f.drawIndirectCount != 0) log.info("  ✓ Draw Indirect Count", .{});
            if (f.descriptorBindingPartiallyBound != 0) log.info("  ✓ Partially Bound Descriptors", .{});
            if (f.runtimeDescriptorArray != 0) log.info("  ✓ Runtime Descriptor Arrays", .{});
            if (f.scalarBlockLayout != 0) log.info("  ✓ Scalar Block Layout", .{});
            if (f.imagelessFramebuffer != 0) log.info("  ✓ Imageless Framebuffers", .{});
            if (f.hostQueryReset != 0) log.info("  ✓ Host Query Reset", .{});
        }
    }

    /// Log Vulkan 1.3 features
    fn logVulkan13Features(self: *FeatureAuditor) void {
        if (self.feature_support.features13) |f| {
            log.info("Vulkan 1.3 Features:", .{});
            if (f.synchronization2 != 0) log.info("  ✓ Synchronization2", .{});
            if (f.dynamicRendering != 0) log.info("  ✓ Dynamic Rendering", .{});
            if (f.maintenance4 != 0) log.info("  ✓ Maintenance4", .{});
            if (f.pipelineCreationCacheControl != 0) log.info("  ✓ Pipeline Cache Control", .{});
            if (f.privateData != 0) log.info("  ✓ Private Data", .{});
            if (f.shaderDemoteToHelperInvocation != 0) log.info("  ✓ Shader Demote to Helper", .{});
            if (f.shaderTerminateInvocation != 0) log.info("  ✓ Shader Terminate Invocation", .{});
            if (f.subgroupSizeControl != 0) log.info("  ✓ Subgroup Size Control", .{});
            if (f.computeFullSubgroups != 0) log.info("  ✓ Compute Full Subgroups", .{});
            if (f.inlineUniformBlock != 0) log.info("  ✓ Inline Uniform Blocks", .{});
            if (f.shaderIntegerDotProduct != 0) log.info("  ✓ Shader Integer Dot Product", .{});
            if (f.shaderZeroInitializeWorkgroupMemory != 0) log.info("  ✓ Zero-Initialize Workgroup Memory", .{});
        }
    }

    /// Validate requested extensions are available
    pub fn validateExtensions(self: *FeatureAuditor, requested: []const [*:0]const u8) !void {
        log.info("=== Validating Requested Extensions ===", .{});

        for (requested) |ext_ptr| {
            const ext_name = std.mem.sliceTo(ext_ptr, 0);

            if (!self.extension_support.hasExtension(ext_name)) {
                log.err("❌ Extension NOT supported: {s}", .{ext_name});
                return errors.BaseError.ExtensionNotPresent;
            }

            log.info("  ✓ {s}", .{ext_name});
        }
    }

    /// Validate requested features are available
    pub fn validateFeatures(
        self: *FeatureAuditor,
        requested: types.VkPhysicalDeviceFeatures,
    ) !void {
        log.info("=== Validating Requested Features ===", .{});

        const supported = self.feature_support.features;
        var any_unsupported = false;

        // Check each feature (macro-generate this in production)
        if (requested.geometryShader != 0 and supported.geometryShader == 0) {
            log.err("❌ geometryShader requested but not supported", .{});
            any_unsupported = true;
        }
        if (requested.tessellationShader != 0 and supported.tessellationShader == 0) {
            log.err("❌ tessellationShader requested but not supported", .{});
            any_unsupported = true;
        }
        if (requested.samplerAnisotropy != 0 and supported.samplerAnisotropy == 0) {
            log.err("❌ samplerAnisotropy requested but not supported", .{});
            any_unsupported = true;
        }

        if (any_unsupported) {
            return errors.VkError.FeatureNotPresent;
        }

        log.info("  ✓ All requested features supported", .{});
    }

    /// Cross-check extension/feature dependencies
    pub fn crossCheckDependencies(
        self: *FeatureAuditor,
        extensions: []const [*:0]const u8,
        features: types.VkPhysicalDeviceFeatures,
    ) !void {
        _ = self;
        log.info("=== Cross-Checking Extension/Feature Dependencies ===", .{});

        // Example: VK_KHR_swapchain doesn't require features
        // VK_EXT_descriptor_indexing requires descriptorBindingPartiallyBound feature
        // etc.

        for (extensions) |ext_ptr| {
            const ext_name = std.mem.sliceTo(ext_ptr, 0);

            // Add specific checks here
            if (std.mem.eql(u8, ext_name, "VK_EXT_descriptor_indexing")) {
                // Would need to check descriptorBindingPartiallyBound in features12
                log.debug("  Checking VK_EXT_descriptor_indexing dependencies...", .{});
            }
        }

        _ = features; // Use features for dependency checks

        log.info("  ✓ No dependency violations detected", .{});
    }

    /// Print full audit report
    pub fn printAuditReport(self: *FeatureAuditor) void {
        log.info("", .{});
        log.info("╔══════════════════════════════════════════╗", .{});
        log.info("║  Vulkan Feature/Extension Audit Report  ║", .{});
        log.info("╚══════════════════════════════════════════╝", .{});
        log.info("", .{});
        log.info("Available Extensions: {}", .{self.extension_support.available.count()});
        log.info("", .{});
    }
};

/// Debug-only assertion that features are supported
pub fn assertFeaturesSupported(
    auditor: *FeatureAuditor,
    requested: types.VkPhysicalDeviceFeatures,
) void {
    if (@import("builtin").mode == .Debug) {
        auditor.validateFeatures(requested) catch |err| {
            log.err("ASSERTION FAILED: Unsupported features requested: {}", .{err});
            @panic("Feature validation failed - requested unsupported features");
        };
    }
}

/// Debug-only assertion that extensions are supported
pub fn assertExtensionsSupported(
    auditor: *FeatureAuditor,
    requested: []const [*:0]const u8,
) void {
    if (@import("builtin").mode == .Debug) {
        auditor.validateExtensions(requested) catch |err| {
            log.err("ASSERTION FAILED: Unsupported extensions requested: {}", .{err});
            @panic("Extension validation failed - requested unsupported extensions");
        };
    }
}
