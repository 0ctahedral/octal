const std = @import("std");
const octal = @import("octal");
const cube = octal.mesh.cube;
const quad = octal.mesh.quad;

const renderer = octal.renderer;
const resources = octal.renderer.resources;
const input = octal.input;
const jobs = octal.jobs;
const CmdBuf = renderer.CmdBuf;

const mmath = octal.mmath;
const Vec4 = mmath.Vec4;
const Vec3 = mmath.Vec3;
const Vec2 = mmath.Vec2;
const Quat = mmath.Quat;
const Mat4 = mmath.Mat4;
const Transform = mmath.Transform;

const Skybox = @import("skybox.zig");
const Camera = @import("camera.zig");

// since this file is implicitly a struct we can store state in here
// and use methods that we expect to be defined in the engine itself.
// we can then make our app a package which is included by the engine
const App = @This();

/// The name of this app (required)
pub const name = "testbed";

const MaterialData = struct {
    albedo: Vec4 = Vec4.new(1, 1, 1, 1),
    tile: Vec2 = Vec2.new(10, 10),
};

// internal state of the app
/// transform of the quad
t: Transform = .{},

quad_verts: renderer.Handle = .{},
quad_inds: renderer.Handle = .{},

world_pass: renderer.Handle = .{},

camera: Camera = .{
    .pos = .{ .y = -10, .z = 5 },
    .fov = 60,
},

material_group: renderer.Handle = .{},
material_buffer: renderer.Handle = .{},
material_data: MaterialData = .{},
default_texture: renderer.Handle = .{},
default_sampler: renderer.Handle = .{},

cube_verts: renderer.Handle = .{},
cube_inds: renderer.Handle = .{},

simple_pipeline: renderer.Handle = .{},

last_pos: Vec2 = .{},

skybox: Skybox = .{},
file_c: jobs.Counter = .{},
file: std.fs.File = undefined,

camera_move_speed: f32 = 5.0,
pub fn init(app: *App) !void {
    // index and vertex buffer for cube
    app.cube_verts = try resources.createBuffer(
        .{
            .size = cube.uvs.len * @sizeOf(Vec2) + cube.positions.len * @sizeOf(Vec3),
            .usage = .Vertex,
        },
    );
    var offset = try renderer.updateBuffer(app.cube_verts, 0, Vec3, cube.positions);
    offset = try renderer.updateBuffer(app.cube_verts, offset, Vec2, cube.uvs);

    app.cube_inds = try resources.createBuffer(
        .{
            .size = cube.indices.len * @sizeOf(u32),
            .usage = .Index,
        },
    );
    _ = try renderer.updateBuffer(app.cube_inds, 0, u32, cube.indices);

    app.t.pos = .{ .x = 0, .y = 1, .z = 0 };
    app.t.scale = .{ .x = 1, .y = 1, .z = 1 };

    // setup the quad

    app.quad_verts = try resources.createBuffer(
        .{
            .size = quad.uvs.len * @sizeOf(Vec2) + quad.positions.len * @sizeOf(Vec3),
            .usage = .Vertex,
        },
    );
    offset = try renderer.updateBuffer(app.quad_verts, 0, Vec3, quad.positions);
    offset = try renderer.updateBuffer(app.quad_verts, offset, Vec2, quad.uvs);

    app.quad_inds = try resources.createBuffer(
        .{
            .size = quad.indices.len * @sizeOf(u32),
            .usage = .Index,
        },
    );
    _ = try renderer.updateBuffer(app.quad_inds, 0, u32, quad.indices);

    // setup the camera
    try app.camera.init();
    app.camera.aspect = @intToFloat(f32, renderer.w) / @intToFloat(f32, renderer.h);

    // setup the material
    app.material_group = try resources.createBindingGroup(&.{
        .{ .binding_type = .Buffer },
        .{ .binding_type = .Texture },
        .{ .binding_type = .Sampler },
    });

    app.material_buffer = try resources.createBuffer(
        .{
            .size = @sizeOf(MaterialData),
            .usage = .Uniform,
        },
    );
    _ = try renderer.updateBuffer(app.material_buffer, 0, MaterialData, &[_]MaterialData{app.material_data});

    const tex_dimension: u32 = 2;
    const channels: u32 = 4;
    var pixels: [tex_dimension * tex_dimension * channels]u8 = .{
        0, 255, 0, 255, // 0, 0
        255, 255, 255, 255, // 0, 1
        255, 255, 255, 255, // 1, 0
        0, 255, 0, 255, // 1, 1
    };

    app.default_texture = try resources.createTexture(.{
        .width = tex_dimension,
        .height = tex_dimension,
        .channels = channels,
        .flags = .{},
        .texture_type = .@"2d",
    }, &pixels);

    app.default_sampler = try resources.createSampler(.{
        .filter = .nearest,
        .repeat = .wrap,
        .compare = .greater,
    });

    try resources.updateBindings(app.material_group, &[_]resources.BindingUpdate{
        .{ .binding = 0, .handle = app.material_buffer },
        .{ .binding = 1, .handle = app.default_texture },
        .{ .binding = 2, .handle = app.default_sampler },
    });

    app.world_pass = try resources.createRenderPass(.{
        .clear_color = .{ 0.75, 0.49, 0.89, 1.0 },
        .clear_depth = 1.0,
        .clear_stencil = 1.0,
        .clear_flags = .{ .depth = true },
    });

    // create our shader pipeline
    app.simple_pipeline = try resources.createPipeline(.{
        .stages = &.{
            .{
                .bindpoint = .Vertex,
                .path = "testbed/assets/default.vert.spv",
            },
            .{
                .bindpoint = .Fragment,
                .path = "testbed/assets/default.frag.spv",
            },
        },
        .binding_groups = &.{ app.camera.group, app.material_group },
        .renderpass = app.world_pass,
        .cull_mode = .back,
        .vertex_inputs = &.{ .Vec3, .Vec2 },
        .push_const_size = @sizeOf(Mat4),
    });

    app.skybox = try Skybox.init(app.camera, true);

    // hot reload this bitch
    try jobs.run(jobs.statCheckOpen, .{ "test/file.txt", &app.file }, &app.file_c);
}

