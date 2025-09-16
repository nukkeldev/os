//! TODO:
//! - Replace panic handler.

// -- Imports -- //

const uart = @import("uart.zig");
const sbi = @import("sbi.zig");
const fdt = @import("../util/devicetree/devicetree_blob.zig");

// -- Main -- //

pub export fn kmain_riscv(hartid: usize, dtb_ptr: ?*anyopaque) noreturn {
    if (hartid != 0) while (true) {}; // TODO: This is to catch errors, not for multiple harts.

    uart.print("Entering `kmain_riscv` on hartid={}", .{hartid});

    main(hartid, dtb_ptr) catch |e| {
        uart.print("Error from `main`: {}", .{e});
    };

    while (true) {} // Just in case.
}

fn main(hartid: usize, dtb_ptr: ?*anyopaque) !noreturn {
    uart.print("Entering `main` on hartid={}", .{hartid});

    const dtb = try fdt.parse(dtb_ptr);
    uart.print("{f}", .{dtb});

    if (!try sbi.Base.probeExtension(sbi.Debug.EID)) {
        uart.print("SBI DBCN is not available, further use will be disabled.", .{});
    } else {
        uart.print("SBI DBCN is available.", .{});
    }

    _ = try sbi.Debug.consoleWrite("[SBI] Hello, World!\n");

    const uart_addr = dtb.getFirst2x2RegForNodeByCompatibles("ns16550a");
    uart.print("Found uart_addr=0x{X} length=0x{X}", .{uart_addr.?.address, uart_addr.?.length});

    try sbi.SystemReset.reset(.shutdown, .no_reason);
}
