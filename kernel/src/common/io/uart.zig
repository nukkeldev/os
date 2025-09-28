//! I/O access to UART.

const DTB_COMPAT = switch (@import("builtin").cpu.arch) {
    .riscv64 => "ns16550a",
    else => unreachable,
};

var BUFFER: [16 * 1024]u8 = @splat(0);
var ADDR: *u8 = @ptrFromInt(0x10_000_000); // Hardcoded Fallback (set to QEMU virt's address)

// -- Initialization -- //

/// Trys to poll the DTB for the address of a UART device ("ns16550a").
/// Returns `true` on success.
pub fn initFromDevicetree(dt: *const @import("../devicetree/devicetree.zig")) !void {
    const device_opt = dt.getCompatibleDevice("ns16550a");
    if (device_opt) |device| {
        const addr = try device.getProp("reg").?.readInt(u64, 0);

        printf("UART address set to 0x{X}", .{addr});
        ADDR = @ptrFromInt(addr);
    }

    // TODO: Configure UART FIFO, Word Length, etc.
    // TODO: On a non-virt board, need to get baud rate.
}

// -- Usage -- //

/// Formats and prints to UART TX.
// TODO: Trunacate messages if the buffer is overflown.
pub fn printf(comptime fmt: []const u8, args: anytype) void {
    if (comptime !@import("options").uart) return;

    const str = @import("std").fmt.bufPrint(&BUFFER, "[UART] " ++ fmt ++ "\n", args) catch unreachable;
    for (str) |c| ADDR.* = c;
}

// -- Writer -- //

const Io = @import("std").Io;

pub fn writer() Io.Writer {
    return .{ .buffer = &BUFFER, .vtable = &Writer.vtable };
}

const Writer = struct {
    pub const vtable: Io.Writer.VTable = .{ .drain = drain };

    fn drain(w: *Io.Writer, data: []const []const u8, _: usize) Io.Writer.Error!usize {
        printf("{s}", .{w.buffer[0..w.end]});
        w.end = 0;

        var bytes: usize = 0;
        for (data) |datum| {
            printf("{s}", .{datum});
            bytes += datum.len;
        }

        return bytes;
    }
};
