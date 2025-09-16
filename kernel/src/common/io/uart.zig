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

    print("uart address set to 0x{X}", .{uart.address});

    return true;
}

// -- Usage -- //

/// Prints to UART TX.
pub fn print(comptime fmt: []const u8, args: anytype) void {
    if (comptime !@import("options").uart) return;

    const str = @import("std").fmt.bufPrint(&BUFFER, "[UART] " ++ fmt ++ "\n", args) catch unreachable;
    for (str) |c| ADDR.* = c;
}
