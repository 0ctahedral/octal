const std = @import("std");
const vk = @import("vulkan");
const Device = @import("device.zig").Device;
const Queue = @import("device.zig").Queue;
//const Fence = @import("fence.zig").Fence;
const CommandBuffer = @import("commandbuffer.zig").CommandBuffer;
const Renderer = @import("../renderer.zig");

pub const Buffer = struct {
    handle: vk.Buffer,
    usage: vk.BufferUsageFlags,
    mem: vk.DeviceMemory = .null_handle,

    locked: bool = false,

    index: u32,
    mem_flags: vk.MemoryPropertyFlags,

    size: usize,

    const Self = @This();

    pub fn init(
        dev: Device,
        size: usize,
        usage: vk.BufferUsageFlags,
        mem_flags: vk.MemoryPropertyFlags,
        bind_on_create: bool,
    ) !Self {
        var self: Self = undefined;
        self.size = size;
        self.usage = usage;
        self.mem_flags = mem_flags;

        // create handle
        self.handle = try dev.vkd.createBuffer(dev.logical, &.{
            .flags = .{},
            .size = size,
            .usage = usage,
            // only used in one queue
            .sharing_mode = .exclusive,
            .queue_family_index_count = 0,
            .p_queue_family_indices = undefined,
        }, null);

        // get memory
        const reqs = dev.vkd.getBufferMemoryRequirements(dev.logical, self.handle);

        // get memory index TODO: move to device?
        self.index = try dev.findMemoryIndex(reqs.memory_type_bits, mem_flags);

        self.mem = try dev.vkd.allocateMemory(dev.logical, &.{
            .allocation_size = reqs.size,
            .memory_type_index = self.index,
        }, null);

        if (bind_on_create) {
            try self.bind(dev);
        }

        return self;
    }

    pub fn deinit(
        self: Self,
        dev: Device,
    ) void {
        dev.vkd.freeMemory(dev.logical, self.mem, null);
        dev.vkd.destroyBuffer(dev.logical, self.handle, null);
    }

    pub fn lock(
        self: Self,
        dev: Device,
        offset: usize,
        size: usize,
        flags: u32,
    ) !*anyopaque {
        const data = try dev.vkd.mapMemory(dev.logical, self.mem, offset, size, flags);
        self.locked = true;
        return data;
    }

    pub fn unlock(
        self: Self,
        dev: Device,
    ) !void {
        dev.vkd.unmapMemory(dev.logical, self.mem);
        self.locked = false;
    }

    /// map buffer memory and copy into it
    pub fn load(
        self: Self,
        dev: Device,
        comptime T: type,
        data: []const T,
        offset: usize,
    ) !void {
        const dest = try dev.vkd.mapMemory(dev.logical, self.mem, @sizeOf(T) * offset, @sizeOf(T) * data.len, .{});
        const ptr = @ptrCast([*]T, @alignCast(@alignOf(T), dest));

        for (data) |item, i| {
            ptr[i] = item;
        }

        dev.vkd.unmapMemory(dev.logical, self.mem);
    }

    /// create a temporary staging buffer and use that to load into gpu side buffer
    pub fn stagedLoad(self: Self, comptime T: type, items: []const T, offset: usize) !void {
        const size = @sizeOf(T) * items.len;
        const staging_buffer = try Buffer.init(
            Renderer.device,
            size,
            .{ .transfer_src_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
            true,
        );
        defer staging_buffer.deinit(Renderer.device);

        try staging_buffer.load(Renderer.device, T, items, 0);

        try Buffer.copyTo(Renderer.device, Renderer.device.command_pool, Renderer.device.graphics.?, staging_buffer, 0, self, offset, size);
    }

    pub fn bind(self: Self, dev: Device) !void {
        try dev.vkd.bindBufferMemory(dev.logical, self.handle, self.mem, 0);
    }

    pub fn resize(
        self: *Self,
        dev: Device,
        pool: vk.CommandPool,
        queue: Queue,
        new_size: usize,
    ) !void {
        // make a new buffer
        var new_buf = try init(
            dev,
            new_size,
            self.usage,
            self.mem_flags,
            false,
        );

        try new_buf.bind(dev);

        try copyTo(self, new_buf, dev, pool, .null_handle, queue.handle, 0, 0, self.size);

        try dev.vkd.deviceWaitIdle(dev.logical);

        self = new_buf;
    }

    pub fn copyTo(
        dev: Device,
        pool: vk.CommandPool,
        queue: Queue,
        src: Self,
        src_offset: usize,
        dest: Self,
        dest_offset: usize,
        size: usize,
    ) !void {
        var cmdbuf = try CommandBuffer.beginSingleUse(dev, pool);
        const region = vk.BufferCopy{
            .src_offset = src_offset,
            .dst_offset = dest_offset,
            .size = size,
        };
        dev.vkd.cmdCopyBuffer(cmdbuf.handle, src.handle, dest.handle, 1, @ptrCast([*]const vk.BufferCopy, &region));

        try cmdbuf.endSingleUse(dev, pool, queue.handle);
    }
};
