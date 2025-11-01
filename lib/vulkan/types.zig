pub const VK_MAX_PHYSICAL_DEVICE_NAME_SIZE = 256;
pub const VK_UUID_SIZE = 16;
pub const VK_MAX_MEMORY_TYPES = 32;
pub const VK_MAX_MEMORY_HEAPS = 16;

pub const VkFlags = u32;
pub const VkBool32 = u32;
pub const VkDeviceSize = u64;
pub const VkSampleMask = u32;

pub fn makeApiVersion(major: u32, minor: u32, patch: u32) u32 {
    return (major << 22) | (minor << 12) | patch;
}

pub const VkStructureType = enum(u32) {
    APPLICATION_INFO = 0,
    INSTANCE_CREATE_INFO = 1,
    DEVICE_QUEUE_CREATE_INFO = 2,
    DEVICE_CREATE_INFO = 3,
    SUBMIT_INFO = 4,
    MEMORY_ALLOCATE_INFO = 5,
    MAPPED_MEMORY_RANGE = 6,
    BIND_SPARSE_INFO = 7,
    FENCE_CREATE_INFO = 8,
    SEMAPHORE_CREATE_INFO = 9,
    EVENT_CREATE_INFO = 10,
    QUERY_POOL_CREATE_INFO = 11,
    BUFFER_CREATE_INFO = 12,
    BUFFER_VIEW_CREATE_INFO = 13,
    IMAGE_CREATE_INFO = 14,
    IMAGE_VIEW_CREATE_INFO = 15,
    SHADER_MODULE_CREATE_INFO = 16,
    PIPELINE_CACHE_CREATE_INFO = 17,
    PIPELINE_SHADER_STAGE_CREATE_INFO = 18,
    PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO = 19,
    PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO = 20,
    PIPELINE_TESSELLATION_STATE_CREATE_INFO = 21,
    PIPELINE_VIEWPORT_STATE_CREATE_INFO = 22,
    PIPELINE_RASTERIZATION_STATE_CREATE_INFO = 23,
    PIPELINE_MULTISAMPLE_STATE_CREATE_INFO = 24,
    PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO = 25,
    PIPELINE_COLOR_BLEND_STATE_CREATE_INFO = 26,
    PIPELINE_DYNAMIC_STATE_CREATE_INFO = 27,
    GRAPHICS_PIPELINE_CREATE_INFO = 28,
    COMPUTE_PIPELINE_CREATE_INFO = 29,
    PIPELINE_LAYOUT_CREATE_INFO = 30,
    SAMPLER_CREATE_INFO = 31,
    DESCRIPTOR_SET_LAYOUT_CREATE_INFO = 32,
    DESCRIPTOR_POOL_CREATE_INFO = 33,
    DESCRIPTOR_SET_ALLOCATE_INFO = 34,
    WRITE_DESCRIPTOR_SET = 35,
    COPY_DESCRIPTOR_SET = 36,
    FRAMEBUFFER_CREATE_INFO = 37,
    RENDER_PASS_CREATE_INFO = 38,
    COMMAND_POOL_CREATE_INFO = 39,
    COMMAND_BUFFER_ALLOCATE_INFO = 40,
    COMMAND_BUFFER_INHERITANCE_INFO = 41,
    COMMAND_BUFFER_BEGIN_INFO = 42,
    RENDER_PASS_BEGIN_INFO = 43,
    BUFFER_MEMORY_BARRIER = 44,
    IMAGE_MEMORY_BARRIER = 45,
    MEMORY_BARRIER = 46,
    LOADER_INSTANCE_CREATE_INFO = 47,
    LOADER_DEVICE_CREATE_INFO = 48,
    SWAPCHAIN_CREATE_INFO_KHR = 1000001000,
    PRESENT_INFO_KHR = 1000001001,
    PRESENT_TIMES_INFO_GOOGLE = 1000092000,
    DEBUG_UTILS_OBJECT_NAME_INFO_EXT = 1000128000,
    DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT = 1000128004,
    DEBUG_UTILS_MESSENGER_CALLBACK_DATA_EXT = 1000128005,
    DEBUG_UTILS_LABEL_EXT = 1000128006,
    SEMAPHORE_TYPE_CREATE_INFO = 1000207002,
    TIMELINE_SEMAPHORE_SUBMIT_INFO = 1000207003,
    SEMAPHORE_WAIT_INFO = 1000207004,
    SEMAPHORE_SIGNAL_INFO = 1000207005,
    _,
};

pub const VkResult = enum(i32) {
    SUCCESS = 0,
    NOT_READY = 1,
    TIMEOUT = 2,
    EVENT_SET = 3,
    EVENT_RESET = 4,
    INCOMPLETE = 5,
    ERROR_OUT_OF_HOST_MEMORY = -1,
    ERROR_OUT_OF_DEVICE_MEMORY = -2,
    ERROR_INITIALIZATION_FAILED = -3,
    ERROR_DEVICE_LOST = -4,
    ERROR_MEMORY_MAP_FAILED = -5,
    ERROR_LAYER_NOT_PRESENT = -6,
    ERROR_EXTENSION_NOT_PRESENT = -7,
    ERROR_FEATURE_NOT_PRESENT = -8,
    ERROR_INCOMPATIBLE_DRIVER = -9,
    ERROR_TOO_MANY_OBJECTS = -10,
    ERROR_FORMAT_NOT_SUPPORTED = -11,
    ERROR_FRAGMENTED_POOL = -12,
    ERROR_UNKNOWN = -13,
    ERROR_SURFACE_LOST_KHR = -1000000000,
    ERROR_NATIVE_WINDOW_IN_USE_KHR = -1000000001,
    SUBOPTIMAL_KHR = 1000001003,
    ERROR_OUT_OF_DATE_KHR = -1000001004,
    _,
};

pub const VkInstance_T = opaque {};
pub const VkPhysicalDevice_T = opaque {};
pub const VkDevice_T = opaque {};
pub const VkQueue_T = opaque {};
pub const VkCommandBuffer_T = opaque {};
pub const VkCommandPool_T = opaque {};
pub const VkBuffer_T = opaque {};
pub const VkDeviceMemory_T = opaque {};
pub const VkImageView_T = opaque {};
pub const VkSampler_T = opaque {};
pub const VkShaderModule_T = opaque {};
pub const VkRenderPass_T = opaque {};
pub const VkPipeline_T = opaque {};
pub const VkPipelineLayout_T = opaque {};
pub const VkDescriptorSetLayout_T = opaque {};
pub const VkDescriptorPool_T = opaque {};
pub const VkDescriptorSet_T = opaque {};
pub const VkFramebuffer_T = opaque {};
pub const VkSurfaceKHR_T = opaque {};
pub const VkSwapchainKHR_T = opaque {};
pub const VkImage_T = opaque {};

pub const VkInstance = *VkInstance_T;
pub const VkPhysicalDevice = *VkPhysicalDevice_T;
pub const VkDevice = *VkDevice_T;
pub const VkQueue = *VkQueue_T;
pub const VkCommandBuffer = *VkCommandBuffer_T;
pub const VkCommandPool = *VkCommandPool_T;
pub const VkBuffer = *VkBuffer_T;
pub const VkDeviceMemory = *VkDeviceMemory_T;
pub const VkImageView = *VkImageView_T;
pub const VkSampler = *VkSampler_T;
pub const VkShaderModule = *VkShaderModule_T;
pub const VkRenderPass = *VkRenderPass_T;
pub const VkPipeline = *VkPipeline_T;
pub const VkPipelineLayout = *VkPipelineLayout_T;
pub const VkDescriptorSetLayout = *VkDescriptorSetLayout_T;
pub const VkDescriptorPool = *VkDescriptorPool_T;
pub const VkDescriptorSet = *VkDescriptorSet_T;
pub const VkFramebuffer = *VkFramebuffer_T;
pub const VkSurfaceKHR = *VkSurfaceKHR_T;
pub const VkSwapchainKHR = *VkSwapchainKHR_T;
pub const VkImage = *VkImage_T;

pub const VkAllocationCallbacks = extern struct {
    pUserData: ?*anyopaque,
    pfnAllocation: ?*const fn (?*anyopaque, usize, usize, VkSystemAllocationScope) callconv(.C) ?*anyopaque,
    pfnReallocation: ?*const fn (?*anyopaque, ?*anyopaque, usize, usize, VkSystemAllocationScope) callconv(.C) ?*anyopaque,
    pfnFree: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.C) void,
    pfnInternalAllocation: ?*const fn (?*anyopaque, usize, VkInternalAllocationType, VkSystemAllocationScope) callconv(.C) void,
    pfnInternalFree: ?*const fn (?*anyopaque, usize, VkInternalAllocationType, VkSystemAllocationScope) callconv(.C) void,
};

