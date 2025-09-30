// -- Imports -- //

const std = @import("std");

const asmh = @import("asmh.zig");
const heap = @import("mem/heap.zig");
const uart = @import("mmio/uart.zig");
const sbi = @import("sbi.zig");

const Devicetree = @import("devicetree/devicetree.zig");

// -- Constants -- //

/// How many bytes are commands able to be?
const SHELL_COMMAND_BUFFER_LENGTH = 128;
// const SHELL_COMMAND_HISTORY = 100;

// -- System State -- //

pub var hart_state: *HartState = undefined;

pub const HartState = struct {
    /// The update rate of the shell in ticks.
    shell_update_rate: usize = 1_000,
    /// Platform-specific ticks per second.
    time_base_freq: usize = 1_000_000,
    /// An arbitrary reference point for "time-since" operations.
    start_time: usize = 0,

    devicetree: *const Devicetree,

    pub fn init(allocator: std.mem.Allocator, devicetree: *const Devicetree) !*@This() {
        const state = try allocator.create(@This());

        state.devicetree = devicetree;
        state.start_time = state.getTimeTicks();

        const cpus = devicetree.getDeviceByName("cpus").?;
        const prop_timebase_freq = cpus.getProp("timebase-frequency");

        var timebase_set = false;
        // TODO: Per the spec:
        // Properties that have identical values across cpu nodes may be placed in the /cpus node
        // instead. A client program must first examine a specific cpu node, but if an expected
        // property is not found then it should look at the parent /cpus node.
        if (prop_timebase_freq) |prop| blk: {
            state.time_base_freq = prop.readInt(u32, 0) catch {
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

        uart.printf("System has a timebase frequency of {} ticks/second.", .{state.time_base_freq});
        uart.printf("System starting from {} ticks ({} seconds).", .{ state.start_time, state.ticksToSeconds(state.start_time) });

        state.shell_update_rate = state.secondsToTicks(0.01);

        return state;
    }

    pub inline fn getTimeTicks(_: *const @This()) usize {
        return asm volatile (
            \\rdtime t0
            : [ret] "={t0}" (-> usize),
            :
            : .{ .x5 = true });
    }

    pub inline fn getTimeSeconds(self: *const @This()) f64 {
        return self.ticksToSeconds(self.getTimeTicks());
    }

    fn ticksToSeconds(self: *const @This(), ticks: usize) f64 {
        return @as(f64, @floatFromInt(ticks)) / @as(f64, @floatFromInt(self.time_base_freq));
    }

    fn secondsToTicks(self: *const @This(), secs: f64) usize {
        return @intFromFloat(secs * @as(f64, @floatFromInt(self.time_base_freq)));
    }
};

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
    const dt = try allocator.create(Devicetree);
    dt.* = try Devicetree.parseFromBlob(allocator, dtb_ptr);

    // Attempt to initialize the UART with the corresponding Devicetree device.
    uart.initFromDevicetree(dt) catch |e| {
        uart.printf("Failed to initialize uart! Error: {}", .{e});
    };

    // Setup hart system state.
    hart_state = try HartState.init(allocator, dt);

    // Start a shell for user interaction.
    var done = false;

    var cmd_buf: [SHELL_COMMAND_BUFFER_LENGTH]u8 = undefined;
    var cmd_buf_writer: std.Io.Writer = .fixed(&cmd_buf);

    uart.print("> ");
    while (!done) {
        const state = readChar(&cmd_buf_writer) catch {
            uart.printf("Commands are limited to {} bytes!", .{SHELL_COMMAND_BUFFER_LENGTH});
            continue;
        };

        switch (state) {
            .submit => {
                uart.print("\r\n");
                done = try processCommand(std.mem.trim(u8, cmd_buf[0..cmd_buf_writer.end], &std.ascii.whitespace));
                cmd_buf_writer.end = 0;
                uart.print("> ");
            },
            .progress => {},
        }
    }

    // NOTE: We can bypass SBI by writing to the syscon MMIO.
    try sbi.SystemReset.reset(.shutdown, .no_reason);
}

const ReadByteState = union(enum) {
    submit,
    progress,
    // TODO: Command History
};

/// Reads a byte from UART and returns whether the command is "done".
fn readChar(cmd_buf_writer: *std.Io.Writer) !ReadByteState {
    const State = union(enum) {
        empty,
        escape,
        arrow,
    };
    const MAX_WAIT_DEPTH = 100;

    var wait_depth: usize = 0;
    sw: switch (State.empty) {
        .empty => switch (uart.readByte()) {
            8, 127 => if (cmd_buf_writer.end > 0) {
                uart.print("\x08 \x08");
                cmd_buf_writer.end -= 1;
            },
            std.ascii.control_code.esc => continue :sw .escape,
            10, 13 => {
                return .submit;
            },
            0 => {},
            else => |c| {
                if (std.ascii.isPrint(c)) uart.printChar(c);
                try cmd_buf_writer.writeByte(c);
            },
        },
        .escape => switch (uart.readByte()) {
            '[' => continue :sw .arrow,
            else => {
                if (wait_depth > MAX_WAIT_DEPTH) {
                    break :sw;
                }
                wait_depth += 1;
                continue :sw .escape;
            },
        },
        .arrow => switch (uart.readByte()) {
            'A' => {}, // Up Arrow
            'B' => {}, // Down Arrow
            'C' => {}, // Right Arrow
            'D' => {}, // Left Arrow
            else => {
                if (wait_depth > MAX_WAIT_DEPTH) {
                    uart.print("Incomplete arrow sequence timeout!\n");
                    break :sw;
                }
                wait_depth += 1;
                continue :sw .arrow;
            },
        },
    }

    return .progress;
}

const COMMANDS: std.StaticStringMap(*const fn ([]const u8) bool) = .initComptime(.{
    .{ "help", commandHelp },
    .{ "ls", commandLs },
    .{ "quit", commandQuit },
});

fn processCommand(command: []const u8) !bool {
    if (command.len == 0) return false;

    uart.printf("Running command '{s}' ({any}).", .{ command, command });

    const first_split = std.mem.indexOfScalar(u8, command, ' ') orelse command.len;
    const root_command = command[0..first_split];

    const command_fn = COMMANDS.get(root_command) orelse {
        uart.printf("Command '{s}' ({any}) does not exist!", .{ root_command, root_command });
        return false;
    };

    return command_fn(command[first_split..]);
}

fn commandHelp(_: []const u8) bool {
    uart.print(
        \\Available Commands:
        \\
    );

    for (COMMANDS.keys()) |key| {
        uart.printf("  {s}", .{key});
    }

    return false;
}

fn commandQuit(_: []const u8) bool {
    return true;
}

fn commandLs(args: []const u8) bool {
    var tokens = std.mem.tokenizeAny(u8, args, &std.ascii.whitespace);

    var print_usage = false;
    blk: {
        if (tokens.next()) |token| {
            if (std.mem.eql(u8, "--help", token)) {
                print_usage = true;
                break :blk;
            }
        }

        for (hart_state.devicetree.devices) |*device| {
            uart.printf("- {s}", .{device.name});
        }
    }

    if (print_usage) {
        uart.print(
            \\Usage: ls 
            \\Lists devices in the Devicetree.
            \\
        );
    }

    return false;
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
