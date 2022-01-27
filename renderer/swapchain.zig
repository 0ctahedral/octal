const std = @import("std");
const vk = @import("vulkan");
const dispatch_types = @import("dispatch_types.zig");
const InstanceDispatch = dispatch_types.InstanceDispatch;
const Device = @import("device.zig").Device;
const Image = @import("image.zig").Image;

pub const Swapchain = struct {
    surface_format: vk.SurfaceFormatKHR = undefined,
    // defaults to fifo which all devices support
    present_mode: vk.PresentModeKHR = .fifo_khr,
    extent: vk.Extent2D = undefined,

    handle: vk.SwapchainKHR = .null_handle,

    images: []Image = undefined,
    framebuffers: []vk.Framebuffer = undefined,

    const Self = @This();

    /// initialize/create a swapchian object
    pub fn init(vki: InstanceDispatch, dev: Device, surface: vk.SurfaceKHR, extent: vk.Extent2D, allocator: std.mem.Allocator) !Self {
        return try create(vki, dev, surface, extent, allocator);
    }

    /// shutdown a swapchian object
    pub fn deinit(self: Self, dev: Device, allocator: std.mem.Allocator) void {
        self.destroy(dev, allocator);
    }

    /// create our swapchain
    fn create(vki: InstanceDispatch, dev: Device, surface: vk.SurfaceKHR, extent: vk.Extent2D, allocator: std.mem.Allocator) !Self {
        var self: Self = .{};

        // find the format
        const preferred_format = vk.SurfaceFormatKHR{
            .format = .b8g8r8a8_srgb,
            .color_space = .srgb_nonlinear_khr,
        };
        var surface_formats: [32]vk.SurfaceFormatKHR = undefined;
        var count: u32 = undefined;
        _ = try vki.getPhysicalDeviceSurfaceFormatsKHR(dev.physical, surface, &count, surface_formats[0..]);

        self.surface_format = surface_formats[0];

        for (surface_formats[0..count]) |sfmt| {
            if (std.meta.eql(sfmt, preferred_format)) {
                self.surface_format = sfmt;
                break;
            }
        }

        std.log.info("chosen surface format: {}", .{self.surface_format});

        // find present mode
        var present_modes: [32]vk.PresentModeKHR = undefined;
        _ = try vki.getPhysicalDeviceSurfacePresentModesKHR(dev.physical, surface, &count, present_modes[0..]);

        for (present_modes[0..count]) |mode| {
            // if we can get mailbox that's ideal
            if (mode == .mailbox_khr) {
                self.present_mode = mode;
                break;
            }
        }

        std.log.info("chosen present mode: {}", .{self.present_mode});

        // get the actual extent of the window
        const caps = try vki.getPhysicalDeviceSurfaceCapabilitiesKHR(dev.physical, surface);

        const actual_extent =
            if (caps.current_extent.width != 0xFFFF_FFFF)
            caps.current_extent
        else
            vk.Extent2D{
                .width = std.math.clamp(extent.width, caps.min_image_extent.width, caps.max_image_extent.width),
                .height = std.math.clamp(extent.height, caps.min_image_extent.height, caps.max_image_extent.height),
            };

        if (actual_extent.width == 0 or actual_extent.height == 0) {
            return error.InvalidSurfaceDimensions;
        }

        self.extent = actual_extent;

        std.log.info("given extent: {} actual extent: {}", .{ extent, self.extent });

        // get the image count
        var image_count = caps.min_image_count + 1;
        if (caps.max_image_count > 0) {
            image_count = std.math.min(image_count, caps.max_image_count);
        }
        std.log.info("image count: {}", .{image_count});

        const qfi = [_]u32{ dev.graphics.?.idx, dev.present.?.idx };
        const sharing_mode: vk.SharingMode = if (dev.graphics.?.idx == dev.present.?.idx) .exclusive else .concurrent;

        // create the handle
        self.handle = try dev.vkd.createSwapchainKHR(dev.logical, &.{
            .flags = .{},
            .surface = surface,
            .min_image_count = image_count,
            .image_format = self.surface_format.format,
            .image_color_space = self.surface_format.color_space,
            .image_extent = self.extent,
            // multiple for vr?
            .image_array_layers = 1,
            .image_usage = .{ .color_attachment_bit = true },
            .image_sharing_mode = sharing_mode,
            .queue_family_index_count = qfi.len,
            .p_queue_family_indices = &qfi,
            .pre_transform = caps.current_transform,
            .composite_alpha = .{ .opaque_bit_khr = true },
            .present_mode = self.present_mode,
            .clipped = vk.TRUE,
            .old_swapchain = self.handle,
        }, null);

        // make the images and views
        var imgs: [8]vk.Image = undefined;
        _ = try dev.vkd.getSwapchainImagesKHR(dev.logical, self.handle, &count, null);
        _ = try dev.vkd.getSwapchainImagesKHR(dev.logical, self.handle, &count, imgs[0..]);
        self.images = try allocator.alloc(Image, count);

        for (imgs[0..count]) |img, i| {
            self.images[i] = try Image.initManaged(dev, img, self.surface_format.format);
        }

        // allocate the framebuffers
        self.framebuffers = try allocator.alloc(vk.Framebuffer, count);

        return self;
    }

    /// destroy our swapchain
    fn destroy(self: Self, dev: Device, allocator: std.mem.Allocator) void {
        for (self.images) |img| {
            img.deinit(dev);
        }
        allocator.free(self.framebuffers);
        allocator.free(self.images);
        dev.vkd.destroySwapchainKHR(dev.logical, self.handle, null);
    }

    pub fn recreate(
        self: *Self,
        vki: InstanceDispatch,
        dev: Device,
        surface: vk.SurfaceKHR,
        allocator: std.mem.Allocator
    ) !void {
        self.destroy(dev, allocator);
        self.* = try create(vki, dev, surface, self.extent, allocator);
    }

    /// present an image to the swapchain
    pub fn present() void {}
};
