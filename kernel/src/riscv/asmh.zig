// -- Imports -- //

const fmt = @import("std").fmt.comptimePrint;

// -- CSR -- //

pub inline fn csrr(comptime T: type, comptime csr: []const u8) T {
    return asm volatile (fmt("csrr %[ret], {s}", .{csr})
        : [ret] "=r" (-> T),
        :
        : .{});
}

pub inline fn csrw(comptime T: type, comptime csr: []const u8, val: T) void {
    return asm volatile (fmt("csrw {s}, %[val]", .{csr})
        :
        : [val] "r" (val),
        : .{});
}

pub const SStatus = packed struct(usize) {
    wpri1: u1,
    sie: u1,
    wpri2: u3,
    spie: u1,
    ube: u1,
    wpri3: u1,
    spp: u1,
    vs: u2,
    wpri4: u2,
    fs: u2,
    xs: u2,
    wpri5: u1,
    sum: u1,
    mxr: u1,
    wpri6: u3,
    spelp: u1,
    sdt: u1,
    wpri7: u7,
    uxl: u2,
    wpri8: u29,
    sd: u1,
};
