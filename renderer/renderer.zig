const dispatch_types = @import("dispatch_types.zig");
const BaseDispatch = dispatch_types.BaseDispatch;
const InstanceDispatch = dispatch_types.InstanceDispatch;
const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");
const glfw = @import("glfw");
const Allocator = std.mem.Allocator;

const Device = @import("device.zig").Device;
const Queue = @import("device.zig").Queue;
const Swapchain = @import("swapchain.zig").Swapchain;
const RenderPass = @import("renderpass.zig").RenderPass;
const CommandBuffer = @import("commandbuffer.zig").CommandBuffer;
const Fence = @import("fence.zig").Fence;
const Semaphore = @import("semaphore.zig").Semaphore;
const Shader = @import("shader.zig").Shader;
const Pipeline = @import("pipeline.zig").Pipeline;
const Vertex = @import("mesh.zig").Vertex;
const Vec3 = @import("mmath").Vec3;
const Buffer = @import("buffer.zig").Buffer;

// TODO: get these from the system
const required_exts = [_][*:0]const u8{
    vk.extension_info.ext_debug_utils.name,
    "VK_KHR_surface",
    switch (builtin.target.os.tag) {
        .macos => "VK_EXT_metal_surface",
        .linux => "VK_KHR_xcb_surface",
        else => unreachable,
    },
};

// TODO: set this in a config
const required_layers = [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};

var quad_verts = [_]Vertex{
    .{ .pos = Vec3.new(-0.5, -0.5, 0).scale(20) },
    .{ .pos = Vec3.new(0.5, 0.5, 0).scale(20) },
    .{ .pos = Vec3.new(-0.5, 0.5, 0).scale(20) },
    .{ .pos = Vec3.new(0.5, -0.5, 0).scale(20) },
};

var oct_verts = [_]Vertex{
    .{ .pos = .{ .x=-1.1920928955078125e-07, .y=-1.1920928955078125e-07, .z=-1.0 } },
    .{ .pos = .{ .x=-1.1920928955078125e-07, .y=-1.0, .z=-1.1920928955078125e-07 } },
    .{ .pos = .{ .x=-1.0, .y=-1.1920928955078125e-07, .z=-1.1920928955078125e-07 } },
    .{ .pos = .{ .x=-1.1920928955078125e-07, .y=-1.1920928955078125e-07, .z=1.0 } },
    .{ .pos = .{ .x=-1.1920928955078125e-07, .y=1.0, .z=-1.1920928955078125e-07 } },
    .{ .pos = .{ .x=1.0, .y=-1.1920928955078125e-07, .z=-1.1920928955078125e-07 } },
    .{ .pos = .{ .x=-0.6666668057441711, .y=-0.6666667461395264, .z=-0.6666667461395264 } },
    .{ .pos = .{ .x=-0.6666668057441711, .y=-0.6666667461395264, .z=0.6666667461395264 } },
    .{ .pos = .{ .x=-0.6666667461395264, .y=0.6666668057441711, .z=-0.6666667461395264 } },
    .{ .pos = .{ .x=-0.6666668057441711, .y=0.6666667461395264, .z=0.6666667461395264 } },
    .{ .pos = .{ .x=0.6666667461395264, .y=-0.6666668057441711, .z=-0.6666667461395264 } },
    .{ .pos = .{ .x=0.6666668057441711, .y=-0.6666667461395264, .z=0.6666667461395264 } },
    .{ .pos = .{ .x=0.6666668057441711, .y=0.6666667461395264, .z=-0.6666667461395264 } },
    .{ .pos = .{ .x=0.6666667461395264, .y=0.6666668057441711, .z=0.6666667461395264 } },
};

var oct_inds = [_]u32{
    0, 1, 6, 1, 3, 7, 0, 2, 8, 3, 4, 9, 0, 5, 10, 3, 1, 11, 0, 4, 12, 3, 5, 13,
    1, 2, 6, 2, 0, 6, 3, 2, 7, 2, 1, 7, 2, 4, 8, 4, 0, 8, 4, 2, 9, 2, 3, 9, 5,
    1, 10, 1, 0, 10, 1, 5, 11, 5, 3, 11, 4, 5, 12, 5, 0, 12, 5, 4, 13, 4, 3, 13
};