pub const VkSystemAllocationScope = enum(u32) {
    COMMAND = 0,
    OBJECT = 1,
    CACHE = 2,
    DEVICE = 3,
    INSTANCE = 4,
};

pub const VkInternalAllocationType = enum(u32) {
    EXECUTABLE = 0,
};

pub const VkApplicationInfo = extern struct {
    sType: VkStructureType = .APPLICATION_INFO,
    pNext: ?*const anyopaque = null,
    pApplicationName: ?[*:0]const u8 = null,
    applicationVersion: u32 = 0,
    pEngineName: ?[*:0]const u8 = null,
    engineVersion: u32 = 0,
    apiVersion: u32 = makeApiVersion(1, 0, 0),
};

pub const VkInstanceCreateFlags = VkFlags;

pub const VkInstanceCreateInfo = extern struct {
    sType: VkStructureType = .INSTANCE_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    flags: VkInstanceCreateFlags = 0,
    pApplicationInfo: ?*const VkApplicationInfo = null,
    enabledLayerCount: u32 = 0,
    ppEnabledLayerNames: ?[*]const [*:0]const u8 = null,
    enabledExtensionCount: u32 = 0,
    ppEnabledExtensionNames: ?[*]const [*:0]const u8 = null,
};

pub const VkDeviceQueueCreateFlags = VkFlags;

pub const VkDeviceQueueCreateInfo = extern struct {
    sType: VkStructureType = .DEVICE_QUEUE_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    flags: VkDeviceQueueCreateFlags = 0,
    queueFamilyIndex: u32,
    queueCount: u32,
    pQueuePriorities: [*]const f32,
};

pub const VkDeviceCreateFlags = VkFlags;

pub const VkDeviceCreateInfo = extern struct {
    sType: VkStructureType = .DEVICE_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    flags: VkDeviceCreateFlags = 0,
    queueCreateInfoCount: u32,
    pQueueCreateInfos: [*]const VkDeviceQueueCreateInfo,
    enabledLayerCount: u32 = 0,
    ppEnabledLayerNames: ?[*]const [*:0]const u8 = null,
    enabledExtensionCount: u32 = 0,
    ppEnabledExtensionNames: ?[*]const [*:0]const u8 = null,
    pEnabledFeatures: ?*const VkPhysicalDeviceFeatures = null,
};

pub const VkFormat = enum(u32) {
    UNDEFINED = 0,
    R8G8B8A8_UNORM = 37,
    R8G8B8A8_SRGB = 43,
    B8G8R8A8_UNORM = 44,
    B8G8R8A8_SRGB = 50,
    D32_SFLOAT = 126,
    _,
};

pub const VkLayerProperties = extern struct {
    layerName: [256]u8,
    specVersion: u32,
    implementationVersion: u32,
    description: [256]u8,
};

pub const VkExtensionProperties = extern struct {
    extensionName: [256]u8,
    specVersion: u32,
};

pub const VkPhysicalDeviceFeatures = extern struct {
    robustBufferAccess: VkBool32,
    fullDrawIndexUint32: VkBool32,
    imageCubeArray: VkBool32,
    independentBlend: VkBool32,
    geometryShader: VkBool32,
    tessellationShader: VkBool32,
    sampleRateShading: VkBool32,
    dualSrcBlend: VkBool32,
    logicOp: VkBool32,
    multiDrawIndirect: VkBool32,
    drawIndirectFirstInstance: VkBool32,
    depthClamp: VkBool32,
    depthBiasClamp: VkBool32,
    fillModeNonSolid: VkBool32,
    depthBounds: VkBool32,
    wideLines: VkBool32,
    largePoints: VkBool32,
    alphaToOne: VkBool32,
    multiViewport: VkBool32,
    samplerAnisotropy: VkBool32,
    textureCompressionETC2: VkBool32,
    textureCompressionASTC_LDR: VkBool32,
    textureCompressionBC: VkBool32,
    occlusionQueryPrecise: VkBool32,
    pipelineStatisticsQuery: VkBool32,
    vertexPipelineStoresAndAtomics: VkBool32,
    fragmentStoresAndAtomics: VkBool32,
    shaderTessellationAndGeometryPointSize: VkBool32,
    shaderImageGatherExtended: VkBool32,
    shaderStorageImageExtendedFormats: VkBool32,
    shaderStorageImageMultisample: VkBool32,
    shaderStorageImageReadWithoutFormat: VkBool32,
    shaderStorageImageWriteWithoutFormat: VkBool32,
    shaderUniformBufferArrayDynamicIndexing: VkBool32,
    shaderSampledImageArrayDynamicIndexing: VkBool32,
    shaderStorageBufferArrayDynamicIndexing: VkBool32,
    shaderStorageImageArrayDynamicIndexing: VkBool32,
    shaderClipDistance: VkBool32,
    shaderCullDistance: VkBool32,
    shaderFloat64: VkBool32,
    shaderInt64: VkBool32,
    shaderInt16: VkBool32,
    shaderResourceResidency: VkBool32,
    shaderResourceMinLod: VkBool32,
    sparseBinding: VkBool32,
    sparseResidencyBuffer: VkBool32,
    sparseResidencyImage2D: VkBool32,
    sparseResidencyImage3D: VkBool32,
    sparseResidency2Samples: VkBool32,
    sparseResidency4Samples: VkBool32,
    sparseResidency8Samples: VkBool32,
    sparseResidency16Samples: VkBool32,
    sparseResidencyAliased: VkBool32,
    variableMultisampleRate: VkBool32,
    inheritedQueries: VkBool32,
};

pub const VkPhysicalDeviceType = enum(u32) {
    OTHER = 0,
    INTEGRATED_GPU = 1,
    DISCRETE_GPU = 2,
    VIRTUAL_GPU = 3,
    CPU = 4,
};

pub const VkPipelineBindPoint = enum(u32) {
    GRAPHICS = 0,
    COMPUTE = 1,
    _,
};

pub const VK_PIPELINE_BIND_POINT_GRAPHICS: VkPipelineBindPoint = .GRAPHICS;
pub const VK_PIPELINE_BIND_POINT_COMPUTE: VkPipelineBindPoint = .COMPUTE;

pub const VkShaderStageFlags = VkFlags;

pub const VkShaderStageFlagBits = enum(VkShaderStageFlags) {
    VERTEX_BIT = 0x00000001,
    TESSELLATION_CONTROL_BIT = 0x00000002,
    TESSELLATION_EVALUATION_BIT = 0x00000004,
    GEOMETRY_BIT = 0x00000008,
    FRAGMENT_BIT = 0x00000010,
    COMPUTE_BIT = 0x00000020,
    _,
};

pub const VK_SHADER_STAGE_VERTEX_BIT: VkShaderStageFlags = 0x00000001;
pub const VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT: VkShaderStageFlags = 0x00000002;
pub const VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT: VkShaderStageFlags = 0x00000004;
pub const VK_SHADER_STAGE_GEOMETRY_BIT: VkShaderStageFlags = 0x00000008;
pub const VK_SHADER_STAGE_FRAGMENT_BIT: VkShaderStageFlags = 0x00000010;
pub const VK_SHADER_STAGE_COMPUTE_BIT: VkShaderStageFlags = 0x00000020;
pub const VK_SHADER_STAGE_ALL_GRAPHICS: VkShaderStageFlags = 0x0000001F;
pub const VK_SHADER_STAGE_ALL: VkShaderStageFlags = 0x7FFFFFFF;

pub const VkPushConstantRange = extern struct {
    stageFlags: VkShaderStageFlags,
    offset: u32,
    size: u32,
};

pub const VkExtent2D = extern struct {
    width: u32,
    height: u32,
};

pub const VkExtent3D = extern struct {
    width: u32,
    height: u32,
    depth: u32,
};

pub const VkOffset2D = extern struct {
    x: i32,
    y: i32,
};

pub const VkOffset3D = extern struct {
    x: i32,
    y: i32,
    z: i32,
};

pub const VkViewport = extern struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    minDepth: f32,
    maxDepth: f32,
};

pub const VkRect2D = extern struct {
    offset: VkOffset2D,
    extent: VkExtent2D,
};

pub const VkQueueFlags = VkFlags;

pub const VK_QUEUE_GRAPHICS_BIT: VkQueueFlags = 0x00000001;
pub const VK_QUEUE_COMPUTE_BIT: VkQueueFlags = 0x00000002;
pub const VK_QUEUE_TRANSFER_BIT: VkQueueFlags = 0x00000004;
pub const VK_QUEUE_SPARSE_BINDING_BIT: VkQueueFlags = 0x00000008;

pub const VK_QUEUE_FAMILY_IGNORED: u32 = 0xFFFFFFFF;

