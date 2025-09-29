// -- Imports -- //

const Devicetree = @This();

const std = @import("std");

const b2n = std.mem.bigToNative;
const n2b = std.mem.nativeToBig;
const dc = std.math.divCeil;

const printf = @import("../io/uart.zig").printf;

const MAX_SUPPORTED_VERSION = 17;
const MIN_SUPPORTED_VERSION = 16;
const MAGIC = 0xD00DFEED;

// -- Fields -- //

version: u32,
boot_cpu_id: u32,
mem_rsv: []const ReserveEntry,
devices: []const Device,

pub const ReserveEntry = struct {
    address: u64,
    size: u64,
};

// -- Parsing -- //

const fdt_header = extern struct {
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

const fdt_reserve_entry = extern struct { address: u64, len: u64 };

pub fn parseFromBlob(allocator: std.mem.Allocator, ptr: ?*anyopaque) !Devicetree {
    const header: *const fdt_header = @ptrCast(@alignCast(ptr));

    if (b2n(u32, header.magic) != MAGIC) return error.InvalidMagic;
    if (b2n(u32, header.version) < MIN_SUPPORTED_VERSION or
        b2n(u32, header.version) > MAX_SUPPORTED_VERSION) return error.InvalidVersion;

    const mem_rsv = blk: {
        const start_ptr = @intFromPtr(header) + b2n(u32, header.off_mem_rsvmap);
        const many_ptr: [*]const fdt_reserve_entry = @ptrFromInt(start_ptr);

        var len: usize = 0;
        while (many_ptr[len].address != 0 and many_ptr[len].len != 0) len += 1;

        var out = try allocator.alloc(ReserveEntry, len);
        for (many_ptr[0..len], 0..) |entry, i| {
            out[i] = .{
                .address = b2n(u64, entry.address),
                .size = b2n(u64, entry.len),
            };
        }

        break :blk out;
    };

    const structure_block: [*]const u32 = @ptrFromInt(@intFromPtr(ptr) + b2n(u32, header.off_dt_struct));
    const strings_block: [*]const u8 = @ptrFromInt(@intFromPtr(ptr) + b2n(u32, header.off_dt_strings));
    const len = b2n(u32, header.size_dt_struct);
    var devices = std.ArrayList(Device).empty;
    var i: usize = 0;
    var parent: ?usize = null;
    var props: std.ArrayList(Prop) = .empty;
    while (i < len) {
        switch (b2n(u32, structure_block[i])) {
            1 => { // Begin Node
                const name = std.mem.span(@as([*:0]const u8, @ptrCast(&structure_block[i + 1])));

                const device: Device = .{
                    .parent = parent,
                    .name = name,
                    .props = &.{},
                    .children = &.{},
                };

                if (props.items.len > 0) {
                    if (parent) |p| {
                        devices.items[p].props = try props.toOwnedSlice(allocator);
                    }
                }
                props.clearAndFree(allocator);

                parent = devices.items.len;
                try devices.append(allocator, device);

                i += 1 + (dc(usize, name.len + 1, 4) catch unreachable);
            },
            2 => { // End Node
                if (parent) |p| {
                    if (props.items.len > 0) {
                        devices.items[p].props = try props.toOwnedSlice(allocator);
                    }
                    parent = devices.items[p].parent;
                } else {
                    parent = null;
                }
                i += 1;
            },
            3 => { // Prop
                const value_byte_len = b2n(u32, structure_block[i + 1]);
                const value_cell_len = dc(u32, value_byte_len, 4) catch unreachable;

                const name_offs = b2n(u32, structure_block[i + 2]);
                const name = std.mem.span(@as([*:0]const u8, @ptrCast(&strings_block[@intCast(name_offs)])));
                @import("../io/uart.zig").printf("{s}", .{name});

                try props.append(allocator, .{ .name = name, .value = @as([]const u8, @ptrCast(structure_block[i + 3 .. i + 3 + value_cell_len]))[0..value_byte_len] });

                i += 3 + value_cell_len;
            },
            4 => { // NOP
                i += 1;
            },
            9 => break, // End
            else => unreachable,
        }
    }

    return .{
        .version = b2n(u32, header.version),
        .boot_cpu_id = b2n(u32, header.boot_cpuid_phys),
        .mem_rsv = mem_rsv,
        .devices = try devices.toOwnedSlice(allocator),
    };
}

// -- Usage -- //

pub fn getDeviceByName(self: *const @This(), name: []const u8) ?*const Device {
    for (self.devices) |*device|
        if (std.mem.eql(
            u8,
            device.name[0 .. std.mem.indexOfScalar(u8, device.name, '@') orelse device.name.len],
            name,
        )) return device;
    return null;
}

pub fn getCompatibleDevice(self: *const @This(), compatiblity: []const u8) ?*const Device {
    for (self.devices) |*device| {
        for (device.props) |*prop| {
            if (std.mem.eql(u8, prop.name, "compatible")) {
                var strings = std.mem.tokenizeScalar(u8, prop.value, 0);
                while (strings.next()) |string| if (std.mem.eql(u8, string, compatiblity)) {
                    return device;
                };
            }
        }
    }
    return null;
}

// -- Device -- //

pub const Device = struct {
    parent: ?usize,
    name: [:0]const u8,
    props: []const Prop,
    children: []const usize,

    pub fn getProp(self: *const @This(), name: []const u8) ?*const Prop {
        for (self.props) |*prop|
            if (std.mem.eql(u8, prop.name, name)) return prop;
        return null;
    }
};

pub const Prop = struct {
    name: [:0]const u8,
    value: []const u8,

    pub fn readInt(self: *const @This(), comptime T: type, offset: usize) !T {
        if (@typeInfo(T) != .int) unreachable;

        const len = @sizeOf(T);
        if (self.value.len < offset + len) return error.TooShort;

        return b2n(T, std.mem.bytesToValue(T, self.value[offset .. offset + len]));
    }
};

// -- Formatting -- //

pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print(
        \\[Devicetree]
        \\  - Header:
        \\    - Version: {}
        \\    - Boot CPU ID: {}
        \\
    , .{
        self.version,
        self.boot_cpu_id,
    });

    if (self.mem_rsv.len > 0) {
        try writer.print("  - Memory Reservations:\n", .{});
        for (self.mem_rsv) |rsv| {
            try writer.print("      - Address: 0x{X}, Size: 0x{X}\n", .{ rsv.address, rsv.size });
        }
    } else {
        try writer.print("  - No Memory Reservations\n", .{});
    }

    try writer.print("  - Devices:\n", .{});
    for (self.devices, 0..) |device, i| {
        try writer.print("    [{}] {s} (^{?})\n", .{ i, if (device.name.len == 0) "(root)" else device.name, device.parent });
        for (device.props) |prop| {
            try writer.print("      - {s}\n", .{prop.name});
        }
    }
}
