const mem = @import("std").mem;

extern const __kernel_end: u8;

pub var ufa: ?UnboundedForeverAllocator = null;

pub fn ufaInit() void {
    ufa = .{
        .next_addr = @intFromPtr(&__kernel_end),
    };
}

const UnboundedForeverAllocator = struct {
    next_addr: usize,

    pub const vtable: mem.Allocator.VTable = .{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    pub fn allocator(self: *@This()) mem.Allocator {
        return .{
            .ptr = &self.next_addr,
            .vtable = &vtable,
        };
    }

    pub fn alloc(ctx: *anyopaque, len: usize, alignment: mem.Alignment, _: usize) ?[*]u8 {
        const next_addr: *usize = @ptrCast(@alignCast(ctx));
        defer next_addr.* += len;

        return @ptrFromInt(alignment.forward(next_addr.*));
    }

    pub fn resize(_: *anyopaque, _: []u8, _: mem.Alignment, _: usize, _: usize) bool {
        return false;
    }

    pub fn remap(_: *anyopaque, _: []u8, _: mem.Alignment, _: usize, _: usize) ?[*]u8 {
        return null;
    }

    pub fn free(_: *anyopaque, _: []u8, _: mem.Alignment, _: usize) void {}
};