pub const VkImageUsageFlags = VkFlags;
pub const VK_IMAGE_USAGE_TRANSFER_SRC_BIT: VkImageUsageFlags = 0x00000001;
pub const VK_IMAGE_USAGE_TRANSFER_DST_BIT: VkImageUsageFlags = 0x00000002;
pub const VK_IMAGE_USAGE_SAMPLED_BIT: VkImageUsageFlags = 0x00000004;
pub const VK_IMAGE_USAGE_STORAGE_BIT: VkImageUsageFlags = 0x00000008;
pub const VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT: VkImageUsageFlags = 0x00000010;
pub const VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT: VkImageUsageFlags = 0x00000020;
pub const VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT: VkImageUsageFlags = 0x00000040;
pub const VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT: VkImageUsageFlags = 0x00000080;

pub const VkSharingMode = enum(u32) {
    EXCLUSIVE = 0,
    CONCURRENT = 1,
};

pub const VkSurfaceTransformFlagsKHR = VkFlags;
pub const VkSurfaceTransformFlagBitsKHR = enum(VkSurfaceTransformFlagsKHR) {
    IDENTITY = 0x00000001,
    ROTATE_90 = 0x00000002,
    ROTATE_180 = 0x00000004,
    ROTATE_270 = 0x00000008,
    HORIZONTAL_MIRROR = 0x00000010,
    HORIZONTAL_MIRROR_ROTATE_90 = 0x00000020,
    HORIZONTAL_MIRROR_ROTATE_180 = 0x00000040,
    HORIZONTAL_MIRROR_ROTATE_270 = 0x00000080,
    INHERIT = 0x00000100,
};

pub const VkCompositeAlphaFlagsKHR = VkFlags;
pub const VkCompositeAlphaFlagBitsKHR = enum(VkCompositeAlphaFlagsKHR) {
    OPAQUE = 0x00000001,
    PRE_MULTIPLIED = 0x00000002,
    POST_MULTIPLIED = 0x00000004,
    INHERIT = 0x00000008,
};

pub const VkColorSpaceKHR = enum(u32) {
    SRGB_NONLINEAR = 0,
    DISPLAY_P3_NONLINEAR = 1000104001,
    EXTENDED_SRGB_LINEAR = 1000104002,
    DISPLAY_P3_LINEAR = 1000104003,
    DCI_P3_NONLINEAR = 1000104004,
    _,
};

pub const VkPresentModeKHR = enum(u32) {
    IMMEDIATE = 0,
    MAILBOX = 1,
    FIFO = 2,
    FIFO_RELAXED = 3,
    SHARED_DEMAND_REFRESH = 1000111000,
    SHARED_CONTINUOUS_REFRESH = 1000111001,
    _,
};

pub const VkQueueFamilyProperties = extern struct {
    queueFlags: VkQueueFlags,
    queueCount: u32,
    timestampValidBits: u32,
    minImageTransferGranularity: VkExtent3D,
};

pub const VkSurfaceCapabilitiesKHR = extern struct {
    minImageCount: u32,
    maxImageCount: u32,
    currentExtent: VkExtent2D,
    minImageExtent: VkExtent2D,
    maxImageExtent: VkExtent2D,
    maxImageArrayLayers: u32,
    supportedTransforms: VkSurfaceTransformFlagsKHR,
    currentTransform: VkSurfaceTransformFlagBitsKHR,
    supportedCompositeAlpha: VkCompositeAlphaFlagsKHR,
    supportedUsageFlags: VkImageUsageFlags,
};

pub const VkSurfaceFormatKHR = extern struct {
    format: VkFormat,
    colorSpace: VkColorSpaceKHR,
};

pub const VkPhysicalDeviceLimits = extern struct {
    maxImageDimension1D: u32,
    maxImageDimension2D: u32,
    maxImageDimension3D: u32,
    maxImageDimensionCube: u32,
    maxImageArrayLayers: u32,
    maxTexelBufferElements: u32,
    maxUniformBufferRange: u32,
    maxStorageBufferRange: u32,
    maxPushConstantsSize: u32,
    maxMemoryAllocationCount: u32,
    maxSamplerAllocationCount: u32,
    bufferImageGranularity: VkDeviceSize,
    sparseAddressSpaceSize: VkDeviceSize,
    maxBoundDescriptorSets: u32,
    maxPerStageDescriptorSamplers: u32,
    maxPerStageDescriptorUniformBuffers: u32,
    maxPerStageDescriptorStorageBuffers: u32,
    maxPerStageDescriptorSampledImages: u32,
    maxPerStageDescriptorStorageImages: u32,
    maxPerStageDescriptorInputAttachments: u32,
    maxPerStageResources: u32,
    maxDescriptorSetSamplers: u32,
    maxDescriptorSetUniformBuffers: u32,
    maxDescriptorSetUniformBuffersDynamic: u32,
    maxDescriptorSetStorageBuffers: u32,
    maxDescriptorSetStorageBuffersDynamic: u32,
    maxDescriptorSetSampledImages: u32,
    maxDescriptorSetStorageImages: u32,
    maxDescriptorSetInputAttachments: u32,
    maxVertexInputAttributes: u32,
    maxVertexInputBindings: u32,
    maxVertexInputAttributeOffset: u32,
    maxVertexInputBindingStride: u32,
    maxVertexOutputComponents: u32,
    maxTessellationGenerationLevel: u32,
    maxTessellationPatchSize: u32,
    maxTessellationControlPerVertexInputComponents: u32,
    maxTessellationControlPerVertexOutputComponents: u32,
    maxTessellationControlPerPatchOutputComponents: u32,
    maxTessellationControlTotalOutputComponents: u32,
    maxTessellationEvaluationInputComponents: u32,
    maxTessellationEvaluationOutputComponents: u32,
    maxGeometryShaderInvocations: u32,
    maxGeometryInputComponents: u32,
    maxGeometryOutputComponents: u32,
    maxGeometryOutputVertices: u32,
    maxGeometryTotalOutputComponents: u32,
    maxFragmentInputComponents: u32,
    maxFragmentOutputAttachments: u32,
    maxFragmentDualSrcAttachments: u32,
    maxFragmentCombinedOutputResources: u32,
    maxComputeSharedMemorySize: u32,
    maxComputeWorkGroupCount: [3]u32,
    maxComputeWorkGroupInvocations: u32,
    maxComputeWorkGroupSize: [3]u32,
    subPixelPrecisionBits: u32,
    subTexelPrecisionBits: u32,
    mipmapPrecisionBits: u32,
    maxDrawIndexedIndexValue: u32,
    maxDrawIndirectCount: u32,
    maxSamplerLodBias: f32,
    maxSamplerAnisotropy: f32,
    maxViewports: u32,
    maxViewportDimensions: [2]u32,
    viewportBoundsRange: [2]f32,
    viewportSubPixelBits: u32,
    minMemoryMapAlignment: usize,
    minTexelBufferOffsetAlignment: VkDeviceSize,
    minUniformBufferOffsetAlignment: VkDeviceSize,
    minStorageBufferOffsetAlignment: VkDeviceSize,
    minTexelOffset: i32,
    maxTexelOffset: u32,
    minTexelGatherOffset: i32,
    maxTexelGatherOffset: u32,
    minInterpolationOffset: f32,
    maxInterpolationOffset: f32,
    subPixelInterpolationOffsetBits: u32,
    maxFramebufferWidth: u32,
    maxFramebufferHeight: u32,
    maxFramebufferLayers: u32,
    framebufferColorSampleCounts: VkSampleMask,
    framebufferDepthSampleCounts: VkSampleMask,
    framebufferStencilSampleCounts: VkSampleMask,
    framebufferNoAttachmentsSampleCounts: VkSampleMask,
    maxColorAttachments: u32,
    sampledImageColorSampleCounts: VkSampleMask,
    sampledImageIntegerSampleCounts: VkSampleMask,
    sampledImageDepthSampleCounts: VkSampleMask,
    sampledImageStencilSampleCounts: VkSampleMask,
    storageImageSampleCounts: VkSampleMask,
    maxSampleMaskWords: u32,
    timestampComputeAndGraphics: VkBool32,
    timestampPeriod: f32,
    maxClipDistances: u32,
    maxCullDistances: u32,
    maxCombinedClipAndCullDistances: u32,
    discreteQueuePriorities: u32,
    pointSizeRange: [2]f32,
    lineWidthRange: [2]f32,
    pointSizeGranularity: f32,
    lineWidthGranularity: f32,
    strictLines: VkBool32,
    standardSampleLocations: VkBool32,
    optimalBufferCopyOffsetAlignment: VkDeviceSize,
    optimalBufferCopyRowPitchAlignment: VkDeviceSize,
    nonCoherentAtomSize: VkDeviceSize,
};

