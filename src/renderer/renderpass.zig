const dispatch_types = @import("dispatch_types.zig");
const BaseDispatch = dispatch_types.BaseDispatch;
const InstanceDispatch = dispatch_types.InstanceDispatch;
const std = @import("std");
const vk = @import("vulkan");
const Device = @import("device.zig").Device;
const Swapchain = @import("swapchain.zig").Swapchain;
const CommandBuffer = @import("commandbuffer.zig").CommandBuffer;
const Image = @import("image.zig").Image;

// TODO: cache this type somewhere so that we don't remake the renderpasses
/// Info for creating a renderpass
/// collects setup so that we can just make it when binding
pub const RenderPassInfo = struct {
    pub const MAX_ATTATCHMENTS = 10;

    // images we will render to in this pass
    n_color_attachments: u32 = 0,
    color_attachments: [MAX_ATTATCHMENTS]*const Image = undefined,
    // colors to clear each image
    clear_colors: [MAX_ATTATCHMENTS][4]f32 = undefined,

    depth_attachment: ?*const Image = null,
    clear_depth: vk.ClearDepthStencilValue = undefined,

    // TODO: subpasses

    // TODO: bitflags for clear/load/store attachments
    clear_flags: ClearFlags,

    pub const ClearFlags = packed struct {
        color: bool = false,
        depth: bool = false,
        stencil: bool = false,
    };

    /// used for hashing renderpass info
    pub const Context = struct {
        //const Context = @This();
        const K = RenderPassInfo;
        pub fn hash(self: Context, k: K) u32 {
            var h = std.hash.Wyhash.init(0);
            _ = self;
            // things to hash
            // color_attachments layouts?
            // depth_attachment layout?
            // num layers (don't have yet)
            // TODO: subpasses
            // TODO: formats
            // num color_attachments
            // depth stencil value
            h.update(std.mem.asBytes(&k.n_color_attachments));
            h.update(std.mem.asBytes(&k.clear_flags));
            for (k.color_attachments[0..k.n_color_attachments]) |att| {
                h.update(std.mem.asBytes(att));
            }

            return @truncate(u32, h.final());
        }

        pub fn eql(self: Context, a: K, b: K) bool {
            _ = self;
            var match = a.n_color_attachments == b.n_color_attachments;

            if (match) {
                for (a.color_attachments[0..a.n_color_attachments]) |att, i| {
                    match = match and (att.handle == b.color_attachments[i].handle);
                }
            } else {
                return false;
            }

            return match and
                (a.depth_attachment != null and b.depth_attachment != null) and
                std.meta.eql(a.clear_flags, b.clear_flags) and true;
        }
    };
};

pub const RenderPass = struct {
    handle: vk.RenderPass,

    const Self = @This();

    // TODO: take in pass info instead
    pub fn init(
        device: Device,
        rpi: RenderPassInfo,
    ) !Self {
        var attachment_descriptions: [RenderPassInfo.MAX_ATTATCHMENTS + 1]vk.AttachmentDescription = undefined;
        var color_attachment_refs: [RenderPassInfo.MAX_ATTATCHMENTS]vk.AttachmentReference = undefined;

        for (rpi.color_attachments[0..rpi.n_color_attachments]) |at, i| {
            _ = at;
            // create a description of all the color attachments
            attachment_descriptions[i] = vk.AttachmentDescription{
                .flags = .{},
                .format = at.format,
                .samples = .{ .@"1_bit" = true },
                .load_op = if (rpi.clear_flags.color) .clear else .load,
                .store_op = .store,
                .stencil_load_op = .dont_care,
                .stencil_store_op = .dont_care,
                // TODO: add prev pass option
                .initial_layout = .@"undefined",
                // TODO: add next pass option
                .final_layout = .present_src_khr,
            };

            // create a reference to it
            color_attachment_refs[i] = .{
                .attachment = @intCast(u32, i),
                .layout = .color_attachment_optimal,
            };
        }

        var depth_attachment_ref: ?*const vk.AttachmentReference = null;

        if (rpi.depth_attachment) |at| {
            _ = at;
            attachment_descriptions[rpi.n_color_attachments] = vk.AttachmentDescription{
                .flags = .{},
                .format = device.depth_format,
                .samples = .{ .@"1_bit" = true },
                .load_op = if (rpi.clear_flags.depth) .clear else .load,
                .store_op = .store,
                .stencil_load_op = .dont_care,
                .stencil_store_op = .dont_care,
                // TODO: add prev pass option
                .initial_layout = .@"undefined",
                // TODO: add next pass option
                .final_layout = .depth_stencil_attachment_optimal,
            };

            depth_attachment_ref = &.{
                .attachment = @intCast(u32, rpi.n_color_attachments),
                .layout = .depth_stencil_attachment_optimal,
            };
        }

        const subpass = vk.SubpassDescription{
            .flags = .{},
            .pipeline_bind_point = .graphics,

            .input_attachment_count = 0,
            .p_input_attachments = undefined,

            .color_attachment_count = rpi.n_color_attachments,
            .p_color_attachments = &color_attachment_refs,

            .p_resolve_attachments = null,
            .p_depth_stencil_attachment = depth_attachment_ref,

            // attachments not used in this subpass but in others
            .preserve_attachment_count = 0,
            .p_preserve_attachments = undefined,
        };

        // TODO: make configurable
        const dependency = vk.SubpassDependency{
            .src_subpass = vk.SUBPASS_EXTERNAL,
            .dst_subpass = 0,
            .src_stage_mask = .{ .color_attachment_output_bit = true },
            .src_access_mask = .{},
            .dst_stage_mask = .{ .color_attachment_output_bit = true },
            .dst_access_mask = .{
                .color_attachment_read_bit = true,
                .color_attachment_write_bit = true,
            },
            .dependency_flags = .{},
        };

        var total_attachments: u32 = rpi.n_color_attachments;
        if (rpi.depth_attachment) |_| {
            total_attachments += 1;
        }

        const rp = try device.vkd.createRenderPass(device.logical, &.{
            .flags = .{},
            .p_next = null,
            .attachment_count = total_attachments,
            .p_attachments = @ptrCast([*]const vk.AttachmentDescription, &attachment_descriptions),
            .subpass_count = 1,
            .p_subpasses = @ptrCast([*]const vk.SubpassDescription, &subpass),
            .dependency_count = 1,
            .p_dependencies = @ptrCast([*]const vk.SubpassDependency, &dependency),
        }, null);

        return Self{
            .handle = rp,
        };
    }

    pub fn deinit(self: Self, device: Device) void {
        device.vkd.destroyRenderPass(device.logical, self.handle, null);
    }
};
