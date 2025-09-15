//! TODO:
//! - Replace panic handler.

// -- Imports -- //

const uart = @import("uart.zig");
const sbi = @import("sbi.zig");
const fdt = @import("../util/fdt.zig");

// -- Main -- //

pub export fn kmain_riscv(hartid: usize, dtb_ptr: ?*anyopaque) noreturn {
    uart.print("Entering kmain on hartid={}", .{hartid});

    main(hartid, dtb_ptr) catch |e| {
        uart.print("Error from `main`: {}", .{e});
    };

    while (true) {} // Just in case.
}

fn main(hartid: usize, dtb_ptr: ?*anyopaque) !noreturn {
    uart.print("Entering main on hartid={}", .{hartid});

    const dtb = try fdt.load(dtb_ptr);
    uart.print("{}", .{dtb});

    if (!try sbi.Base.probeExtension(sbi.Debug.EID)) {
        uart.print("SBI DBCN is not available, further use will be disabled.", .{});
    } else {
        uart.print("SBI DBCN is available.", .{});
    }

    _ = try sbi.Debug.consoleWrite("[SBI] Hello, World!\n");

    try sbi.SystemReset.reset(.shutdown, .no_reason);
}
