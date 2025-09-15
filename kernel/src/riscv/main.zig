//! TODO:
//! - Replace panic handler.

// -- Imports -- //

const bufPrint = @import("std").fmt.bufPrint;
const comptimePrint = @import("std").fmt.comptimePrint;

// -- Main -- //

pub export fn kmain() noreturn {
    UART.print("Entering kernel main", .{});
    _ = SBI.Debug.consoleWrite("[SBI] Hello, World!\n");
    // for (0..256) |c| _ = SBI.Debug.consoleWriteByte(@intCast(c));

    _ = SBI.SystemReset.reset(.shutdown, .no_reason);
    while (true) {} // Just in case.
}

// -- UART -- //

/// A basic debugging I/O when all else fails.
pub const UART = struct {
    var BUFFER: [4096]u8 = @splat(0);
    const ADDR: *u8 = @ptrFromInt(0x10_000_000);

    fn putChar(c: u8) void {
        ADDR.* = c;
    }

    fn print(comptime fmt: []const u8, args: anytype) void {
        const str = bufPrint(&BUFFER, "[UART] " ++ fmt ++ "\n", args) catch unreachable;
        for (str) |c| putChar(c);
    }
};

// -- SBI -- //

/// An abstraction of functions provided by the SBI implementation.
///
/// See https://github.com/riscv-non-isa/riscv-sbi-doc/blob/master/src/binary-encoding.adoc and sibling
/// documents.
pub const SBI = struct {
    /// The return value of all SBI functions.
    pub const Ret = extern struct {
        err: isize,
        val: isize,
    };

    // -- Debug Console Extension -- //

    pub const Debug = struct {
        pub const EID = 0x4442434E;

        pub fn consoleWrite(str: [:0]const u8) Ret {
            var err: isize = undefined;
            var val: isize = undefined;

            UART.print("[SBI.consoleWrite] Writing {*}[0:{}] to console", .{ str.ptr, str.len });

            asm volatile (
                \\ecall
                : [err] "={a0}" (err),
                  [val] "={a1}" (val),
                : [eid] "{a7}" (EID),
                  [fid] "{a6}" (0),
                  [typ] "{a0}" (str.len),
                  [rsn] "{a1}" (@intFromPtr(str.ptr)),
                  [___] "{a2}" (0),
                : .{ .x10 = true, .x11 = true });

            return Ret{ .err = err, .val = val };
        }
    };

    // -- System Reset Extension -- //

    pub const SystemReset = struct {
        pub const EID = 0x53525354;

        pub const ResetType = enum(u32) {
            shutdown = 0x0,
            cold_reboot = 0x1,
            warm_reboot = 0x2,
        };

        pub const ResetReason = enum(u32) {
            no_reason = 0x0,
            system_failure = 0x1,
        };

        pub fn reset(reset_type: ResetType, reset_reason: ResetReason) Ret {
            var err: isize = undefined;
            var val: isize = undefined;

            UART.print("Resetting type={t} reason={t}", .{ reset_type, reset_reason });

            asm volatile (
                \\ecall
                : [err] "={a0}" (err),
                  [val] "={a1}" (val),
                : [eid] "{a7}" (EID),
                  [fid] "{a6}" (0),
                  [typ] "{a0}" (@intFromEnum(reset_type)),
                  [rsn] "{a1}" (@intFromEnum(reset_reason)),
                : .{ .x10 = true, .x11 = true });

            return Ret{ .err = err, .val = val };
        }
    };

    // -- Function Invocation -- //

    pub inline fn fnBegin(
        comptime eid: u32,
        comptime fid: u32,
    ) void {
        UART.print("[SBI.start] EID=0x{x} FID=0x{x}", .{ eid, fid });

        asm volatile (""
            :
            : [eid] "{a7}" (eid),
              [fid] "{a6}" (fid),
            : .{ .x17 = true, .x16 = true });
    }
};

// -- Inefficiency -- //

pub const InEff = struct {
    pub fn readRegister(comptime n: u8) usize {
        var out: usize = undefined;

        asm volatile (comptimePrint("mv %[out], x{}", .{n})
            : [out] "=r" (out),
            :
            : .{});

        return out;
    }
};
