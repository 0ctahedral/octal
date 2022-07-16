/// Identifier for a device resource
/// the default values in the struct indicate a null handle
pub const Handle = struct {
    /// index of this resource
    resource: u32 = 0,
};

/// data for a draw call
/// right now it can only be indexed
pub const DrawDesc = struct {
    /// number of indices to draw
    count: u32,
    /// handle for the buffer we are drawing from
    vertex_handle: Handle,
    index_handle: Handle,
};

// buffer stuff
pub const BufferDesc = struct {
    pub const Usage = enum {
        Vertex,
        Index,
        Storage,
    };
    usage: Usage,
    size: usize,
};

pub const TextureDesc = struct {
    width: u32,
    height: u32,
    depth: u32 = 1,
    channels: u32,
    flags: packed struct {
        /// is this texture be transparent?
        transparent: bool = false,
        /// can this texture be written to?
        writable: bool = false,
    },
};

pub const SamplerDesc = struct {
    pub const Filter = enum {
        /// grab the nearest texel to the sample
        nearest,
        /// sample four nearest texels
        bilinear,
        /// sample four nearest texels on two mip map levels
        trilinear,
        /// ???
        anisotropic,
    };

    pub const Repeat = enum {
        /// wrap the texure by repeating (tiled)
        wrap,
        /// doesn't tile
        clamp,
    };

    pub const Compare = enum {
        never,
        less,
        less_eq,
        greater,
        greater_eq,
    };

    /// how should the texture be filtered when sampled
    filter: Filter,

    /// how the texture is repeated with uvs outside the range
    repeat: Repeat,

    /// how the sampler should compare mipmap values
    compare: Compare,
};

// TODO: add more details like attachments and subpasses and stuff
pub const RenderPassDesc = struct {
    /// color this renderpass should clear the rendertarget to
    clear_color: [4]f32,
    /// value the renderpass should clear the rendertarget depth bufffer to
    clear_depth: f32,
    /// value the renderpass should clear the rendertarget stencil buffer to
    clear_stencil: u32,
    /// flags for which values should actully be cleared
    clear_flags: packed struct {
        color: bool = false,
        depth: bool = false,
        stencil: bool = false,
    },
};

/// Describes a shader pipeline for drawing
pub const StageDesc = struct {
    bindpoint: enum {
        Vertex,
        Fragment,
    },
    path: []const u8,
};
pub const PipelineDesc = struct {
    /// render pass this pipeline is going to draw with
    // render_pass: Handle,
    stages: []const StageDesc = undefined,

    // TODO: add multiple binding groups?
    /// groups of bindings for the shader
    bindings: []const Handle = undefined,

    // TODO: add this
    // renderpass: Handle,
};
