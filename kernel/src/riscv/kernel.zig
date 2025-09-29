//! TODO:
//! - Replace panic handler.

// -- Imports -- //

const std = @import("std");

const heap = @import("../common/mem/heap.zig");

const uart = @import("../common/io/uart.zig");
const sbi = @import("sbi.zig");
const Devicetree = @import("../common/devicetree/devicetree.zig");
const asmh = @import("asmh.zig");

// -- Globals & Constants -- //

var TIME_BASE_FREQ: usize = 1_000_000;
var START_TIME: usize = 0;

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

    START_TIME = getTime();

    if (!try sbi.Base.probeExtension(sbi.Debug.EID)) {
        uart.printf("SBI DBCN is not available, further use will be disabled.", .{});
    } else {
        uart.printf("SBI DBCN is available.", .{});
    }

    _ = try sbi.Debug.consoleWrite("[SBI] Hello, World!\n");

    heap.ufaInit();
    const allocator = heap.ufa.?.allocator();

    const dt = try Devicetree.parseFromBlob(allocator, dtb_ptr);
    // uart.printf("{f}", .{dt});

    uart.initFromDevicetree(&dt) catch |e| {
        uart.printf("Failed to initialize uart! Error: {}", .{e});
    };

    const dram_len = try dt.getDeviceByName("memory").?.getProp("reg").?.readInt(u64, 8);
    uart.printf("Memory Size: 0x{X}", .{dram_len});

    const cpus = dt.getDeviceByName("cpus") orelse {
        uart.printf("Failed to get the \"cpus\" device!", .{});
        return error.DeviceTree;
    };

    for (cpus.props) |*prop| uart.printf("{s}", .{prop.name});

    TIME_BASE_FREQ = try (cpus.getProp("timebase-frequency") orelse {
        uart.printf("Failed to get the \"timebase-frequency\" prop on the \"cpus\" device!", .{});
        return error.DeviceTree;
    }).readInt(u32, 0);

    uart.printf("The system is starting at {} seconds.", .{ticksToSeconds(START_TIME)});

    uart.printf("Kernel ends and heap starts at 0x{X}.", .{heap.ufa.?.next_addr});
    uart.printf("Subsequent memory is available for use, with the exception of the previously listed reserved memory slices.", .{});

    uart.printf("Attempting to dynamically allocate memory for a format...", .{});

    const str = try @import("std").fmt.allocPrint(allocator, "This was formatted by an allocator at 0x{X}!", .{@intFromPtr(&heap.ufa.?)});
    uart.printf("{s}", .{str});

    while (true) {
        switch (uart.readByte()) {
            8, 127 => uart.print("\x08 \x08"),
            10, 13 => uart.print("\r\n"),
            0 => {},
            else => |c| {
                if (std.ascii.isPrint(c)) {
                    uart.printChar(c);
                } else {
                    uart.printf("\\x{:0<2}", .{c});
                }
            },
        }
    }

    // const wait_time = secondsToTicks(5);
    // uart.printf("Waiting {} seconds ({} ticks)", .{ 5, wait_time });
    // const end = getTime() + wait_time;

    // while (getTime() < end) {}

    // NOTE: We can bypass SBI by writing to the syscon MMIO.
    try sbi.SystemReset.reset(.shutdown, .no_reason);
}

fn getTime() usize {
    return asm volatile (
        \\rdtime t0
        : [ret] "={t0}" (-> usize),
        :
        : .{ .x5 = true });
}

fn ticksToSeconds(ticks: usize) f64 {
    return @as(f64, @floatFromInt(ticks)) / @as(f64, @floatFromInt(TIME_BASE_FREQ));
}

fn secondsToTicks(secs: f64) usize {
    return @intFromFloat(secs * @as(f64, @floatFromInt(TIME_BASE_FREQ)));
}

// -- VM Setup -- //

pub export fn setup_vm_riscv() void {}

// -- Interrupt Handler -- //

export fn reset_time_interrupts_riscv() void {
    sbi.Time.setTimer(std.math.maxInt(usize));
}

// Ref: https://github.com/popovicu/zig-riscv-interrupts/blob/main/program.zig
export fn interrupt_handler_riscv() align(16) linksection(".text.interrupt") callconv(.{ .riscv64_interrupt = .{ .mode = .supervisor } }) void {
    // sbi.Time.setTimer(getTime() + SHELL_UPDATE_RATE);
}

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

        sbi.SystemReset.reset(.shutdown, .no_reason) catch {};

        while (true) {}
    }
}.call);
