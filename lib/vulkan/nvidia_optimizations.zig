//! NVIDIA-specific optimizations for RTX 4090 and Ada Lovelace architecture

const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const instance_mod = @import("instance.zig");
const allocator_mod = @import("allocator.zig");

const log = std.log.scoped(.nvidia_optimizations);

/// NVIDIA GPU architecture detection
pub const NvidiaArchitecture = enum {
    unknown,
    pascal, // GTX 10 series
    volta, // Titan V
    turing, // RTX 20 series
    ampere, // RTX 30 series
    ada_lovelace, // RTX 40 series
    hopper, // H100, etc.

    pub fn fromDeviceID(device_id: u32) NvidiaArchitecture {
        // Ada Lovelace (RTX 40 series): 0x2684 (RTX 4090), 0x2704 (RTX 4080), etc.
        if (device_id >= 0x2680 and device_id < 0x2800) return .ada_lovelace;

        // Ampere (RTX 30 series): 0x2204 (RTX 3090), 0x2206 (RTX 3080), etc.
        if (device_id >= 0x2200 and device_id < 0x2500) return .ampere;

        // Turing (RTX 20 series): 0x1E82 (RTX 2080 Ti), etc.
        if (device_id >= 0x1E00 and device_id < 0x2000) return .turing;

        // Volta: 0x1D81 (Titan V)
        if (device_id >= 0x1D80 and device_id < 0x1E00) return .volta;

        // Pascal (GTX 10 series): 0x1B80 (GTX 1080 Ti), etc.
        if (device_id >= 0x1B00 and device_id < 0x1D00) return .pascal;

        return .unknown;
    }

    pub fn supportsReBAR(self: NvidiaArchitecture) bool {
        return switch (self) {
            .ada_lovelace, .hopper => true,
            .ampere => true, // RTX 30 series with BIOS update
            else => false,
        };
    }

    pub fn supportsAsyncCompute(self: NvidiaArchitecture) bool {
        return switch (self) {
            .ada_lovelace, .hopper, .ampere, .turing, .volta => true,
            else => false,
        };
    }

    pub fn getAsyncComputeQueueCount(self: NvidiaArchitecture) u32 {
        return switch (self) {
            .ada_lovelace => 2, // RTX 40 series has excellent async compute
            .hopper => 2,
            .ampere => 1,
            .turing => 1,
            .volta => 1,
            else => 0,
        };
    }
};

/// NVIDIA-specific device capabilities
pub const NvidiaCapabilities = struct {
    architecture: NvidiaArchitecture,
    device_id: u32,
    has_rebar: bool,
    rebar_size_mb: u32,
    async_compute_queues: u32,
    has_device_generated_commands: bool,
    has_mesh_shader: bool,
    has_ray_tracing: bool,
    has_dlss: bool,

    pub fn detect(physical_device: types.VkPhysicalDevice, instance: *instance_mod.Instance) NvidiaCapabilities {
        var properties: types.VkPhysicalDeviceProperties = undefined;
        instance.dispatch.get_physical_device_properties(physical_device, &properties);

        const is_nvidia = properties.vendorID == 0x10DE;
        const device_id = properties.deviceID;

        var caps = NvidiaCapabilities{
            .architecture = if (is_nvidia) NvidiaArchitecture.fromDeviceID(device_id) else .unknown,
            .device_id = device_id,
            .has_rebar = false,
            .rebar_size_mb = 0,
            .async_compute_queues = 0,
            .has_device_generated_commands = false,
            .has_mesh_shader = false,
            .has_ray_tracing = false,
            .has_dlss = false,
        };

        if (!is_nvidia) return caps;

        // Detect ReBAR
        caps.has_rebar = caps.architecture.supportsReBAR();
        caps.async_compute_queues = caps.architecture.getAsyncComputeQueueCount();

        // RTX features
        caps.has_mesh_shader = switch (caps.architecture) {
            .ada_lovelace, .hopper, .ampere, .turing => true,
            else => false,
        };

        caps.has_ray_tracing = switch (caps.architecture) {
            .ada_lovelace, .hopper, .ampere, .turing => true,
            else => false,
        };

        caps.has_dlss = switch (caps.architecture) {
            .ada_lovelace, .hopper, .ampere, .turing => true,
            else => false,
        };

        log.info("NVIDIA GPU detected: {} (0x{X})", .{ caps.architecture, device_id });
        log.info("ReBAR: {}, Async compute queues: {}", .{ caps.has_rebar, caps.async_compute_queues });
        log.info("Mesh shaders: {}, Ray tracing: {}, DLSS: {}", .{
            caps.has_mesh_shader,
            caps.has_ray_tracing,
            caps.has_dlss,
        });

        return caps;
    }
};

