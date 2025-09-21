//! TODO:
//! - Replace panic handler.

// -- Imports -- //

const std = @import("std");

const heap = @import("../common/mem/heap.zig");

const uart = @import("../common/io/uart.zig");
const sbi = @import("sbi.zig");
const fdt = @import("../common/devicetree/devicetree_blob.zig");
const asmh = @import("asmh.zig");

// -- Main -- //

pub export fn kmain_riscv(hartid: usize, dtb_ptr: ?*anyopaque) noreturn {
    uart.printf("Entering `kmain_riscv` on hartid={}", .{hartid});

    main(hartid, dtb_ptr) catch |e| {
        std.debug.panic("Error from `main`: {}", .{e});
    };

    while (true) {}
}

fn main(hartid: usize, dtb_ptr: ?*anyopaque) !void {
    uart.printf("Entering `main` on hartid={}", .{hartid});

    const dtb = try fdt.parse(dtb_ptr);
    uart.printf("{f}", .{dtb});

    _ = uart.initFromDevicetree(&dtb);

    if (!try sbi.Base.probeExtension(sbi.Debug.EID)) {
        uart.printf("SBI DBCN is not available, further use will be disabled.", .{});
    } else {
        uart.printf("SBI DBCN is available.", .{});
    }

    _ = try sbi.Debug.consoleWrite("[SBI] Hello, World!\n");

    heap.ufaInit();
    const allocator = heap.ufa.?.allocator();

    uart.printf("Kernel ends and heap starts at 0x{X}.", .{heap.ufa.?.next_addr});
    uart.printf("Subsequent memory is available for use, with the exception of the previously listed reserved memory slices.", .{});

    uart.printf("Attempting to dynamically allocate memory for a format...", .{});

    const str = try @import("std").fmt.allocPrint(allocator, "This was formatted by an allocator at 0x{X}!", .{@intFromPtr(&heap.ufa.?)});
    uart.printf("{s}", .{str});

    const sstatus = asmh.csrr(asmh.SStatus, "sstatus");
    uart.printf("{}", .{sstatus});

    // NOTE: We can bypass SBI by writing to the syscon MMIO.
    try sbi.SystemReset.reset(.shutdown, .no_reason);
}

// -- VM Setup -- //

pub export fn setup_vm_riscv() void {}

// -- Panic Handler -- //

pub const panic = @import("std").debug.FullPanic(struct {
    const debug = std.debug;
    const io = std.io;

    const StackIterator = debug.StackIterator;
    const SelfInfo = debug.SelfInfo;
    const UnwindError = debug.UnwindError;
    const Writer = std.Io.Writer;

    /// Prints the message to UART along with an address stacktrace, trys to shutdown, then traps
    /// if that failed. This takes bits and pieces of the default panic implementation.
    pub fn call(msg: []const u8, ra: ?usize) noreturn {
        @branchHint(.cold);
        uart.printf("Panic: {s}", .{msg});
        uart.printf("Stack Trace:", .{});

        var it = StackIterator.init(ra, null);
        var i: usize = 0;
        while (it.next()) |return_address| {
            uart.printf("\t[{}] 0x{X}", .{ i, return_address });
            i += 1;
        }

        while (true) {}
    }
}.call);
