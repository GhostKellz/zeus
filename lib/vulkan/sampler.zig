const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const loader = @import("loader.zig");

pub const SamplerOptions = struct {
    mag_filter: types.VkFilter = .LINEAR,
    min_filter: types.VkFilter = .LINEAR,
    mipmap_mode: types.VkSamplerMipmapMode = .LINEAR,
    address_mode_u: types.VkSamplerAddressMode = .CLAMP_TO_EDGE,
    address_mode_v: types.VkSamplerAddressMode = .CLAMP_TO_EDGE,
    address_mode_w: types.VkSamplerAddressMode = .CLAMP_TO_EDGE,
    mip_lod_bias: f32 = 0.0,
    anisotropy_enable: bool = false,
    max_anisotropy: f32 = 1.0,
    compare_enable: bool = false,
    compare_op: types.VkCompareOp = .ALWAYS,
    min_lod: f32 = 0.0,
    max_lod: f32 = std.math.inf(f32),
    border_color: types.VkBorderColor = .INT_OPAQUE_BLACK,
    unnormalized_coordinates: bool = false,
};

pub fn createSampler(device: *device_mod.Device, options: SamplerOptions) errors.Error!types.VkSampler {
    const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;

    var create_info = types.VkSamplerCreateInfo{
        .magFilter = options.mag_filter,
        .minFilter = options.min_filter,
        .mipmapMode = options.mipmap_mode,
        .addressModeU = options.address_mode_u,
        .addressModeV = options.address_mode_v,
        .addressModeW = options.address_mode_w,
        .mipLodBias = options.mip_lod_bias,
        .anisotropyEnable = if (options.anisotropy_enable) 1 else 0,
        .maxAnisotropy = options.max_anisotropy,
        .compareEnable = if (options.compare_enable) 1 else 0,
        .compareOp = options.compare_op,
        .minLod = options.min_lod,
        .maxLod = options.max_lod,
        .borderColor = options.border_color,
        .unnormalizedCoordinates = if (options.unnormalized_coordinates) 1 else 0,
    };

    var sampler: types.VkSampler = undefined;
    try errors.ensureSuccess(device.dispatch.create_sampler(device_handle, &create_info, device.allocation_callbacks, &sampler));
    return sampler;
}

pub const Sampler = struct {
    device: *device_mod.Device,
    handle: ?types.VkSampler,
    options: SamplerOptions,

    pub fn init(device: *device_mod.Device, options: SamplerOptions) errors.Error!Sampler {
        const handle = try createSampler(device, options);
        return Sampler{ .device = device, .handle = handle, .options = options };
    }

    pub fn deinit(self: *Sampler) void {
        const handle = self.handle orelse return;
        const device_handle = self.device.handle orelse return;
        self.device.dispatch.destroy_sampler(device_handle, handle, self.device.allocation_callbacks);
        self.handle = null;
    }
};

// Tests ---------------------------------------------------------------------

const fake_sampler = @as(types.VkSampler, @ptrFromInt(@as(usize, 0xCAFE)));

const Capture = struct {
    pub var create_info: ?types.VkSamplerCreateInfo = null;
    pub var destroy_calls: usize = 0;

    pub fn reset() void {
        create_info = null;
        destroy_calls = 0;
    }

    pub fn stubCreate(_: types.VkDevice, info: *const types.VkSamplerCreateInfo, _: ?*const types.VkAllocationCallbacks, sampler: *types.VkSampler) callconv(.c) types.VkResult {
        create_info = info.*;
        sampler.* = fake_sampler;
        return .SUCCESS;
    }

    pub fn stubDestroy(_: types.VkDevice, _: types.VkSampler, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {
        destroy_calls += 1;
    }
};

fn makeDevice() device_mod.Device {
    var device = device_mod.Device{
        .allocator = std.testing.allocator,
        .loader = undefined,
        .dispatch = undefined,
        .handle = @as(types.VkDevice, @ptrFromInt(@as(usize, 0x20))),
        .allocation_callbacks = null,
    };
    device.dispatch.create_sampler = Capture.stubCreate;
    device.dispatch.destroy_sampler = Capture.stubDestroy;
    return device;
}

test "createSampler populates info" {
    Capture.reset();
    var device = makeDevice();
    const sampler = try createSampler(&device, .{
        .anisotropy_enable = true,
        .max_anisotropy = 8.0,
        .address_mode_u = .REPEAT,
        .address_mode_v = .MIRRORED_REPEAT,
    });
    try std.testing.expectEqual(fake_sampler, sampler);
    const info = Capture.create_info orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(types.VkBool32, 1), info.anisotropyEnable);
    try std.testing.expectEqual(types.VkSamplerAddressMode.REPEAT, info.addressModeU);
    try std.testing.expectEqual(types.VkSamplerAddressMode.MIRRORED_REPEAT, info.addressModeV);
}

test "Sampler.init and deinit destroy handle" {
    Capture.reset();
    var device = makeDevice();
    var sampler = try Sampler.init(&device, .{});
    defer sampler.deinit();
    try std.testing.expectEqual(fake_sampler, sampler.handle.?);
    try std.testing.expectEqual(@as(usize, 0), Capture.destroy_calls);
    sampler.deinit();
    try std.testing.expectEqual(@as(usize, 1), Capture.destroy_calls);
}
