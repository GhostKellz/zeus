const std = @import("std");
const types = @import("types.zig");
const errors = @import("error.zig");
const device_mod = @import("device.zig");
const loader = @import("loader.zig");

pub fn createShaderModule(device: *device_mod.Device, spirv_code: []const u32) errors.Error!types.VkShaderModule {
    const device_handle = device.handle orelse return errors.Error.DeviceCreationFailed;

    var create_info = types.VkShaderModuleCreateInfo{
        .codeSize = spirv_code.len * @sizeOf(u32),
        .pCode = if (spirv_code.len == 0)
            null
        else
            @as([*]const u32, @ptrCast(spirv_code.ptr)),
    };

    var module: types.VkShaderModule = undefined;
    try errors.ensureSuccess(device.dispatch.create_shader_module(device_handle, &create_info, device.allocation_callbacks, &module));
    return module;
}

pub fn destroyShaderModule(device: *device_mod.Device, module: types.VkShaderModule) void {
    const device_handle = device.handle orelse return;
    device.dispatch.destroy_shader_module(device_handle, module, device.allocation_callbacks);
}

pub const ShaderModule = struct {
    device: *device_mod.Device,
    handle: ?types.VkShaderModule,

    pub fn init(device: *device_mod.Device, spirv_code: []const u32) errors.Error!ShaderModule {
        const module = try createShaderModule(device, spirv_code);
        return ShaderModule{ .device = device, .handle = module };
    }

    pub fn deinit(self: *ShaderModule) void {
        if (self.handle) |module| {
            destroyShaderModule(self.device, module);
            self.handle = null;
        }
    }
};

pub fn createShaderStage(module: types.VkShaderModule, stage: types.VkShaderStageFlagBits, entry_point: [*:0]const u8) types.VkPipelineShaderStageCreateInfo {
    return types.VkPipelineShaderStageCreateInfo{
        .stage = stage,
        .module = module,
        .pName = entry_point,
    };
}

// Tests ---------------------------------------------------------------------

const fake_module = @as(types.VkShaderModule, @ptrFromInt(@as(usize, 0x1234ABCD)));

const Capture = struct {
    pub var create_info: ?types.VkShaderModuleCreateInfo = null;
    pub var destroy_calls: usize = 0;

    pub fn reset() void {
        create_info = null;
        destroy_calls = 0;
    }

    pub fn stubCreateModule(_: types.VkDevice, info: *const types.VkShaderModuleCreateInfo, _: ?*const types.VkAllocationCallbacks, module: *types.VkShaderModule) callconv(.c) types.VkResult {
        create_info = info.*;
        module.* = fake_module;
        return .SUCCESS;
    }

    pub fn stubDestroyModule(_: types.VkDevice, _: types.VkShaderModule, _: ?*const types.VkAllocationCallbacks) callconv(.c) void {
        destroy_calls += 1;
    }
};

fn makeDevice() device_mod.Device {
    var device = device_mod.Device{
        .allocator = std.testing.allocator,
        .loader = undefined,
        .dispatch = std.mem.zeroes(loader.DeviceDispatch),
        .handle = @as(types.VkDevice, @ptrFromInt(@as(usize, 0xABCDEF01))),
        .allocation_callbacks = null,
    };
    device.dispatch.create_shader_module = Capture.stubCreateModule;
    device.dispatch.destroy_shader_module = Capture.stubDestroyModule;
    return device;
}

test "createShaderModule forwards code" {
    Capture.reset();
    var device = makeDevice();
    const code = [_]u32{ 0x07230203, 0x00010000, 0x000d0003 };
    const module = try createShaderModule(&device, code[0..]);
    try std.testing.expectEqual(fake_module, module);
    const info = Capture.create_info orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(code.len * @sizeOf(u32), info.codeSize);
    try std.testing.expect(info.pCode != null);
}

test "ShaderModule.deinit destroys once" {
    Capture.reset();
    var device = makeDevice();
    var module = try ShaderModule.init(&device, &.{ 0x07230203, 0x3 });
    try std.testing.expectEqual(fake_module, module.handle.?);
    module.deinit();
    try std.testing.expectEqual(@as(usize, 1), Capture.destroy_calls);
    module.deinit();
    try std.testing.expectEqual(@as(usize, 1), Capture.destroy_calls);
}

test "createShaderStage populates struct" {
    const entry: [:0]const u8 = "main";
    const stage_info = createShaderStage(fake_module, .VERTEX_BIT, entry.ptr);
    try std.testing.expectEqual(types.VkShaderStageFlagBits.VERTEX_BIT, stage_info.stage);
    try std.testing.expectEqual(fake_module, stage_info.module);
    try std.testing.expect(stage_info.pName != null);
}

test "embedded text shaders are 4-byte aligned" {
    const vert_spv align(@alignOf(u32)) = @embedFile("../../shaders/text.vert.spv");
    const frag_spv align(@alignOf(u32)) = @embedFile("../../shaders/text.frag.spv");

    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(vert_spv.ptr) % @alignOf(u32));
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(frag_spv.ptr) % @alignOf(u32));

    const vert_words = std.mem.bytesAsSlice(u32, vert_spv);
    const frag_words = std.mem.bytesAsSlice(u32, frag_spv);
    try std.testing.expect(vert_words.len > 0);
    try std.testing.expect(frag_words.len > 0);
}
