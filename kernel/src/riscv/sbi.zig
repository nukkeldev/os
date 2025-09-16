//! An abstraction of functions provided by the SBI implementation. Unfortunately, not a lot of this
//! can be done at comptime (at least I haven't figured out a good API for it).
//!
//! Currently most functions are thin wrappers of the SBI functions,
//! except debug extension functions that ignore being unsupported.
//!
//! See https://github.com/riscv-non-isa/riscv-sbi-doc/blob/master/src/binary-encoding.adoc and sibling
//! documents.

// -- Errors -- //

/// Return codes for SBI functions.
pub const Err = error{
    // success, // = 0x0,
    failed, // = -0x1,
    not_supported, // = -0x2,
    invalid_param, // = -0x3,
    denied, // = -0x4,
    invalid_address, // = -0x5,
    already_available, // = -0x6,
    already_started, // = -0x7,
    already_stopped, // = -0x8,
    no_shmem, // = -0x9,
    bad_range, // = -0xA,
    invalid_state, // = -0xB,
    timeout, // = -0xC,
    io, // = -0xD,
    denied_locked, // = -0xE,
};

pub fn errFromInt(err: isize) ?Err {
    return switch (err) {
        0x0 => null,
        -0x1 => Err.failed,
        -0x2 => Err.not_supported,
        -0x3 => Err.invalid_address,
        -0x4 => Err.denied,
        -0x5 => Err.invalid_address,
        -0x6 => Err.already_available,
        -0x7 => Err.already_started,
        -0x8 => Err.already_stopped,
        -0x9 => Err.no_shmem,
        -0xA => Err.bad_range,
        -0xB => Err.invalid_state,
        -0xC => Err.timeout,
        -0xD => Err.io,
        -0xE => Err.denied_locked,
        else => unreachable,
    };
}

// -- Base Extension -- //

pub const Base = struct {
    pub const EID = 0x10;

    pub fn probeExtension(eid: isize) Err!bool {
        var errc: isize = undefined;
        var exists: bool = undefined;

        asm volatile (
            \\ecall
            : [err] "={a0}" (errc),
              [val] "={a1}" (exists),
            : [eid] "{a7}" (EID),
              [fid] "{a6}" (3),
              [typ] "{a0}" (eid),
            : .{ .x10 = true, .x11 = true });

        return errFromInt(errc) orelse exists;
    }
};

// -- Debug Console Extension -- //

pub const Debug = struct {
    pub const EID = 0x4442434E;

    pub fn consoleWrite(str: []const u8) Err!usize {
        var errc: isize = undefined;
        var bytes: usize = undefined;

        asm volatile (
            \\ecall
            : [err] "={a0}" (errc),
              [val] "={a1}" (bytes),
            : [eid] "{a7}" (EID),
              [fid] "{a6}" (0),
              [typ] "{a0}" (str.len),
              [rsn] "{a1}" (@intFromPtr(str.ptr)),
              [___] "{a2}" (0),
            : .{ .x10 = true, .x11 = true });

        const err = errFromInt(errc);
        // Ignore the calls when they are not supported.
        if (err != null and err.? == Err.not_supported) return str.len;

        return err orelse bytes;
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

    pub fn reset(reset_type: ResetType, reset_reason: ResetReason) Err!noreturn {
        var err: isize = undefined;

        _ = Debug.consoleWrite("[SBI] Goodbye, World!\n") catch {};

        asm volatile (
            \\ecall
            : [err] "={a0}" (err),
            : [eid] "{a7}" (EID),
              [fid] "{a6}" (0),
              [typ] "{a0}" (@intFromEnum(reset_type)),
              [rsn] "{a1}" (@intFromEnum(reset_reason)),
            : .{ .x10 = true, .x11 = true });

        return errFromInt(err).?;
    }
};
