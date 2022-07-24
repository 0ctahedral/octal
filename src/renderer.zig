//! Renderer front end

const std = @import("std");
const Allocator = std.mem.Allocator;
const Platform = @import("platform.zig");
const Events = @import("events.zig");
const App = @import("app");
const RingBuffer = @import("containers.zig").RingBuffer;

const Transform = @import("math.zig").Transform;

// TODO: make private and depend on which backend we are using
pub const backend = @import("renderer/vulkan/renderer.zig");

pub const CmdBuf = @import("renderer/cmdbuf.zig");

pub fn init(_allocator: Allocator, app_name: [*:0]const u8, window: Platform.Window) !void {
    try backend.init(_allocator, app_name, window);

    // register for resize event
    try Events.register(Events.EventType.WindowResize, onResize);

    submitted_cmds = RingBuffer(CmdBuf, 32).init();
}

var submitted_cmds: RingBuffer(CmdBuf, 32) = undefined;

// TODO: make a command pool api
pub fn getCmdBuf() CmdBuf {
    return .{};
}

/// Submit a command buffer to be run by the renderer
pub fn submit(cmdbuf: CmdBuf) !void {
    try submitted_cmds.push(cmdbuf);
}

pub fn drawFrame() !void {
    // regardless of control flow we need to reset the command buffer
    // at the end of this function
    defer submitted_cmds.clear();

    if (resizing) {
        frames_since_resize += 1;

        if (frames_since_resize >= 30) {
            backend.onResize(w, h);
            frames_since_resize = 0;
            resizing = false;
        } else {
            return;
        }
    }

    if (try backend.beginFrame()) {
        while (submitted_cmds.pop()) |cmdbuf| {
            try backend.submit(cmdbuf);
        }
        try backend.endFrame();
    }
}

pub fn deinit() void {
    backend.deinit();
}

// State for resizing
var frames_since_resize: usize = 0;
var w: u16 = 800;
var h: u16 = 600;
var resizing = false;

pub fn onResize(ev: Events.Event) bool {
    frames_since_resize = 0;
    w = ev.WindowResize.w;
    h = ev.WindowResize.h;
    resizing = true;

    // other systems might need this event
    return true;
}

pub const types = @import("renderer/rendertypes.zig");
pub const Handle = types.Handle;
pub const BufferDesc = types.BufferDesc;
pub const RenderPassDesc = types.RenderPassDesc;
pub const PipelineDesc = types.PipelineDesc;

pub const Resources = backend.Resources;

/// uploades data to a buffer and returns the resulting offest in bytes
// TODO: make this just in the Resources
pub fn updateBuffer(
    handle: types.Handle,
    offset: usize,
    comptime T: type,
    data: []const T,
) !usize {
    const size = @sizeOf(T) * data.len;
    try backend.Resources.updateBuffer(
        handle,
        offset,
        @ptrCast([*]const u8, data),
        size,
    );
    return size + offset;
}