pub const VkMemoryPropertyFlags = VkFlags;
pub const VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT: VkMemoryPropertyFlags = 0x00000001;
pub const VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT: VkMemoryPropertyFlags = 0x00000002;
pub const VK_MEMORY_PROPERTY_HOST_COHERENT_BIT: VkMemoryPropertyFlags = 0x00000004;
pub const VK_MEMORY_PROPERTY_HOST_CACHED_BIT: VkMemoryPropertyFlags = 0x00000008;
pub const VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT: VkMemoryPropertyFlags = 0x00000010;
pub const VK_MEMORY_PROPERTY_PROTECTED_BIT: VkMemoryPropertyFlags = 0x00000020;

pub const VkMemoryHeapFlags = VkFlags;
pub const VK_MEMORY_HEAP_DEVICE_LOCAL_BIT: VkMemoryHeapFlags = 0x00000001;
pub const VK_MEMORY_HEAP_MULTI_INSTANCE_BIT: VkMemoryHeapFlags = 0x00000002;

pub const VkMemoryType = extern struct {
    propertyFlags: VkMemoryPropertyFlags,
    heapIndex: u32,
};

pub const VkMemoryHeap = extern struct {
    size: VkDeviceSize,
    flags: VkMemoryHeapFlags,
};

pub const VkPhysicalDeviceMemoryProperties = extern struct {
    memoryTypeCount: u32,
    memoryTypes: [VK_MAX_MEMORY_TYPES]VkMemoryType,
    memoryHeapCount: u32,
    memoryHeaps: [VK_MAX_MEMORY_HEAPS]VkMemoryHeap,
};

pub const VkPhysicalDeviceSparseProperties = extern struct {
    residencyStandard2DBlockShape: VkBool32,
    residencyStandard2DMultisampleBlockShape: VkBool32,
    residencyStandard3DBlockShape: VkBool32,
    residencyAlignedMipSize: VkBool32,
    residencyNonResidentStrict: VkBool32,
};

pub const VkPhysicalDeviceProperties = extern struct {
    apiVersion: u32,
    driverVersion: u32,
    vendorID: u32,
    deviceID: u32,
    deviceType: VkPhysicalDeviceType,
    deviceName: [VK_MAX_PHYSICAL_DEVICE_NAME_SIZE]u8,
    pipelineCacheUUID: [VK_UUID_SIZE]u8,
    limits: VkPhysicalDeviceLimits,
    sparseProperties: VkPhysicalDeviceSparseProperties,
};

pub const PFN_vkVoidFunction = ?*const anyopaque;
pub const PFN_vkVoidFunctionNonNull = *const anyopaque;

pub const PFN_vkGetInstanceProcAddr = *const fn (?VkInstance, [*:0]const u8) callconv(.C) PFN_vkVoidFunction;
pub const PFN_vkGetDeviceProcAddr = *const fn (VkDevice, [*:0]const u8) callconv(.C) PFN_vkVoidFunction;

pub const PFN_vkCreateInstance = *const fn (?*const VkInstanceCreateInfo, ?*const VkAllocationCallbacks, *VkInstance) callconv(.C) VkResult;
pub const PFN_vkEnumerateInstanceExtensionProperties = *const fn (?[*:0]const u8, *u32, ?[*]VkExtensionProperties) callconv(.C) VkResult;
pub const PFN_vkEnumerateInstanceLayerProperties = *const fn (*u32, ?[*]VkLayerProperties) callconv(.C) VkResult;
pub const PFN_vkDestroyInstance = *const fn (VkInstance, ?*const VkAllocationCallbacks) callconv(.C) void;
pub const PFN_vkEnumeratePhysicalDevices = *const fn (VkInstance, *u32, ?[*]VkPhysicalDevice) callconv(.C) VkResult;
pub const PFN_vkGetPhysicalDeviceQueueFamilyProperties = *const fn (VkPhysicalDevice, *u32, ?[*]VkQueueFamilyProperties) callconv(.C) void;
pub const PFN_vkGetPhysicalDeviceFeatures = *const fn (VkPhysicalDevice, *VkPhysicalDeviceFeatures) callconv(.C) void;
pub const PFN_vkGetPhysicalDeviceProperties = *const fn (VkPhysicalDevice, *VkPhysicalDeviceProperties) callconv(.C) void;
pub const PFN_vkGetPhysicalDeviceMemoryProperties = *const fn (VkPhysicalDevice, *VkPhysicalDeviceMemoryProperties) callconv(.C) void;
pub const PFN_vkEnumerateDeviceExtensionProperties = *const fn (VkPhysicalDevice, ?[*:0]const u8, *u32, ?[*]VkExtensionProperties) callconv(.C) VkResult;
pub const PFN_vkCreateDevice = *const fn (VkPhysicalDevice, *const VkDeviceCreateInfo, ?*const VkAllocationCallbacks, *VkDevice) callconv(.C) VkResult;
pub const PFN_vkDestroyDevice = *const fn (VkDevice, ?*const VkAllocationCallbacks) callconv(.C) void;
pub const PFN_vkGetDeviceQueue = *const fn (VkDevice, u32, u32, *VkQueue) callconv(.C) void;
pub const PFN_vkQueueSubmit = *const fn (VkQueue, u32, ?[*]const VkSubmitInfo, ?VkFence) callconv(.C) VkResult;
pub const PFN_vkQueueWaitIdle = *const fn (VkQueue) callconv(.C) VkResult;
pub const PFN_vkCreateFence = *const fn (VkDevice, *const VkFenceCreateInfo, ?*const VkAllocationCallbacks, *VkFence) callconv(.C) VkResult;
pub const PFN_vkDestroyFence = *const fn (VkDevice, VkFence, ?*const VkAllocationCallbacks) callconv(.C) void;
pub const PFN_vkResetFences = *const fn (VkDevice, u32, *const VkFence) callconv(.C) VkResult;
pub const PFN_vkWaitForFences = *const fn (VkDevice, u32, *const VkFence, VkBool32, u64) callconv(.C) VkResult;
pub const PFN_vkGetFenceStatus = *const fn (VkDevice, VkFence) callconv(.C) VkResult;
pub const PFN_vkCreateSemaphore = *const fn (VkDevice, *const VkSemaphoreCreateInfo, ?*const VkAllocationCallbacks, *VkSemaphore) callconv(.C) VkResult;
pub const PFN_vkDestroySemaphore = *const fn (VkDevice, VkSemaphore, ?*const VkAllocationCallbacks) callconv(.C) void;
pub const PFN_vkWaitSemaphores = *const fn (VkDevice, *const VkSemaphoreWaitInfo, u64) callconv(.C) VkResult;
pub const PFN_vkSignalSemaphore = *const fn (VkDevice, *const VkSemaphoreSignalInfo) callconv(.C) VkResult;
pub const PFN_vkCreateBuffer = *const fn (VkDevice, *const VkBufferCreateInfo, ?*const VkAllocationCallbacks, *VkBuffer) callconv(.C) VkResult;
pub const PFN_vkDestroyBuffer = *const fn (VkDevice, VkBuffer, ?*const VkAllocationCallbacks) callconv(.C) void;
pub const PFN_vkGetBufferMemoryRequirements = *const fn (VkDevice, VkBuffer, *VkMemoryRequirements) callconv(.C) void;
pub const PFN_vkBindBufferMemory = *const fn (VkDevice, VkBuffer, VkDeviceMemory, VkDeviceSize) callconv(.C) VkResult;
pub const PFN_vkCreateImage = *const fn (VkDevice, *const VkImageCreateInfo, ?*const VkAllocationCallbacks, *VkImage) callconv(.C) VkResult;
pub const PFN_vkDestroyImage = *const fn (VkDevice, VkImage, ?*const VkAllocationCallbacks) callconv(.C) void;
pub const PFN_vkGetImageMemoryRequirements = *const fn (VkDevice, VkImage, *VkMemoryRequirements) callconv(.C) void;
pub const PFN_vkBindImageMemory = *const fn (VkDevice, VkImage, VkDeviceMemory, VkDeviceSize) callconv(.C) VkResult;
pub const PFN_vkCreateImageView = *const fn (VkDevice, *const VkImageViewCreateInfo, ?*const VkAllocationCallbacks, *VkImageView) callconv(.C) VkResult;
pub const PFN_vkDestroyImageView = *const fn (VkDevice, VkImageView, ?*const VkAllocationCallbacks) callconv(.C) void;
pub const PFN_vkAllocateMemory = *const fn (VkDevice, *const VkMemoryAllocateInfo, ?*const VkAllocationCallbacks, *VkDeviceMemory) callconv(.C) VkResult;
pub const PFN_vkFreeMemory = *const fn (VkDevice, VkDeviceMemory, ?*const VkAllocationCallbacks) callconv(.C) void;
pub const PFN_vkMapMemory = *const fn (VkDevice, VkDeviceMemory, VkDeviceSize, VkDeviceSize, VkMemoryMapFlags, *?*anyopaque) callconv(.C) VkResult;
pub const PFN_vkUnmapMemory = *const fn (VkDevice, VkDeviceMemory) callconv(.C) void;
pub const PFN_vkFlushMappedMemoryRanges = *const fn (VkDevice, u32, *const VkMappedMemoryRange) callconv(.C) VkResult;
pub const PFN_vkInvalidateMappedMemoryRanges = *const fn (VkDevice, u32, *const VkMappedMemoryRange) callconv(.C) VkResult;
pub const PFN_vkCmdPipelineBarrier = *const fn (VkCommandBuffer, VkPipelineStageFlags, VkPipelineStageFlags, VkDependencyFlags, u32, ?[*]const VkMemoryBarrier, u32, ?[*]const VkBufferMemoryBarrier, u32, ?[*]const VkImageMemoryBarrier) callconv(.C) void;
pub const PFN_vkCmdCopyBuffer = *const fn (VkCommandBuffer, VkBuffer, VkBuffer, u32, *const VkBufferCopy) callconv(.C) void;
pub const PFN_vkCmdCopyBufferToImage = *const fn (VkCommandBuffer, VkBuffer, VkImage, VkImageLayout, u32, *const VkBufferImageCopy) callconv(.C) void;
pub const PFN_vkCmdBindPipeline = *const fn (VkCommandBuffer, VkPipelineBindPoint, VkPipeline) callconv(.C) void;
pub const PFN_vkCmdBindDescriptorSets = *const fn (VkCommandBuffer, VkPipelineBindPoint, VkPipelineLayout, u32, u32, *const VkDescriptorSet, u32, ?[*]const u32) callconv(.C) void;
pub const PFN_vkCmdBindVertexBuffers = *const fn (VkCommandBuffer, u32, u32, *const VkBuffer, *const VkDeviceSize) callconv(.C) void;
pub const PFN_vkCmdPushConstants = *const fn (VkCommandBuffer, VkPipelineLayout, VkShaderStageFlags, u32, u32, ?*const anyopaque) callconv(.C) void;
pub const PFN_vkCmdSetViewport = *const fn (VkCommandBuffer, u32, u32, *const VkViewport) callconv(.C) void;
pub const PFN_vkCmdSetScissor = *const fn (VkCommandBuffer, u32, u32, *const VkRect2D) callconv(.C) void;
pub const PFN_vkCmdDraw = *const fn (VkCommandBuffer, u32, u32, u32, u32) callconv(.C) void;
pub const PFN_vkCmdBeginRenderPass = *const fn (VkCommandBuffer, *const VkRenderPassBeginInfo, VkSubpassContents) callconv(.C) void;
pub const PFN_vkCmdEndRenderPass = *const fn (VkCommandBuffer) callconv(.C) void;
pub const PFN_vkCmdCopyImageToBuffer = *const fn (VkCommandBuffer, VkImage, VkImageLayout, VkBuffer, u32, *const VkBufferImageCopy) callconv(.C) void;
pub const PFN_vkCreateFramebuffer = *const fn (VkDevice, *const VkFramebufferCreateInfo, ?*const VkAllocationCallbacks, *VkFramebuffer) callconv(.C) VkResult;
pub const PFN_vkDestroyFramebuffer = *const fn (VkDevice, VkFramebuffer, ?*const VkAllocationCallbacks) callconv(.C) void;
pub const PFN_vkCreateCommandPool = *const fn (VkDevice, *const VkCommandPoolCreateInfo, ?*const VkAllocationCallbacks, *VkCommandPool) callconv(.C) VkResult;
pub const PFN_vkDestroyCommandPool = *const fn (VkDevice, VkCommandPool, ?*const VkAllocationCallbacks) callconv(.C) void;
pub const PFN_vkResetCommandPool = *const fn (VkDevice, VkCommandPool, VkCommandPoolResetFlags) callconv(.C) VkResult;
pub const PFN_vkAllocateCommandBuffers = *const fn (VkDevice, *const VkCommandBufferAllocateInfo, *VkCommandBuffer) callconv(.C) VkResult;
pub const PFN_vkFreeCommandBuffers = *const fn (VkDevice, VkCommandPool, u32, *const VkCommandBuffer) callconv(.C) void;
pub const PFN_vkBeginCommandBuffer = *const fn (VkCommandBuffer, *const VkCommandBufferBeginInfo) callconv(.C) VkResult;
pub const PFN_vkEndCommandBuffer = *const fn (VkCommandBuffer) callconv(.C) VkResult;