var quad_inds = [_]u32{ 0, 1, 2, 0, 3, 1 };

var vkb: BaseDispatch = undefined;
var vki: InstanceDispatch = undefined;
var instance: vk.Instance = undefined;
var surface: vk.SurfaceKHR = undefined;
var messenger: vk.DebugUtilsMessengerEXT = undefined;
var device: Device = undefined;
var swapchain: Swapchain = undefined;
var renderpass: RenderPass = undefined;

/// monotonically increasing frame number
var frame_number: usize = 0;

/// index of the image in the swapchain we are currently
/// rendering to
var image_index: usize = 0;

/// Allocator used by the renderer
var allocator: Allocator = undefined;

/// Are we currently recreating the swapchain
/// I don't think this is really used yet but might
/// be useful when we multi thread
var recreating_swapchain = false;

/// generation of this resize
var size_gen: usize = 0;
var last_size_gen: usize = 0;

/// cached dimensions of the framebuffer
var cached_width: u32 = 0;
var cached_height: u32 = 0;

/// current dimesnsions of the framebuffer
var fb_width: u32 = 0;
var fb_height: u32 = 0;

/// Shader currently used by the pipeline
var shader: Shader = undefined;

/// pipeline currently being used
var pipeline: Pipeline = undefined;

/// the GPU side buffers that store the currenlty rendering objects
var vert_buf: Buffer = undefined;
var ind_buf: Buffer = undefined;

/// What you need for a single frame
const FrameData = struct {
    /// Semaphore signaled when the frame is finished rendering
    queue_complete_semaphore: Semaphore,
    /// semaphore signaled when the frame has been presented by the framebuffer
    image_avail_semaphore: Semaphore,
    /// fence to wait on for this frame to finish rendering
    render_fence: Fence,

    // maybe add a command pool?
    /// Command buffer for this frame
    cmdbuf: CommandBuffer,
};

/// The currently rendering frames
var frames: [2]FrameData = undefined;

/// Returns the framedata of the frame we should be on
inline fn getCurrentFrame() FrameData {
    return frames[frame_number % frames.len];
}

