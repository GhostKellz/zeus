pub const types = @import("types.zig");
pub const types_ext = @import("types_ext.zig");
pub const loader = @import("loader.zig");
pub const errors = @import("error.zig");
pub const context = @import("context.zig");
pub const instance = @import("instance.zig");
pub const device = @import("device.zig");
pub const surface = @import("surface.zig");
pub const swapchain = @import("swapchain.zig");
pub const physical_device = @import("physical_device.zig");
pub const commands = @import("commands.zig");
pub const sync = @import("sync.zig");
pub const query = @import("query.zig");
pub const one_time_submit = @import("one_time_submit.zig");
pub const buffer = @import("buffer.zig");
pub const image = @import("image.zig");
pub const sampler = @import("sampler.zig");
pub const descriptor = @import("descriptor.zig");
pub const pipeline = @import("pipeline.zig");
pub const shader = @import("shader.zig");
pub const render_pass = @import("render_pass.zig");
pub const glyph_atlas = @import("glyph_atlas.zig");
pub const text_renderer = @import("text_renderer.zig");
pub const text_decoration = @import("text_decoration.zig");
pub const system_validation = @import("system_validation.zig");
pub const compositor_validation = @import("compositor_validation.zig");
pub const frame_pacing = @import("frame_pacing.zig");

// v0.1.4: Advanced memory management
pub const allocator = @import("allocator.zig");
pub const buffer_allocator = @import("buffer_allocator.zig");
pub const image_allocator = @import("image_allocator.zig");
pub const memory = @import("memory.zig");

// v0.1.4: Advanced command & sync
pub const command_manager = @import("command_manager.zig");
pub const sync_manager = @import("sync_manager.zig");
pub const barrier_helper = @import("barrier_helper.zig");

// v0.1.4: Advanced descriptors
pub const descriptor_allocator = @import("descriptor_allocator.zig");

// v0.1.4: Advanced helpers and builders
pub const transfer_helper = @import("transfer_helper.zig");
pub const immediate_submit = @import("immediate_submit.zig");
pub const pipeline_builder = @import("pipeline_builder.zig");
pub const render_pass_builder = @import("render_pass_builder.zig");
pub const framebuffer_manager = @import("framebuffer_manager.zig");

// v0.1.4: Performance and hardware support
pub const hdr_support = @import("hdr_support.zig");
pub const vrr_support = @import("vrr_support.zig");
pub const dmabuf_support = @import("dmabuf_support.zig");
pub const nvidia_optimizations = @import("nvidia_optimizations.zig");

// v0.1.4: Developer experience
pub const debug_utils = @import("debug_utils.zig");
pub const error_context = @import("error_context.zig");

pub const Loader = loader.Loader;
pub const Context = context.Context;
pub const Instance = instance.Instance;
pub const Device = device.Device;
pub const DeviceCandidate = instance.DeviceCandidate;
pub const DeviceOptions = device.Device.Options;
pub const Surface = surface.Surface;
pub const Swapchain = swapchain.Swapchain;
pub const SwapchainStatus = swapchain.Status;
pub const SwapchainAcquireResult = swapchain.AcquireResult;
pub const PhysicalDeviceSelection = physical_device.Selection;
pub const PhysicalDeviceRequirements = physical_device.Requirements;
pub const PhysicalDeviceQueueNeeds = physical_device.QueueNeeds;
pub const CommandPool = commands.CommandPool;
pub const Fence = sync.Fence;
pub const Semaphore = sync.Semaphore;
pub const SemaphoreType = sync.SemaphoreType;
pub const TextRenderer = text_renderer.TextRenderer;
pub const ManagedBuffer = buffer.ManagedBuffer;
pub const ManagedImage = image.ManagedImage;
pub const Sampler = sampler.Sampler;
pub const DescriptorSetAllocation = descriptor.DescriptorSetAllocation;
pub const PipelineLayout = pipeline.PipelineLayout;
pub const PipelineLayoutOptions = pipeline.PipelineLayoutOptions;
pub const ShaderModule = shader.ShaderModule;
pub const RenderPassBuilder = render_pass.RenderPassBuilder;
pub const RenderPass = render_pass.RenderPass;
pub const GraphicsPipeline = pipeline.GraphicsPipeline;
pub const GraphicsPipelineOptions = pipeline.GraphicsPipelineOptions;
pub const GlyphAtlas = glyph_atlas.GlyphAtlas;
pub const GlyphKey = glyph_atlas.GlyphKey;
pub const GlyphMetrics = glyph_atlas.GlyphMetrics;
pub const TextQuad = text_renderer.TextQuad;
pub const TextVertexLayout = pipeline.TextVertexLayout;
pub const DecorationType = text_decoration.DecorationType;
pub const DecorationStyle = text_decoration.DecorationStyle;
pub const DecorationRect = text_decoration.DecorationRect;
pub const SystemValidation = system_validation.SystemValidation;
pub const SystemValidationOptions = system_validation.SystemValidationOptions;
pub const KernelValidation = system_validation.KernelValidation;
pub const CompositorInfo = compositor_validation.CompositorInfo;
pub const CompositorType = compositor_validation.CompositorType;
pub const CompositorQuirks = compositor_validation.CompositorQuirks;
pub const FramePacer = frame_pacing.FramePacer;
pub const WaylandFeedback = frame_pacing.WaylandFeedback;
