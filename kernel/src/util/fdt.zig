//! Parses and traverses DTBs.
//!
//! Referencing:
//! 1. https://github.com/devicetree-org/devicetree-specification/releases/tag/v0.4

// --

// So as to not have to hardcode platform-specific constants, Devicetrees (similar to ACPI)
// allow us to read a description of the hardware that we can poll for specific addresses, etc.
//
// [#1 2.1] "A devicetree is a tree data structure with nodes that describe the devices in a system.
// Each node has property/value pairs that describe the characteristics of the device being represented.
// Each node has exactly one parent except for the root node, which has no parent".
// - Nodes generally have correlation to a hardware device (i.e. UART) or a part of one (i.e. rng from TPM).
// - Nodes should not be OS- or project-specific.
// - Nodes are specified by their name and unit address (i.e. uart@0f00ee0), with the root node being named "/".
//
// Standard node properties include:
// - "compatible":
//   - "... used by a client program for device driver selection".
//   - "... from most specific to most general".
// -

// -- Constants -- //

const fdt = @This();

const b2n = @import("std").mem.bigToNative;

const MAX_SUPPORTED_VERSION = 17;
const MIN_SUPPORTED_VERSION = 16;
const MAGIC = 0xD00DFEED;

// -- Fields -- //

header: *Header,

// -- Loading -- //

pub const LoadingError = error{
    InvalidMagic,
    InvalidVersion,
};

pub fn load(ptr: ?*anyopaque) !fdt {
    const header: *Header = @ptrCast(@alignCast(ptr));
    { // Convert all integer fields to native endianness.
        inline for (@typeInfo(Header).@"struct".fields) |f|
            @field(header, f.name) = b2n(f.type, @field(header, f.name));
    }

    if (header.magic != MAGIC) return LoadingError.InvalidMagic;
    if (header.version < MIN_SUPPORTED_VERSION or header.version > MAX_SUPPORTED_VERSION)
        return LoadingError.InvalidVersion;

    return .{
        .header = header,
    };
}

// -- Header -- //

/// [#1 5.2]
pub const Header = extern struct {
    /// 0xd00dfeed (big-endian)
    magic: u32,
    /// The total size, in bytes, of the devicetree structure (header + blocks + padding).
    totalsize: u32,
    /// The offset from the beginning of the header, in bytes, of the structure block.
    off_dt_struct: u32,
    /// The offset from the beginning of the header, in bytes, of the strings block.
    off_dt_strings: u32,
    /// The offset from the beginning of the header, in bytes, of the memory reservation block.
    off_mem_rsvmap: u32,
    /// The version of the devicetree structure (17).
    version: u32,
    /// The version this devicetree structure is earliest compatible with (16).
    last_comp_version: u32,
    /// The physical ID of the system's boot CPU. Equivalent to that CPU's node's reg property.
    boot_cpuid_phys: u32,
    /// The length of the strings block.
    size_dt_strings: u32,
    /// The length of the structure block.
    size_dt_struct: u32,
};