pub const PFN_vkDestroySurfaceKHR = *const fn (VkInstance, VkSurfaceKHR, ?*const VkAllocationCallbacks) callconv(.C) void;
pub const PFN_vkGetPhysicalDeviceSurfaceSupportKHR = *const fn (VkPhysicalDevice, u32, VkSurfaceKHR, *VkBool32) callconv(.C) VkResult;
pub const PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR = *const fn (VkPhysicalDevice, VkSurfaceKHR, *VkSurfaceCapabilitiesKHR) callconv(.C) VkResult;
pub const PFN_vkGetPhysicalDeviceSurfaceFormatsKHR = *const fn (VkPhysicalDevice, VkSurfaceKHR, *u32, ?[*]VkSurfaceFormatKHR) callconv(.C) VkResult;
pub const PFN_vkGetPhysicalDeviceSurfacePresentModesKHR = *const fn (VkPhysicalDevice, VkSurfaceKHR, *u32, ?[*]VkPresentModeKHR) callconv(.C) VkResult;
pub const PFN_vkCreateSwapchainKHR = *const fn (VkDevice, *const VkSwapchainCreateInfoKHR, ?*const VkAllocationCallbacks, *VkSwapchainKHR) callconv(.C) VkResult;
pub const PFN_vkDestroySwapchainKHR = *const fn (VkDevice, VkSwapchainKHR, ?*const VkAllocationCallbacks) callconv(.C) void;
pub const PFN_vkGetSwapchainImagesKHR = *const fn (VkDevice, VkSwapchainKHR, *u32, ?[*]VkImage) callconv(.C) VkResult;
pub const PFN_vkAcquireNextImageKHR = *const fn (VkDevice, VkSwapchainKHR, u64, VkSemaphore, VkFence, *u32) callconv(.C) VkResult;
pub const PFN_vkQueuePresentKHR = *const fn (VkQueue, *const VkPresentInfoKHR) callconv(.C) VkResult;

pub const VkFence = *opaque {};

pub const VkSubmitInfo = extern struct {
    sType: VkStructureType = .SUBMIT_INFO,
    pNext: ?*const anyopaque = null,
    waitSemaphoreCount: u32 = 0,
    pWaitSemaphores: ?[*]const VkSemaphore = null,
    pWaitDstStageMask: ?[*]const VkPipelineStageFlags = null,
    commandBufferCount: u32 = 0,
    pCommandBuffers: ?[*]const VkCommandBuffer = null,
    signalSemaphoreCount: u32 = 0,
    pSignalSemaphores: ?[*]const VkSemaphore = null,
};

pub const VkTimelineSemaphoreSubmitInfo = extern struct {
    sType: VkStructureType = .TIMELINE_SEMAPHORE_SUBMIT_INFO,
    pNext: ?*const anyopaque = null,
    waitSemaphoreValueCount: u32 = 0,
    pWaitSemaphoreValues: ?[*]const u64 = null,
    signalSemaphoreValueCount: u32 = 0,
    pSignalSemaphoreValues: ?[*]const u64 = null,
};

pub const VkSemaphore = *opaque {};
pub const VkPipelineStageFlags = VkFlags;
pub const VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT: VkPipelineStageFlags = 0x00000001;
pub const VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT: VkPipelineStageFlags = 0x00000002;
pub const VK_PIPELINE_STAGE_VERTEX_INPUT_BIT: VkPipelineStageFlags = 0x00000004;
pub const VK_PIPELINE_STAGE_VERTEX_SHADER_BIT: VkPipelineStageFlags = 0x00000008;
pub const VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT: VkPipelineStageFlags = 0x00000080;
pub const VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT: VkPipelineStageFlags = 0x00000100;
pub const VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT: VkPipelineStageFlags = 0x00000200;
pub const VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT: VkPipelineStageFlags = 0x00000400;
pub const VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT: VkPipelineStageFlags = 0x00000800;
pub const VK_PIPELINE_STAGE_TRANSFER_BIT: VkPipelineStageFlags = 0x00001000;
pub const VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT: VkPipelineStageFlags = 0x00002000;
pub const VK_PIPELINE_STAGE_HOST_BIT: VkPipelineStageFlags = 0x00004000;

pub const VkQueryControlFlags = VkFlags;
pub const VkQueryPipelineStatisticFlags = VkFlags;