/// NVIDIA memory allocation hints
pub const NvidiaMemoryHints = struct {
    capabilities: NvidiaCapabilities,

    pub fn init(capabilities: NvidiaCapabilities) NvidiaMemoryHints {
        return .{ .capabilities = capabilities };
    }

    /// Get optimal memory type for ReBAR
    pub fn getRebarMemoryType(self: NvidiaMemoryHints, memory_properties: types.VkPhysicalDeviceMemoryProperties) ?u32 {
        if (!self.capabilities.has_rebar) return null;

        // Look for device-local + host-visible memory (ReBAR)
        const desired_flags = types.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT | types.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT;

        var i: u32 = 0;
        while (i < memory_properties.memoryTypeCount) : (i += 1) {
            const mem_type = memory_properties.memoryTypes[i];
            if ((mem_type.propertyFlags & desired_flags) == desired_flags) {
                // Check heap size (ReBAR should be large)
                const heap_index = mem_type.heapIndex;
                const heap_size = memory_properties.memoryHeaps[heap_index].size;

                // ReBAR heap should be at least 1GB
                if (heap_size >= 1024 * 1024 * 1024) {
                    log.info("Found ReBAR memory type {} (heap size: {} MB)", .{
                        i,
                        heap_size / (1024 * 1024),
                    });
                    return i;
                }
            }
        }

        return null;
    }

    /// Recommend allocation strategy based on ReBAR
    pub fn getAllocationStrategy(self: NvidiaMemoryHints) allocator_mod.MemoryUsage {
        if (self.capabilities.has_rebar) {
            // With ReBAR, prefer host-visible device memory
            return .gpu_to_cpu;
        } else {
            // Without ReBAR, use traditional staging
            return .gpu_only;
        }
    }

    /// Get optimal staging buffer size
    pub fn getOptimalStagingSize(self: NvidiaMemoryHints) usize {
        return switch (self.capabilities.architecture) {
            .ada_lovelace, .hopper => 256 * 1024 * 1024, // 256MB for RTX 40 series
            .ampere => 128 * 1024 * 1024, // 128MB for RTX 30 series
            else => 64 * 1024 * 1024, // 64MB fallback
        };
    }
};

/// NVIDIA async compute optimization
pub const NvidiaAsyncCompute = struct {
    capabilities: NvidiaCapabilities,
    graphics_queue_family: u32,
    compute_queue_family: u32,
    async_queue_family: ?u32,

    pub fn init(
        capabilities: NvidiaCapabilities,
        graphics_family: u32,
        compute_family: u32,
        async_family: ?u32,
    ) NvidiaAsyncCompute {
        return .{
            .capabilities = capabilities,
            .graphics_queue_family = graphics_family,
            .compute_queue_family = compute_family,
            .async_queue_family = async_family,
        };
    }

    /// Check if async compute is beneficial
    pub fn shouldUseAsyncCompute(self: NvidiaAsyncCompute) bool {
        return self.capabilities.async_compute_queues > 0 and self.async_queue_family != null;
    }

    /// Get recommended compute workload size for parallel execution
    pub fn getOptimalWorkgroupSize(self: NvidiaAsyncCompute) u32 {
        return switch (self.capabilities.architecture) {
            .ada_lovelace => 128, // RTX 40 series has massive SM count
            .hopper => 256,
            .ampere => 64,
            .turing => 32,
            else => 32,
        };
    }

    /// Get SM count estimate
    pub fn getEstimatedSMCount(self: NvidiaAsyncCompute) u32 {
        return switch (self.capabilities.architecture) {
            .ada_lovelace => 128, // RTX 4090 has 128 SMs
            .hopper => 132, // H100 has 132 SMs
            .ampere => 82, // RTX 3090 has 82 SMs
            .turing => 68, // RTX 2080 Ti has 68 SMs
            else => 32,
        };
    }
};