pub fn update(app: *App, dt: f64) !void {
    if (app.file_c.val() == 0) {
        try app.skybox.onFileChange(&app.file);
        try jobs.run(jobs.statCheckOpen, .{ "test/file.txt", &app.file }, &app.file_c);
    }

    // camera stuff
    var ivec = Vec3{};
    if (input.keyIs(.right, .down) or input.keyIs(.d, .down)) {
        ivec = ivec.add(app.camera.rot.rotate(Vec3.RIGHT));
    }
    if (input.keyIs(.left, .down) or input.keyIs(.a, .down)) {
        ivec = ivec.add(app.camera.rot.rotate(Vec3.LEFT));
    }
    if (input.keyIs(.up, .down) or input.keyIs(.w, .down)) {
        ivec = ivec.add(app.camera.rot.rotate(Vec3.FORWARD));
    }
    if (input.keyIs(.down, .down) or input.keyIs(.s, .down)) {
        ivec = ivec.add(app.camera.rot.rotate(Vec3.BACKWARD));
    }
    if (input.keyIs(.q, .down)) {
        ivec = ivec.add(Vec3.UP);
    }
    if (input.keyIs(.e, .down)) {
        ivec = ivec.add(Vec3.DOWN);
    }

    if (input.keyIs(.v, .press)) {
        app.camera.fov += 10;
        std.log.debug("fov changed to: {d:.2}", .{app.camera.fov});
    }
    if (input.keyIs(.c, .press)) {
        app.camera.fov -= 10;
        std.log.debug("fov changed to: {d:.2}", .{app.camera.fov});
    }

    const mag = ivec.len();
    if (mag > 0.0) {
        app.camera.pos = app.camera.pos.add(ivec.scale(app.camera_move_speed * @floatCast(f32, dt) / mag));
        //std.log.debug("x: {d:.2} y: {d:.2} z: {d:.2}", .{
        //    app.camera.pos.x,
        //    app.camera.pos.y,
        //    app.camera.pos.z
        //});
    }

    const left = input.getMouse().getButton(.left);
    if (left.action == .drag) {
        const ddrag = left.drag.sub(app.last_pos);
        app.camera.fpsRot(ddrag);
        app.last_pos = left.drag;
    } else {
        app.last_pos = .{};
    }
    try app.camera.update();

    // make that lil cube spin
    app.t.rot = app.t.rot
        .mul(Quat.fromAxisAngle(Vec3.FORWARD, mmath.util.rad(30) * @floatCast(f32, dt)))
        .mul(Quat.fromAxisAngle(Vec3.UP, mmath.util.rad(30) * @floatCast(f32, dt)));
    app.t.pos = Vec3.UP.scale(1 + @sin(@intToFloat(f32, renderer.frame) * 0.03));
}

const floor_mat = Mat4.scale(.{ .x = 100, .y = 100, .z = 100 })
    .mul(Mat4.translate(.{ .y = -1 }));

pub fn render(app: *App) !void {
    var cmd = renderer.getCmdBuf();

    // render skybox
    try app.skybox.draw(&cmd);
    // then render the geometry

    try cmd.beginRenderPass(app.world_pass);

    try cmd.bindPipeline(app.simple_pipeline);

    // draw the floor
    try cmd.pushConst(app.simple_pipeline, floor_mat);

    try cmd.drawIndexed(.{
        .count = quad.indices.len,
        .vertex_handle = app.quad_verts,
        .index_handle = app.quad_inds,
        .offsets = &.{ 0, 4 * @sizeOf(Vec3) },
    });

    // draw the magic cube
    try cmd.pushConst(app.simple_pipeline, app.t.mat());

    try cmd.drawIndexed(.{
        .count = cube.indices.len,
        .vertex_handle = app.cube_verts,
        .index_handle = app.cube_inds,
        .offsets = &.{ 0, 8 * @sizeOf(Vec3) },
    });

    try cmd.endRenderPass(app.world_pass);

    try renderer.submit(cmd);
}

pub fn deinit(app: *App) void {
    _ = app;
    std.log.info("{s}: deinitialized", .{App.name});
}

pub fn onResize(app: *App, w: u16, h: u16) void {
    app.camera.aspect = @intToFloat(f32, w) / @intToFloat(f32, h);
}