// initialize the renderer
pub fn init(provided_allocator: Allocator, app_name: [*:0]const u8, window: glfw.Window) !void {
    allocator = provided_allocator;

    // get proc address from glfw window
    // TODO: this should really just be a function passed into the init
    const vk_proc = @ptrCast(fn (instance: vk.Instance, procname: [*:0]const u8) callconv(.C) vk.PfnVoidFunction, glfw.getInstanceProcAddress);

    // load the base dispatch functions
    vkb = try BaseDispatch.load(vk_proc);

    const winsize = try window.getSize();
    cached_width = winsize.width;
    cached_height = winsize.height;

    fb_width = if (cached_width != 0) cached_width else 800;
    fb_height = if (cached_height != 0) cached_height else 600;
    cached_width = 0;
    cached_height = 0;

    const app_info = vk.ApplicationInfo{
        .p_application_name = app_name,
        .application_version = vk.makeApiVersion(0, 0, 0, 0),
        .p_engine_name = app_name,
        .engine_version = vk.makeApiVersion(0, 0, 0, 0),
        .api_version = vk.API_VERSION_1_2,
    };

    // create an instance
    instance = try vkb.createInstance(&.{
        .flags = .{},
        .p_application_info = &app_info,
        .enabled_layer_count = required_layers.len,
        //.enabled_layer_count = 0,
        .pp_enabled_layer_names = &required_layers,
        .enabled_extension_count = @intCast(u32, required_exts.len),
        .pp_enabled_extension_names = @ptrCast([*]const [*:0]const u8, &required_exts),
    }, null);

    // load dispatch functions which require instance
    vki = try InstanceDispatch.load(instance, vk_proc);
    errdefer vki.destroyInstance(instance, null);

    // setup debug msg
    messenger = try vki.createDebugUtilsMessengerEXT(
        instance,
        &.{
            .message_severity = .{
                .warning_bit_ext = true,
                .error_bit_ext = true,
                .info_bit_ext = true,
                //.verbose_bit_ext = true,
            },
            .message_type = .{
                .general_bit_ext = true,
                .validation_bit_ext = true,
                .performance_bit_ext = true,
            },
            .pfn_user_callback = vk_debug,
            .flags = .{},
            .p_user_data = null,
        },
        null,
    );
    errdefer vki.destroyDebugUtilsMessengerEXT(instance, messenger, null);

    // TODO: move this to system
    if ((try glfw.createWindowSurface(instance, window, null, &surface)) != @enumToInt(vk.Result.success)) {
        return error.SurfaceInitFailed;
    }
    errdefer vki.destroySurfaceKHR(instance, surface, null);

    // create a device
    // load dispatch functions which require device
    device = try Device.init(.{
        .graphics = true,
        .present = true,
        .transfer = false,
        .discrete = false,
        .compute = false,
    }, instance, vki, surface, allocator);
    errdefer device.deinit();

    swapchain = try Swapchain.init(vki, device, surface, fb_width, fb_height, allocator);
    errdefer swapchain.deinit(device, allocator);

    // create a renderpass
    renderpass = try RenderPass.init(swapchain, device, .{ .offset = .{ .x = 0, .y = 0 }, .extent = .{
        .width = fb_width,
        .height = fb_height,
    } }, .{
        .color = true,
        .depth = true,
        .stencil = true,
    }, .{ 0, 0, 0.1, 1 }, 1.0, 0);
    errdefer renderpass.deinit(device);

    // create framebuffers
    std.log.info("fbw: {} fbh: {}", .{ fb_width, fb_width });
    try recreateFramebuffers();

    // create frame objects
    // TOOD: make this part of the struct?
    for (frames) |*f| {
        f.image_avail_semaphore = try Semaphore.init(device);
        errdefer f.image_avail_semaphore.deinit(device);

        f.queue_complete_semaphore = try Semaphore.init(device);
        errdefer f.queue_complete_semaphore.deinit(device);

        f.render_fence = try Fence.init(device, true);
        errdefer f.render_fence.deinit(device);

        f.cmdbuf = try CommandBuffer.init(device, device.command_pool, true);
        errdefer f.cmdbuf.deinit(device, device.command_pool);
    }
    
    // create shader
    shader = try Shader.init(device, allocator);

    // create pipeline
    try createPipeline();
    // create some buffers
    try createBuffers();

    // upload the vertices
    try upload(device.command_pool, vert_buf, Vertex, &quad_verts);
    try upload(device.command_pool, ind_buf, u32, &quad_inds);
}

fn vk_debug(
    message_severity: vk.DebugUtilsMessageSeverityFlagsEXT.IntType,
    message_types: vk.DebugUtilsMessageTypeFlagsEXT.IntType,
    p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
    p_user_data: ?*anyopaque,
) callconv(vk.vulkan_call_conv) vk.Bool32 {
    _ = message_severity;
    _ = message_types;
    _ = p_callback_data;
    _ = p_user_data;
    std.log.info("{s}", .{p_callback_data.?.*.p_message});
    return vk.FALSE;
}

pub fn updateUniform(obj: Shader.GlobalUniformObject) void {
    shader.global_uniform_obj = obj;
}

// shutdown the renderer
pub fn deinit() void {

    // wait until rendering is done
    device.vkd.deviceWaitIdle(device.logical) catch {
        unreachable;
    };

    vert_buf.deinit(device);
    ind_buf.deinit(device);

    pipeline.deinit(device);

    shader.deinit(device);

    for (frames) |*f| {
        f.image_avail_semaphore.deinit(device);
        f.queue_complete_semaphore.deinit(device);
        f.render_fence.deinit(device);
        f.cmdbuf.deinit(device, device.command_pool);
    }

    renderpass.deinit(device);
    swapchain.deinit(device, allocator);

    device.deinit();

    vki.destroySurfaceKHR(instance, surface, null);

    vki.destroyDebugUtilsMessengerEXT(instance, messenger, null);
    vki.destroyInstance(instance, null);
}

