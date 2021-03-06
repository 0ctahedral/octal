//! these buffers are used for sumitting instructions for rendering a scene
const std = @import("std");
const types = @import("rendertypes.zig");

const CmdBuf = @This();
/// Commands that are submitted with a command buffer
const Command = enum {
    DrawIndexed,
    BeginRenderPass,
    EndRenderPass,
    BindPipeline,
    PushConst,
};

/// Desc that stores all the data related to the command
const CommandDecl = union(Command) {
    DrawIndexed: types.DrawIndexedDesc,
    BeginRenderPass: types.Handle,
    EndRenderPass: types.Handle,
    BindPipeline: types.Handle,
    PushConst: types.PushConstDesc,
};

/// maximum number of commands that can be held by a buffer
const MAX_COMMANDS = 32;

/// commands that have been submitted to this buffer
commands: [MAX_COMMANDS]CommandDecl = undefined,

/// last index that has been used by this buffer
idx: usize = 0,

// returns the current index and increases by one
inline fn getNextIdx(self: *CmdBuf) !usize {
    if (self.idx == self.commands.len - 1) {
        return error.MaxCommandsReached;
    }

    const ret = self.idx;
    self.idx += 1;
    return ret;
}

pub fn pushConst(self: *CmdBuf, pipeline: types.Handle, pc: anytype) !void {
    // make sure that this will actually fit
    const size = @sizeOf(@TypeOf(pc));
    if (size > 128) return error.ConstTooLarge;

    var desc = types.PushConstDesc{
        .pipeline = pipeline,
        .size = size,
    };
    std.mem.copy(u8, desc.data[0..], std.mem.asBytes(&pc));

    const idx = try self.getNextIdx();
    self.commands[idx] = .{ .PushConst = desc };
}

/// draw geometry specified with some kind of indirection
pub fn drawIndexed(self: *CmdBuf, desc: types.DrawIndexedDesc) !void {
    const idx = try self.getNextIdx();
    self.commands[idx] = .{ .DrawIndexed = desc };
}

/// begin a renderpass by description
pub fn beginRenderPass(self: *CmdBuf, handle: types.Handle) !void {
    const idx = try self.getNextIdx();
    self.commands[idx] = .{ .BeginRenderPass = handle };
}

/// end a renderpass by description
pub fn endRenderPass(self: *CmdBuf, handle: types.Handle) !void {
    const idx = try self.getNextIdx();
    self.commands[idx] = .{ .EndRenderPass = handle };
}

/// binds a shader pipeline by handle
pub fn bindPipeline(self: *CmdBuf, handle: types.Handle) !void {
    const idx = try self.getNextIdx();
    self.commands[idx] = .{ .BindPipeline = handle };
}
