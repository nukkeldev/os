// -- Imports -- //

const std = @import("std");

const asmh = @import("asmh.zig");
const heap = @import("mem/heap.zig");
const uart = @import("mmio/uart.zig");
const sbi = @import("sbi.zig");

const Devicetree = @import("devicetree/devicetree.zig");

// -- Constants -- //

/// How many bytes are commands able to be?
const SHELL_COMMAND_BUFFER_LENGTH = 512;

// -- Runtime Constants -- //
// Configured with "reasonable" defaults.

/// The update rate of the shell in ticks.
var SHELL_UPDATE_RATE = 1_000;
/// Platform-specific ticks per second.
var TIME_BASE_FREQ: usize = 1_000_000;
/// An arbitrary reference point for "time-since" operations.
var START_TIME: usize = 0;

// -- Main -- //

/// A wrapper for main to allow it to call fallible functions (and therefore
/// return on error). The arguments are forwarded from SBI.
pub export fn kmain(hart_id: usize, dtb_ptr: ?*anyopaque) noreturn {
    if (hart_id != 0) unreachable;

    main(dtb_ptr) catch |e| {
        std.debug.panic("Error from `main`: {}", .{e});
    };

    while (true) {}
}

/// The entrypoint of the kernel.
/// Performs initial setup and spawns a UART shell for the user.
fn main(dtb_ptr: ?*anyopaque) !void {
    // Initialize dumb allocator.
    heap.ufaInit();
    const allocator = heap.ufa.?.allocator();

    // Parse the Devicetree.
    const dt = try Devicetree.parseFromBlob(allocator, dtb_ptr);

    // Attempt to initialize the UART with the corresponding Devicetree device.
    uart.initFromDevicetree(&dt) catch |e| {
        uart.printf("Failed to initialize uart! Error: {}", .{e});
    };

    // Setup global timing.
    setupTiming(&dt);

    // Get memory available for use.
    const dram_len = try dt.getDeviceByName("memory").?.getProp("reg").?.readInt(u64, 8);
    uart.printf("Memory Size: 0x{X}", .{dram_len});

    uart.printf("Kernel ends and heap starts at 0x{X}.", .{heap.ufa.?.next_addr});
    uart.printf("Subsequent memory is available for use, with the exception of the previously listed reserved memory slices.", .{});

    uart.printf("Attempting to dynamically allocate memory for a format...", .{});

    const str = try @import("std").fmt.allocPrint(allocator, "This was formatted by an allocator at 0x{X}!", .{@intFromPtr(&heap.ufa.?)});
    uart.printf("{s}", .{str});

    // Start a shell for user interaction.
    var done = false;

    var cmd_buf: [SHELL_COMMAND_BUFFER_LENGTH]u8 = undefined;
    var cmd_buf_writer: std.Io.Writer = .fixed(&cmd_buf);

    uart.print("> ");
    while (!done) {
        const process = processShell(&cmd_buf_writer) catch {
            uart.printf("Commands are limited to {} bytes!", .{SHELL_COMMAND_BUFFER_LENGTH});
            continue;
        };

        if (process) {
            uart.print("\r\n");
            done = try processCommand(std.mem.trim(u8, cmd_buf[0..cmd_buf_writer.end], &std.ascii.whitespace));
            cmd_buf_writer.end = 0;
            uart.print("> ");
        }
    }

    // NOTE: We can bypass SBI by writing to the syscon MMIO.
    try sbi.SystemReset.reset(.shutdown, .no_reason);
}

/// Reads a byte from UART and returns whether the command is "done".
fn processShell(cmd_buf_writer: *std.Io.Writer) !bool {
    switch (uart.readByte()) {
        8, 127 => if (cmd_buf_writer.end > 0) {
            uart.print("\x08 \x08");
            cmd_buf_writer.end -= 1;
        },
        10, 13 => {
            return true;
        },
        0 => {},
        else => |c| {
            if (std.ascii.isPrint(c)) uart.printChar(c);
            try cmd_buf_writer.writeByte(c);
        },
    }
    return false;
}

fn processCommand(command: []const u8) !bool {
    uart.printf("Running command '{s}'.", .{command});

    if (std.ascii.eqlIgnoreCase(command, "quit")) return true;
    return false;
}

// -- Timing -- //

/// Setups global state necessary for tick to wall-time synchronization.
fn setupTiming(dt: *const Devicetree) void {
    START_TIME = getTime();

    const cpus = dt.getDeviceByName("cpus").?;
    const prop_timebase_freq = cpus.getProp("timebase-frequency");

    var timebase_set = false;
    if (prop_timebase_freq) |prop| blk: {
        TIME_BASE_FREQ = prop.readInt(u32, 0) catch {
            uart.printf("Property \"timebase-freqency\" did not have enough data to read a u32.", .{});
            break :blk;
        };
        timebase_set = true;
    } else {
        uart.printf("Failed to get the \"timebase-frequency\" prop on the \"cpus\" device!", .{});
    }

    if (!timebase_set) {
        uart.printf("Because we could not get the timebase frequency from the Devicetree, " ++
            "we will be using the default which could lead to desynchronization.", .{});
    }

    uart.printf("System has a timebase frequency of {} ticks/second.", .{TIME_BASE_FREQ});
    uart.printf("System starting from {} ticks ({} seconds).", .{ START_TIME, ticksToSeconds(START_TIME) });
}

inline fn getTime() usize {
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

// -- SBI Capabilities -- //

pub fn probeSBICapabilities() void {}

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
