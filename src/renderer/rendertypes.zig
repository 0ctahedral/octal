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

    // bindings: []const Handle,
};
pub const PipelineDesc = struct {

    /// render pass this pipeline is going to draw with
    // render_pass: Handle,
    stages: []const StageDesc,
};