/// NVIDIA pipeline optimization hints
pub const NvidiaPipelineHints = struct {
    capabilities: NvidiaCapabilities,

    pub fn init(capabilities: NvidiaCapabilities) NvidiaPipelineHints {
        return .{ .capabilities = capabilities };
    }

    /// Recommend pipeline cache size
    pub fn getOptimalCacheSize(self: NvidiaPipelineHints) usize {
        return switch (self.capabilities.architecture) {
            .ada_lovelace, .hopper => 64 * 1024 * 1024, // 64MB for complex shaders
            .ampere, .turing => 32 * 1024 * 1024,
            else => 16 * 1024 * 1024,
        };
    }

    /// Recommend subgroup size for compute
    pub fn getOptimalSubgroupSize(self: NvidiaPipelineHints) u32 {
        // NVIDIA always uses 32 (warp size)
        _ = self;
        return 32;
    }

    /// Check if shader should use cooperative matrices
    pub fn shouldUseCooperativeMatrix(self: NvidiaPipelineHints) bool {
        return switch (self.capabilities.architecture) {
            .ada_lovelace, .hopper => true, // Tensor cores
            .ampere, .turing, .volta => true,
            else => false,
        };
    }
};

/// NVIDIA render optimization manager
pub const NvidiaOptimizer = struct {
    allocator: std.mem.Allocator,
    capabilities: NvidiaCapabilities,
    memory_hints: NvidiaMemoryHints,
    pipeline_hints: NvidiaPipelineHints,

    pub fn init(
        allocator: std.mem.Allocator,
        physical_device: types.VkPhysicalDevice,
        instance: *instance_mod.Instance,
    ) !*NvidiaOptimizer {
        const caps = NvidiaCapabilities.detect(physical_device, instance);

        const self = try allocator.create(NvidiaOptimizer);
        self.* = .{
            .allocator = allocator,
            .capabilities = caps,
            .memory_hints = NvidiaMemoryHints.init(caps),
            .pipeline_hints = NvidiaPipelineHints.init(caps),
        };

        return self;
    }

    pub fn deinit(self: *NvidiaOptimizer) void {
        self.allocator.destroy(self);
    }

    /// Check if this is an NVIDIA GPU
    pub fn isNvidia(self: *NvidiaOptimizer) bool {
        return self.capabilities.architecture != .unknown;
    }

    /// Get optimization report
    pub fn getOptimizationReport(self: *NvidiaOptimizer) void {
        if (!self.isNvidia()) {
            log.info("Not an NVIDIA GPU, optimizations not applicable", .{});
            return;
        }

        log.info("=== NVIDIA Optimization Report ===", .{});
        log.info("Architecture: {}", .{self.capabilities.architecture});
        log.info("Device ID: 0x{X}", .{self.capabilities.device_id});
        log.info("ReBAR: {}", .{self.capabilities.has_rebar});
        log.info("Async compute queues: {}", .{self.capabilities.async_compute_queues});
        log.info("Mesh shaders: {}", .{self.capabilities.has_mesh_shader});
        log.info("Ray tracing: {}", .{self.capabilities.has_ray_tracing});
        log.info("Optimal staging size: {} MB", .{self.memory_hints.getOptimalStagingSize() / (1024 * 1024)});
        log.info("Optimal cache size: {} MB", .{self.pipeline_hints.getOptimalCacheSize() / (1024 * 1024)});
        log.info("Cooperative matrices: {}", .{self.pipeline_hints.shouldUseCooperativeMatrix()});
    }
};