pub fn resize(w: u32, h: u32) void {
    cached_width = w;
    cached_height = h;
    size_gen += 1;
    std.log.warn("resize triggered: {}x{}, gen: {}", .{ w, h, size_gen });
}

// TODO: fix this, i'm lazy
// also should probably be in the swapchain??
pub fn recreateFramebuffers() !void {
    std.log.info("fbw: {} fbh: {}", .{ fb_width, fb_height });
    for (swapchain.images) |img, i| {
        const attachments = [_]vk.ImageView{ img.view, swapchain.depth.view };

        swapchain.framebuffers[i] = try device.vkd.createFramebuffer(device.logical, &.{
            .flags = .{},
            .render_pass = renderpass.handle,
            .attachment_count = attachments.len,
            .p_attachments = @ptrCast([*]const vk.ImageView, &attachments),
            .width = fb_width,
            .height = fb_height,
            .layers = 1,
        }, null);
    }
}

pub fn beginFrame() !bool {
    if (recreating_swapchain) {
        std.log.info("waiting for swapchain", .{});
        try device.vkd.deviceWaitIdle(device.logical);
        return false;
    }

    if (size_gen != last_size_gen) {
        try device.vkd.deviceWaitIdle(device.logical);

        if (!try recreateSwapchain()) {
            return false;
        }

        std.log.info("resized, booting frame", .{});
        return false;
    }

    // wait for current frame
    //std.log.info("waiting for render fence", .{});
    try getCurrentFrame().render_fence.wait(device, std.math.maxInt(u64));
    try getCurrentFrame().render_fence.reset(device);
    
    getCurrentFrame().cmdbuf.reset();

    image_index = swapchain.acquireNext(device, getCurrentFrame().image_avail_semaphore, Fence{}) catch |err| {
        switch (err) {
            error.OutOfDateKHR => {
                std.log.warn("failed to aquire, booting", .{});
                return false;
            },
            else => |narrow| return narrow,
        }
    };

    //std.log.debug("image idx: {}", .{image_index});

    var cb: *CommandBuffer = &getCurrentFrame().cmdbuf;
    //cb.reset();
    try cb.begin(device, .{});

    // set the viewport
    const viewport = vk.Viewport{ .x = 0, .y = @intToFloat(f32, fb_height), .width = @intToFloat(f32, fb_width), .height = -@intToFloat(f32, fb_height), .min_depth = 0, .max_depth = 1 };
    device.vkd.cmdSetViewport(cb.handle, 0, 1, @ptrCast([*]const vk.Viewport, &viewport));

    // set the scissor (region we are clipping)
    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = .{
            .width = fb_width,
            .height = fb_height,
        },
    };

    device.vkd.cmdSetScissor(cb.handle, 0, 1, @ptrCast([*]const vk.Rect2D, &scissor));

    renderpass.begin(device, cb, swapchain.framebuffers[image_index]);

    device.vkd.cmdBindPipeline(cb.handle, .graphics, pipeline.handle);

    try shader.updateGlobalState(device, cb, pipeline, image_index);

    const offset = [_]vk.DeviceSize{0};
    device.vkd.cmdBindVertexBuffers(cb.handle, 0, 1, @ptrCast([*]const vk.Buffer, &vert_buf.handle), &offset);
    device.vkd.cmdBindIndexBuffer(cb.handle, ind_buf.handle, 0, .uint32);

    device.vkd.cmdDrawIndexed(cb.handle, quad_inds.len, 1, 0, 0, 0);

    return true;
}

