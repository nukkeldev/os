//! TODO:
//! - Replace panic handler.

// -- Imports -- //

const heap = @import("../common/mem/heap.zig");

const uart = @import("../common/io/uart.zig");
const sbi = @import("sbi.zig");
const fdt = @import("../common/devicetree/devicetree_blob.zig");

// -- Main -- //

pub export fn kmain_riscv(hartid: usize, dtb_ptr: ?*anyopaque) noreturn {
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

    _ = uart.initFromDevicetree(&dtb);

    if (!try sbi.Base.probeExtension(sbi.Debug.EID)) {
        uart.print("SBI DBCN is not available, further use will be disabled.", .{});
    } else {
        uart.print("SBI DBCN is available.", .{});
    }

    _ = try sbi.Debug.consoleWrite("[SBI] Hello, World!\n");

    heap.ufaInit();
    const allocator = heap.ufa.?.allocator();

    uart.print("Kernel ends and heap starts at 0x{X}.", .{heap.ufa.?.next_addr});
    uart.print("Subsequent memory is available for use, with the exception of the previously listed reserved memory slices.", .{});

    uart.print("Attempting to dynamically allocate memory for a format...", .{});

    const str = try @import("std").fmt.allocPrint(allocator, "This was formatted by an allocator at 0x{X}!", .{@intFromPtr(&heap.ufa.?)});
    uart.print("{s}", .{str});

    // NOTE: We can bypass SBI by writing to the syscon MMIO.
    try sbi.SystemReset.reset(.shutdown, .no_reason);
}
