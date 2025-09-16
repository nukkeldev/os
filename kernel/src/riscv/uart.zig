//! I/O access to UART.

var BUFFER: [16 * 1024]u8 = @splat(0);
const ADDR: *u8 = @ptrFromInt(0x10_000_000); // TODO: Probe this from the dtb.

pub fn putChar(c: u8) void {
    ADDR.* = c;
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    if (comptime !@import("options").uart) return;

    const str = @import("std").fmt.bufPrint(&BUFFER, "[UART] " ++ fmt ++ "\n", args) catch unreachable;
    for (str) |c| putChar(c);
}