pub fn endFrame() !void {
    var cb: *CommandBuffer = &getCurrentFrame().cmdbuf;
    renderpass.end(device, cb);
    try cb.end(device);

    // waits for the this stage to write
    const wait_stage = [_]vk.PipelineStageFlags{.{ .color_attachment_output_bit = true }};

    try device.vkd.queueSubmit(device.graphics.?.handle, 1, &[_]vk.SubmitInfo{.{
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast([*]const vk.CommandBuffer, &cb.handle),

        // signaled when queue is complete
        .signal_semaphore_count = 1,
        .p_signal_semaphores = getCurrentFrame().queue_complete_semaphore.ptr(),

        // wait for this before we start
        .wait_semaphore_count = 1,
        .p_wait_semaphores = getCurrentFrame().image_avail_semaphore.ptr(),

        .p_wait_dst_stage_mask = &wait_stage,
    }}, getCurrentFrame().render_fence.handle);

    cb.updateSubmitted();

    // present that shit
    swapchain.present(device, device.present.?, getCurrentFrame().queue_complete_semaphore, @intCast(u32, image_index)) catch |err| {
        switch (err) {
            error.SuboptimalKHR, error.OutOfDateKHR => {
                std.log.warn("swapchain out of date in end frame", .{});
            },
            else => |narrow| return narrow,
        }
    };
}

fn recreateSwapchain() !bool {
    if (recreating_swapchain) {
        std.log.warn("already recreating", .{});
        return false;
    }

    if (fb_width == 0 or fb_height == 0) {
        std.log.info("dimesnsion is zero so, no", .{});
        return false;
    }

    recreating_swapchain = true;
    std.log.info("recreating swapchain", .{});

    try device.vkd.deviceWaitIdle(device.logical);
    std.log.info("device done waiting", .{});


    try swapchain.recreate(vki, device, surface, cached_width, cached_height, allocator);

    fb_width = cached_width;
    fb_height = cached_height;

    cached_width = 0;
    cached_height = 0;

    last_size_gen = size_gen;

    // destroy the sync objects
    for (frames) |*f| {
        f.render_fence.deinit(device);
        f.cmdbuf.deinit(device, device.command_pool);
    }

    // create the framebuffers
    try recreateFramebuffers();

    // create the command buffers
    for (frames) |*f| {
        f.render_fence = try Fence.init(device, true);
        f.cmdbuf = try CommandBuffer.init(device, device.command_pool, true);
    }

    // reset the renderpass
    renderpass.render_area = .{ .offset = .{ .x = 0, .y = 0 }, .extent = .{
        .width = fb_width,
        .height = fb_height,
    } };

    recreating_swapchain = false;
    std.log.info("done recreating swapchain", .{});

    frame_number += 1;

    return true;
}

// TODO: move this?
fn createBuffers() !void {
    const vertex_buf_size = @sizeOf(Vertex) * 1024 * 1024;
    vert_buf = try Buffer.init(device, vertex_buf_size, .{
        .vertex_buffer_bit = true,
        .transfer_src_bit = true,
        .transfer_dst_bit = true,
    }, .{ .device_local_bit = true }, true);

    const index_buf_size = @sizeOf(u32) * 1024 * 1024;
    ind_buf = try Buffer.init(device, index_buf_size, .{
        .index_buffer_bit = true,
        .transfer_src_bit = true,
        .transfer_dst_bit = true,
    }, .{ .device_local_bit = true }, true);
}

// TODO: find a home for this
fn createPipeline() !void {
    const viewport = vk.Viewport{ .x = 0, .y = @intToFloat(f32, fb_height), .width = @intToFloat(f32, fb_width), .height = -@intToFloat(f32, fb_height), .min_depth = 0, .max_depth = 1 };

    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = .{
            .width = fb_width,
            .height = fb_height,
        },
    };

    pipeline = try Pipeline.init(device, renderpass, &[_]vk.DescriptorSetLayout{shader.global_descriptor_layout}, &shader.stage_ci, viewport, scissor, false);
}

fn upload(pool: vk.CommandPool, buffer: Buffer, comptime T: type, items: []T) !void {
    const size = @sizeOf(T) * items.len;
    const staging_buffer = try Buffer.init(
        device,
        size,
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        true,
    );
    defer staging_buffer.deinit(device);

    try staging_buffer.load(device, T, items, 0);

    try Buffer.copyTo(device, pool, device.graphics.?, staging_buffer, 0, buffer, 0, size);
}
