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
//
// ALL INTEGERS ARE BIG-ENDIAN, CONVERT WHEN NECESSARY.

// -- Constants -- //

const b2n = @import("std").mem.bigToNative;
const n2b = @import("std").mem.nativeToBig;

const MAX_SUPPORTED_VERSION = 17;
const MIN_SUPPORTED_VERSION = 16;
const MAGIC = 0xD00DFEED;

// -- Fields -- //

header: *const fdt_header,
mem_rsv: []align(8) const fdt_reserve_entry,
structure: []align(4) const fdt_struct_token,
strings: []const u8,

// -- Parsing -- //

pub const ParseError = error{
    InvalidMagic,
    InvalidVersion,
};

pub fn parse(ptr: ?*anyopaque) !@This() {
    const header: *const fdt_header = @ptrCast(@alignCast(ptr));

    if (b2n(u32, header.magic) != MAGIC) return ParseError.InvalidMagic;
    if (b2n(u32, header.version) < MIN_SUPPORTED_VERSION or
        b2n(u32, header.version) > MAX_SUPPORTED_VERSION) return ParseError.InvalidVersion;

    return .{
        .header = header,
        .mem_rsv = blk: {
            const start_ptr = @intFromPtr(ptr) + b2n(u32, header.off_mem_rsvmap);
            const many_ptr: [*]const fdt_reserve_entry = @ptrFromInt(start_ptr);

            var len: usize = 0;
            while (many_ptr[len].address != 0 and many_ptr[len].size != 0) {
                len += 1;
            }

            break :blk many_ptr[0..len];
        },
        .structure = blk: {
            const many_ptr: [*]const fdt_struct_token = @ptrFromInt(@intFromPtr(ptr) + b2n(u32, header.off_dt_struct));
            break :blk many_ptr[0 .. b2n(u32, header.size_dt_struct) / @sizeOf(fdt_struct_token)];
        },
        .strings = blk: {
            const many_ptr: [*]const u8 = @ptrFromInt(@intFromPtr(ptr) + b2n(u32, header.off_dt_strings));
            break :blk many_ptr[0..b2n(u32, header.size_dt_strings)];
        },
    };
}

// -- Direct Usage -- //

/// Retrieves the first 2x2-cell address-size pair for the first node that is compatible.
pub fn getFirst2x2RegForNodeByCompatibles(
    dtb: *const @This(),
    compatible: []const u8,
) ?struct {
    address: usize,
    length: usize, // TODO: It is valid for length to be omitted if #size_cells == 0.
} {
    const mem = @import("std").mem;

    var i: usize = 0;

    var node_start: usize = 0;
    var node_name: [:0]const u8 = undefined;
    var found: bool = false;

    outer: while (i < dtb.structure.len) : (i += 1) {
        switch (dtb.structure[i]) {
            .begin_node => {
                node_start = i;
                node_name = mem.span(@as([*:0]const u8, @ptrCast(&dtb.structure[i + 1])));
                i += node_name.len;
            },
            .end_node => {
                found = false;
            },
            .prop => {
                const val_byte_len = b2n(u32, @intFromEnum(dtb.structure[i + 1]));
                const val_cell_len = @import("std").math.divCeil(u32, val_byte_len, @sizeOf(fdt_struct_token)) catch unreachable;
                const name_offs = b2n(u32, @intFromEnum(dtb.structure[i + 2]));
                
                const prop_name: []const u8 = mem.span(@as([*:0]const u8, @ptrCast(&dtb.strings[@intCast(name_offs)])));

                if (found and mem.eql(u8, prop_name, "reg")) {
                    // We are assuming that `size` is not omitted.

                    const address = b2n(usize, @import("std").mem.bytesToValue(usize, dtb.structure[i + 3 .. i + 5]));
                    const length = b2n(usize, @import("std").mem.bytesToValue(usize, dtb.structure[i + 5 .. i + 7]));

                    return .{ .address = address, .length = length };
                } else if (mem.eql(u8, prop_name, "compatible")) {
                    var k: usize = 0;
                    var strings: []const u8 = @ptrCast(dtb.structure[i + 3 .. i + 3 + val_cell_len]);
                    for (0..val_byte_len) |l| {
                        if (strings[l] == 0 or l == val_byte_len - 1) {
                            const string = strings[k..@min(l + 1, val_byte_len - 1)];
                            if (mem.eql(u8, string, compatible)) {
                                found = true;
                                i = node_start;
                                continue :outer;
                            }
                            k = l + 1;
                        }
                    }
                }

                i += 2 + val_cell_len;
            },
            else => {},
        }
    }

    return null;
}

// -- Header -- //

/// [#1 5.2]
pub const fdt_header = extern struct {
    magic: u32,
    totalsize: u32,
    off_dt_struct: u32,
    off_dt_strings: u32,
    off_mem_rsvmap: u32,
    version: u32,
    last_comp_version: u32,
    boot_cpuid_phys: u32,
    size_dt_strings: u32,
    size_dt_struct: u32,
};

// -- Memory Reservation Block -- //

pub const fdt_reserve_entry = extern struct {
    address: u64,
    size: u64,
};

// -- Structure Block -- //

pub const fdt_struct_token = enum(u32) {
    /// Followed by the cstr node name.
    begin_node = n2b(u32, 0x1),
    end_node = n2b(u32, 0x2),
    /// Followed by fdt_struct_prop, then property value.
    prop = n2b(u32, 0x3),
    nop = n2b(u32, 0x4),
    end = n2b(u32, 0x9),
    _,
};

pub const fdt_struct_prop = extern struct {
    /// Length of property value.
    len: u32,
    /// Offset into the strings block to cstr of prop name.
    nameoff: u32,
};

// -- Formatting -- //

pub fn format(self: @This(), writer: *@import("std").Io.Writer) @import("std").Io.Writer.Error!void {
    try writer.print(
        \\[Devicetree Blob]
        \\  - Header:
        \\    - Magic: 0x{X} (==0x{X})
        \\    - Total Size: {} bytes
        \\    - Version: {} (>={})
        \\    - Boot CPU ID: {}
        \\  - Reserved Memory [+0x{X}..]
        \\  - Structure [+0x{X}..0x{X}]
        \\  - Strings [+0x{X}..0x{X}]
    , .{
        b2n(u32, self.header.magic),
        MAGIC,
        b2n(u32, self.header.totalsize),
        b2n(u32, self.header.version),
        b2n(u32, self.header.last_comp_version),
        b2n(u32, self.header.boot_cpuid_phys),
        b2n(u32, self.header.off_mem_rsvmap),
        b2n(u32, self.header.off_dt_struct),
        b2n(u32, self.header.off_dt_struct + self.header.size_dt_struct),
        b2n(u32, self.header.off_dt_strings),
        b2n(u32, self.header.off_dt_strings) + b2n(u32, self.header.size_dt_strings),
    });
}