pub const VkAccessFlags = VkFlags;
pub const VK_ACCESS_INDIRECT_COMMAND_READ_BIT: VkAccessFlags = 0x00000001;
pub const VK_ACCESS_INDEX_READ_BIT: VkAccessFlags = 0x00000002;
pub const VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT: VkAccessFlags = 0x00000004;
pub const VK_ACCESS_UNIFORM_READ_BIT: VkAccessFlags = 0x00000008;
pub const VK_ACCESS_INPUT_ATTACHMENT_READ_BIT: VkAccessFlags = 0x00000010;
pub const VK_ACCESS_SHADER_READ_BIT: VkAccessFlags = 0x00000020;
pub const VK_ACCESS_SHADER_WRITE_BIT: VkAccessFlags = 0x00000040;
pub const VK_ACCESS_COLOR_ATTACHMENT_READ_BIT: VkAccessFlags = 0x00000080;
pub const VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT: VkAccessFlags = 0x00000100;
pub const VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT: VkAccessFlags = 0x00000200;
pub const VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT: VkAccessFlags = 0x00000400;
pub const VK_ACCESS_TRANSFER_READ_BIT: VkAccessFlags = 0x00000800;
pub const VK_ACCESS_TRANSFER_WRITE_BIT: VkAccessFlags = 0x00001000;
pub const VK_ACCESS_HOST_READ_BIT: VkAccessFlags = 0x00002000;
pub const VK_ACCESS_HOST_WRITE_BIT: VkAccessFlags = 0x00004000;
pub const VK_ACCESS_MEMORY_READ_BIT: VkAccessFlags = 0x00008000;
pub const VK_ACCESS_MEMORY_WRITE_BIT: VkAccessFlags = 0x00010000;

pub const VkFenceCreateFlags = VkFlags;
pub const VK_FENCE_CREATE_SIGNALED_BIT: VkFenceCreateFlags = 0x00000001;

pub const VkSemaphoreCreateFlags = VkFlags;

pub const VkSemaphoreWaitFlags = VkFlags;
pub const VK_SEMAPHORE_WAIT_ANY_BIT: VkSemaphoreWaitFlags = 0x00000001;

pub const VkSemaphoreType = enum(u32) {
    BINARY = 0,
    TIMELINE = 1,
};

pub const VkFenceCreateInfo = extern struct {
    sType: VkStructureType = .FENCE_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    flags: VkFenceCreateFlags = 0,
};

pub const VkSemaphoreCreateInfo = extern struct {
    sType: VkStructureType = .SEMAPHORE_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    flags: VkSemaphoreCreateFlags = 0,
};

pub const VkSemaphoreTypeCreateInfo = extern struct {
    sType: VkStructureType = .SEMAPHORE_TYPE_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    semaphoreType: VkSemaphoreType,
    initialValue: u64 = 0,
};

pub const VkSemaphoreWaitInfo = extern struct {
    sType: VkStructureType = .SEMAPHORE_WAIT_INFO,
    pNext: ?*const anyopaque = null,
    flags: VkSemaphoreWaitFlags = 0,
    semaphoreCount: u32,
    pSemaphores: *const VkSemaphore,
    pValues: *const u64,
};

pub const VkSemaphoreSignalInfo = extern struct {
    sType: VkStructureType = .SEMAPHORE_SIGNAL_INFO,
    pNext: ?*const anyopaque = null,
    semaphore: VkSemaphore,
    value: u64,
};

pub const VkCommandPoolCreateFlags = VkFlags;
pub const VK_COMMAND_POOL_CREATE_TRANSIENT_BIT: VkCommandPoolCreateFlags = 0x00000001;
pub const VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT: VkCommandPoolCreateFlags = 0x00000002;
pub const VK_COMMAND_POOL_CREATE_PROTECTED_BIT: VkCommandPoolCreateFlags = 0x00000004;

pub const VkCommandPoolResetFlags = VkFlags;

pub const VkCommandBufferUsageFlags = VkFlags;
pub const VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT: VkCommandBufferUsageFlags = 0x00000001;
pub const VK_COMMAND_BUFFER_USAGE_RENDER_PASS_CONTINUE_BIT: VkCommandBufferUsageFlags = 0x00000002;
pub const VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT: VkCommandBufferUsageFlags = 0x00000004;

pub const VkDependencyFlags = VkFlags;
pub const VK_DEPENDENCY_BY_REGION_BIT: VkDependencyFlags = 0x00000001;
pub const VK_DEPENDENCY_VIEW_LOCAL_BIT: VkDependencyFlags = 0x00000002;
pub const VK_DEPENDENCY_DEVICE_GROUP_BIT: VkDependencyFlags = 0x00000004;
pub const VkMemoryMapFlags = VkFlags;

pub const VkCommandBufferLevel = enum(u32) {
    PRIMARY = 0,
    SECONDARY = 1,
};

pub const VkCommandPoolCreateInfo = extern struct {
    sType: VkStructureType = .COMMAND_POOL_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    flags: VkCommandPoolCreateFlags = 0,
    queueFamilyIndex: u32,
};

pub const VkCommandBufferAllocateInfo = extern struct {
    sType: VkStructureType = .COMMAND_BUFFER_ALLOCATE_INFO,
    pNext: ?*const anyopaque = null,
    commandPool: VkCommandPool,
    level: VkCommandBufferLevel,
    commandBufferCount: u32,
};

pub const VkCommandBufferInheritanceInfo = extern struct {
    sType: VkStructureType = .COMMAND_BUFFER_INHERITANCE_INFO,
    pNext: ?*const anyopaque = null,
    renderPass: ?VkRenderPass = null,
    subpass: u32 = 0,
    framebuffer: ?VkFramebuffer = null,
    occlusionQueryEnable: VkBool32 = 0,
    queryFlags: VkQueryControlFlags = 0,
    pipelineStatistics: VkQueryPipelineStatisticFlags = 0,
};

pub const VkCommandBufferBeginInfo = extern struct {
    sType: VkStructureType = .COMMAND_BUFFER_BEGIN_INFO,
    pNext: ?*const anyopaque = null,
    flags: VkCommandBufferUsageFlags = 0,
    pInheritanceInfo: ?*const VkCommandBufferInheritanceInfo = null,
};

pub const VkBufferCreateFlags = VkFlags;

pub const VkBufferUsageFlags = VkFlags;
pub const VK_BUFFER_USAGE_TRANSFER_SRC_BIT: VkBufferUsageFlags = 0x00000001;
pub const VK_BUFFER_USAGE_TRANSFER_DST_BIT: VkBufferUsageFlags = 0x00000002;
pub const VK_BUFFER_USAGE_UNIFORM_TEXEL_BUFFER_BIT: VkBufferUsageFlags = 0x00000004;
pub const VK_BUFFER_USAGE_STORAGE_TEXEL_BUFFER_BIT: VkBufferUsageFlags = 0x00000008;
pub const VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT: VkBufferUsageFlags = 0x00000010;
pub const VK_BUFFER_USAGE_STORAGE_BUFFER_BIT: VkBufferUsageFlags = 0x00000020;
pub const VK_BUFFER_USAGE_INDEX_BUFFER_BIT: VkBufferUsageFlags = 0x00000040;
pub const VK_BUFFER_USAGE_VERTEX_BUFFER_BIT: VkBufferUsageFlags = 0x00000080;
pub const VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT: VkBufferUsageFlags = 0x00000100;

pub const VkBufferCreateInfo = extern struct {
    sType: VkStructureType = .BUFFER_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    flags: VkBufferCreateFlags = 0,
    size: VkDeviceSize,
    usage: VkBufferUsageFlags,
    sharingMode: VkSharingMode = .EXCLUSIVE,
    queueFamilyIndexCount: u32 = 0,
    pQueueFamilyIndices: ?[*]const u32 = null,
};

pub const VkMemoryRequirements = extern struct {
    size: VkDeviceSize,
    alignment: VkDeviceSize,
    memoryTypeBits: u32,
};

pub const VkMemoryAllocateInfo = extern struct {
    sType: VkStructureType = .MEMORY_ALLOCATE_INFO,
    pNext: ?*const anyopaque = null,
    allocationSize: VkDeviceSize,
    memoryTypeIndex: u32,
};

pub const VkMappedMemoryRange = extern struct {
    sType: VkStructureType = .MAPPED_MEMORY_RANGE,
    pNext: ?*const anyopaque = null,
    memory: VkDeviceMemory,
    offset: VkDeviceSize,
    size: VkDeviceSize,
};

pub const VkBufferCopy = extern struct {
    srcOffset: VkDeviceSize,
    dstOffset: VkDeviceSize,
    size: VkDeviceSize,
};

