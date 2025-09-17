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
pub fn initFromDevicetree(dtb: *const @import("../devicetree/devicetree_blob.zig")) bool {
    const uart = dtb.getFirst2x2RegForNodeByCompatibles(DTB_COMPAT) orelse return false;
    ADDR = @ptrFromInt(uart.address);

    // TODO: Configure UART FIFO, Word Length, etc.
    // TODO: On a non-virt board, need to get baud rate.

    printf("uart address set to 0x{X}", .{uart.address});

    return true;
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