pub const VkImageCreateFlags = VkFlags;
pub const VK_IMAGE_CREATE_SPARSE_BINDING_BIT: VkImageCreateFlags = 0x00000001;
pub const VK_IMAGE_CREATE_SPARSE_RESIDENCY_BIT: VkImageCreateFlags = 0x00000002;
pub const VK_IMAGE_CREATE_SPARSE_ALIASED_BIT: VkImageCreateFlags = 0x00000004;
pub const VK_IMAGE_CREATE_MUTABLE_FORMAT_BIT: VkImageCreateFlags = 0x00000008;
pub const VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT: VkImageCreateFlags = 0x00000010;
pub const VK_IMAGE_CREATE_2D_ARRAY_COMPATIBLE_BIT: VkImageCreateFlags = 0x00000020;

pub const VkImageType = enum(u32) {
    @"1D" = 0,
    @"2D" = 1,
    @"3D" = 2,
};

pub const VkImageTiling = enum(u32) {
    OPTIMAL = 0,
    LINEAR = 1,
};

pub const VkSampleCountFlags = VkFlags;

pub const VkSampleCountFlagBits = enum(u32) {
    @"1" = 0x00000001,
    @"2" = 0x00000002,
    @"4" = 0x00000004,
    @"8" = 0x00000008,
    @"16" = 0x00000010,
    @"32" = 0x00000020,
    @"64" = 0x00000040,
};

pub const VK_SAMPLE_COUNT_1_BIT: VkSampleCountFlagBits = .@"1";
pub const VK_SAMPLE_COUNT_2_BIT: VkSampleCountFlagBits = .@"2";
pub const VK_SAMPLE_COUNT_4_BIT: VkSampleCountFlagBits = .@"4";
pub const VK_SAMPLE_COUNT_8_BIT: VkSampleCountFlagBits = .@"8";
pub const VK_SAMPLE_COUNT_16_BIT: VkSampleCountFlagBits = .@"16";
pub const VK_SAMPLE_COUNT_32_BIT: VkSampleCountFlagBits = .@"32";
pub const VK_SAMPLE_COUNT_64_BIT: VkSampleCountFlagBits = .@"64";

pub const VkImageLayout = enum(u32) {
    UNDEFINED = 0,
    GENERAL = 1,
    COLOR_ATTACHMENT_OPTIMAL = 2,
    DEPTH_STENCIL_ATTACHMENT_OPTIMAL = 3,
    DEPTH_STENCIL_READ_ONLY_OPTIMAL = 4,
    SHADER_READ_ONLY_OPTIMAL = 5,
    TRANSFER_SRC_OPTIMAL = 6,
    TRANSFER_DST_OPTIMAL = 7,
    PREINITIALIZED = 8,
    PRESENT_SRC_KHR = 1000001002,
    _,
};

pub const VkAttachmentLoadOp = enum(u32) {
    LOAD = 0,
    CLEAR = 1,
    DONT_CARE = 2,
};

pub const VkAttachmentStoreOp = enum(u32) {
    STORE = 0,
    DONT_CARE = 1,
    _,
};

pub const VkAttachmentDescriptionFlags = VkFlags;

pub const VkAttachmentDescription = extern struct {
    flags: VkAttachmentDescriptionFlags = 0,
    format: VkFormat,
    samples: VkSampleCountFlagBits,
    loadOp: VkAttachmentLoadOp,
    storeOp: VkAttachmentStoreOp,
    stencilLoadOp: VkAttachmentLoadOp,
    stencilStoreOp: VkAttachmentStoreOp,
    initialLayout: VkImageLayout,
    finalLayout: VkImageLayout,
};

pub const VkAttachmentReference = extern struct {
    attachment: u32,
    layout: VkImageLayout,
};

pub const VkSubpassDescriptionFlags = VkFlags;

pub const VkSubpassDescription = extern struct {
    flags: VkSubpassDescriptionFlags = 0,
    pipelineBindPoint: VkPipelineBindPoint,
    inputAttachmentCount: u32 = 0,
    pInputAttachments: ?[*]const VkAttachmentReference = null,
    colorAttachmentCount: u32,
    pColorAttachments: ?[*]const VkAttachmentReference,
    pResolveAttachments: ?[*]const VkAttachmentReference = null,
    pDepthStencilAttachment: ?*const VkAttachmentReference = null,
    preserveAttachmentCount: u32 = 0,
    pPreserveAttachments: ?[*]const u32 = null,
};

pub const VkSubpassDependency = extern struct {
    srcSubpass: u32,
    dstSubpass: u32,
    srcStageMask: VkPipelineStageFlags,
    dstStageMask: VkPipelineStageFlags,
    srcAccessMask: VkAccessFlags,
    dstAccessMask: VkAccessFlags,
    dependencyFlags: VkDependencyFlags = 0,
};

pub const VkRenderPassCreateFlags = VkFlags;

pub const VkRenderPassCreateInfo = extern struct {
    sType: VkStructureType = .RENDER_PASS_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    flags: VkRenderPassCreateFlags = 0,
    attachmentCount: u32,
    pAttachments: ?[*]const VkAttachmentDescription,
    subpassCount: u32,
    pSubpasses: [*]const VkSubpassDescription,
    dependencyCount: u32 = 0,
    pDependencies: ?[*]const VkSubpassDependency = null,
};

pub const VkSubpassContents = enum(u32) {
    INLINE = 0,
    SECONDARY_COMMAND_BUFFERS = 1,
};

pub const VK_SUBPASS_CONTENTS_INLINE: VkSubpassContents = .INLINE;
pub const VK_SUBPASS_CONTENTS_SECONDARY_COMMAND_BUFFERS: VkSubpassContents = .SECONDARY_COMMAND_BUFFERS;

pub const VkClearColorValue = extern union {
    float32: [4]f32,
    int32: [4]i32,
    uint32: [4]u32,
};

pub const VkClearDepthStencilValue = extern struct {
    depth: f32,
    stencil: u32,
};

pub const VkClearValue = extern union {
    color: VkClearColorValue,
    depthStencil: VkClearDepthStencilValue,
};

pub const VkRenderPassBeginInfo = extern struct {
    sType: VkStructureType = .RENDER_PASS_BEGIN_INFO,
    pNext: ?*const anyopaque = null,
    renderPass: VkRenderPass,
    framebuffer: VkFramebuffer,
    renderArea: VkRect2D,
    clearValueCount: u32 = 0,
    pClearValues: ?[*]const VkClearValue = null,
};

pub const VkFramebufferCreateFlags = VkFlags;

pub const VkFramebufferCreateInfo = extern struct {
    sType: VkStructureType = .FRAMEBUFFER_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    flags: VkFramebufferCreateFlags = 0,
    renderPass: VkRenderPass,
    attachmentCount: u32,
    pAttachments: [*]const VkImageView,
    width: u32,
    height: u32,
    layers: u32,
};

pub const VkImageAspectFlags = VkFlags;
pub const VK_IMAGE_ASPECT_COLOR_BIT: VkImageAspectFlags = 0x00000001;
pub const VK_IMAGE_ASPECT_DEPTH_BIT: VkImageAspectFlags = 0x00000002;
pub const VK_IMAGE_ASPECT_STENCIL_BIT: VkImageAspectFlags = 0x00000004;
pub const VK_IMAGE_ASPECT_METADATA_BIT: VkImageAspectFlags = 0x00000008;

pub const VkImageCreateInfo = extern struct {
    sType: VkStructureType = .IMAGE_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    flags: VkImageCreateFlags = 0,
    imageType: VkImageType,
    format: VkFormat,
    extent: VkExtent3D,
    mipLevels: u32,
    arrayLayers: u32,
    samples: VkSampleCountFlagBits,
    tiling: VkImageTiling,
    usage: VkImageUsageFlags,
    sharingMode: VkSharingMode = .EXCLUSIVE,
    queueFamilyIndexCount: u32 = 0,
    pQueueFamilyIndices: ?[*]const u32 = null,
    initialLayout: VkImageLayout,
};

pub const VkImageViewCreateFlags = VkFlags;

pub const VkImageViewType = enum(u32) {
    @"1D" = 0,
    @"2D" = 1,
    @"3D" = 2,
    @"1D_ARRAY" = 3,
    @"2D_ARRAY" = 4,
    CUBE = 5,
    CUBE_ARRAY = 6,
};

pub const VkComponentSwizzle = enum(u32) {
    IDENTITY = 0,
    ZERO = 1,
    ONE = 2,
    R = 3,
    G = 4,
    B = 5,
    A = 6,
};

pub const VkComponentMapping = extern struct {
    r: VkComponentSwizzle = .IDENTITY,
    g: VkComponentSwizzle = .IDENTITY,
    b: VkComponentSwizzle = .IDENTITY,
    a: VkComponentSwizzle = .IDENTITY,
};

pub const VkImageSubresourceRange = extern struct {
    aspectMask: VkImageAspectFlags,
    baseMipLevel: u32,
    levelCount: u32,
    baseArrayLayer: u32,
    layerCount: u32,
};

pub const VkImageViewCreateInfo = extern struct {
    sType: VkStructureType = .IMAGE_VIEW_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    flags: VkImageViewCreateFlags = 0,
    image: VkImage,
    viewType: VkImageViewType,
    format: VkFormat,
    components: VkComponentMapping,
    subresourceRange: VkImageSubresourceRange,
};

pub const VkImageSubresourceLayers = extern struct {
    aspectMask: VkImageAspectFlags,
    mipLevel: u32,
    baseArrayLayer: u32,
    layerCount: u32,
};

pub const VkBufferImageCopy = extern struct {
    bufferOffset: VkDeviceSize,
    bufferRowLength: u32,
    bufferImageHeight: u32,
    imageSubresource: VkImageSubresourceLayers,
    imageOffset: VkOffset3D,
    imageExtent: VkExtent3D,
};

pub const VK_REMAINING_MIP_LEVELS: u32 = 0xFFFFFFFF;
pub const VK_REMAINING_ARRAY_LAYERS: u32 = 0xFFFFFFFF;

pub const VkMemoryBarrier = extern struct {
    sType: VkStructureType = .MEMORY_BARRIER,
    pNext: ?*const anyopaque = null,
    srcAccessMask: VkAccessFlags,
    dstAccessMask: VkAccessFlags,
};

pub const VkBufferMemoryBarrier = extern struct {
    sType: VkStructureType = .BUFFER_MEMORY_BARRIER,
    pNext: ?*const anyopaque = null,
    srcAccessMask: VkAccessFlags,
    dstAccessMask: VkAccessFlags,
    srcQueueFamilyIndex: u32 = VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex: u32 = VK_QUEUE_FAMILY_IGNORED,
    buffer: VkBuffer,
    offset: VkDeviceSize,
    size: VkDeviceSize,
};

pub const VkImageMemoryBarrier = extern struct {
    sType: VkStructureType = .IMAGE_MEMORY_BARRIER,
    pNext: ?*const anyopaque = null,
    srcAccessMask: VkAccessFlags,
    dstAccessMask: VkAccessFlags,
    oldLayout: VkImageLayout,
    newLayout: VkImageLayout,
    srcQueueFamilyIndex: u32 = VK_QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex: u32 = VK_QUEUE_FAMILY_IGNORED,
    image: VkImage,
    subresourceRange: VkImageSubresourceRange,
};
pub const PFN_vkCreateDebugUtilsMessengerEXT = ?*const fn (VkInstance, *const VkDebugUtilsMessengerCreateInfoEXT, ?*const VkAllocationCallbacks, *VkDebugUtilsMessengerEXT) callconv(.C) VkResult;
pub const PFN_vkDestroyDebugUtilsMessengerEXT = ?*const fn (VkInstance, VkDebugUtilsMessengerEXT, ?*const VkAllocationCallbacks) callconv(.C) void;
pub const PFN_vkSubmitDebugUtilsMessageEXT = ?*const fn (VkInstance, VkDebugUtilsMessageSeverityFlagBitsEXT, VkDebugUtilsMessageTypeFlagsEXT, *const VkDebugUtilsMessengerCallbackDataEXT) callconv(.C) void;
pub const PFN_vkGetRefreshCycleDurationGOOGLE = ?*const fn (VkDevice, VkSwapchainKHR, *VkRefreshCycleDurationGOOGLE) callconv(.C) VkResult;
pub const PFN_vkGetPastPresentationTimingGOOGLE = ?*const fn (VkDevice, VkSwapchainKHR, *u32, ?[*]VkPastPresentationTimingGOOGLE) callconv(.C) VkResult;

pub const VkSwapchainCreateFlagsKHR = VkFlags;

pub const VkSwapchainCreateInfoKHR = extern struct {
    sType: VkStructureType = .SWAPCHAIN_CREATE_INFO_KHR,
    pNext: ?*const anyopaque = null,
    flags: VkSwapchainCreateFlagsKHR = 0,
    surface: VkSurfaceKHR,
    minImageCount: u32,
    imageFormat: VkFormat,
    imageColorSpace: VkColorSpaceKHR,
    imageExtent: VkExtent2D,
    imageArrayLayers: u32,
    imageUsage: VkImageUsageFlags,
    imageSharingMode: VkSharingMode = .EXCLUSIVE,
    queueFamilyIndexCount: u32 = 0,
    pQueueFamilyIndices: ?[*]const u32 = null,
    preTransform: VkSurfaceTransformFlagBitsKHR,
    compositeAlpha: VkCompositeAlphaFlagBitsKHR,
    presentMode: VkPresentModeKHR,
    clipped: VkBool32,
    oldSwapchain: ?VkSwapchainKHR = null,
};

pub const VkPresentInfoKHR = extern struct {
    sType: VkStructureType = .PRESENT_INFO_KHR,
    pNext: ?*const anyopaque = null,
    waitSemaphoreCount: u32 = 0,
    pWaitSemaphores: ?[*]const VkSemaphore = null,
    swapchainCount: u32,
    pSwapchains: [*]const VkSwapchainKHR,
    pImageIndices: [*]const u32,
    pResults: ?[*]VkResult = null,
};

pub const VkPresentTimeGOOGLE = extern struct {
    presentID: u32,
    desiredPresentTime: u64,
};

pub const VkPresentTimesInfoGOOGLE = extern struct {
    sType: VkStructureType = .PRESENT_TIMES_INFO_GOOGLE,
    pNext: ?*const anyopaque = null,
    swapchainCount: u32,
    pTimes: ?[*]const VkPresentTimeGOOGLE = null,
};

pub const VkRefreshCycleDurationGOOGLE = extern struct {
    refreshDuration: u64,
};

pub const VkPastPresentationTimingGOOGLE = extern struct {
    presentID: u32,
    desiredPresentTime: u64,
    actualPresentTime: u64,
    earliestPresentTime: u64,
    presentMargin: u64,
};

pub const VkDebugUtilsMessengerEXT = *opaque {};

pub const VkDebugUtilsMessengerCreateInfoEXT = extern struct {
    sType: VkStructureType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    messageSeverity: VkDebugUtilsMessageSeverityFlagsEXT,
    messageType: VkDebugUtilsMessageTypeFlagsEXT,
    pfnUserCallback: PFN_vkDebugUtilsMessengerCallbackEXT,
    pUserData: ?*anyopaque = null,
};

pub const VkDebugUtilsMessageSeverityFlagsEXT = VkFlags;
pub const VkDebugUtilsMessageTypeFlagsEXT = VkFlags;

pub const VkDebugUtilsMessageSeverityFlagBitsEXT = enum(VkDebugUtilsMessageSeverityFlagsEXT) {
    VERBOSE = 0x00000001,
    INFO = 0x00000010,
    WARNING = 0x00000100,
    ERROR = 0x00001000,
};

pub const VkDebugUtilsMessageTypeFlagBitsEXT = enum(VkDebugUtilsMessageTypeFlagsEXT) {
    GENERAL = 0x00000001,
    VALIDATION = 0x00000002,
    PERFORMANCE = 0x00000004,
};

pub const PFN_vkDebugUtilsMessengerCallbackEXT = ?*const fn (VkDebugUtilsMessageSeverityFlagBitsEXT, VkDebugUtilsMessageTypeFlagsEXT, *const VkDebugUtilsMessengerCallbackDataEXT, ?*anyopaque) callconv(.C) VkBool32;

pub const VkDebugUtilsMessengerCallbackDataEXT = extern struct {
    sType: VkStructureType = .DEBUG_UTILS_MESSENGER_CALLBACK_DATA_EXT,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    pMessageIdName: ?[*:0]const u8 = null,
    messageIdNumber: i32 = 0,
    pMessage: ?[*:0]const u8 = null,
    queueLabelCount: u32 = 0,
    pQueueLabels: ?[*]const VkDebugUtilsLabelEXT = null,
    cmdBufLabelCount: u32 = 0,
    pCmdBufLabels: ?[*]const VkDebugUtilsLabelEXT = null,
    objectCount: u32 = 0,
    pObjects: ?[*]const VkDebugUtilsObjectNameInfoEXT = null,
};

pub const VkDebugUtilsLabelEXT = extern struct {
    sType: VkStructureType = .DEBUG_UTILS_LABEL_EXT,
    pNext: ?*const anyopaque = null,
    pLabelName: ?[*:0]const u8 = null,
    color: [4]f32 = .{ 0, 0, 0, 0 },
};

pub const VkDebugUtilsObjectNameInfoEXT = extern struct {
    sType: VkStructureType = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
    pNext: ?*const anyopaque = null,
    objectType: VkObjectType,
    objectHandle: u64,
    pObjectName: ?[*:0]const u8 = null,
};

pub const VkObjectType = enum(u32) {
    UNKNOWN = 0,
};
