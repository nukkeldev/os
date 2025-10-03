//! Common messaging to send between the host and the device.
//!
//! All messages are serialized into the same format with a
//! fixed message length. Specific message types that require
//! longer messages can be split across multiple messages.
//!
//! Serialized messages start with a magic byte 0x01 for host
//! messages and 0x02 for device messages. Multiple users is a
//! non-goal. All messages end with 0xFF.
//!
//! Following this, the content type is encoded in a single byte
//! which determines how long the rest of the message is. The
//! recipient _MUST_ know how many bytes and/or messages the
//! entire message contains. For messages split into multiple parts
//! this length is indicated in the first message.

const std = @import("std");

/// The version of this protocol.
pub const VERSION: u8 = 0;
/// The maximum length of a message in bytes.
pub const MAX_MESSAGE_LENGTH: usize = 32;
pub const SENTINAL: u8 = 0xFF;

// -- Host Message -- //

/// Messages to send _from_ the host to the device.
pub const HostMessage = struct {
    /// The content of the message.
    content: Content,

    pub const MAGIC: u8 = 0x01;

    pub const Content = union(enum(u8)) {
        /// An initial message sent by the host to be assigned a host id by the device.
        /// Required to establish communication. The associated data is the version.
        @"are_you_there?": u8,

        /// Requests the current time as known by the device.
        @"what_time_is_it?",

        /// Ends the communication with the device; freeing up the host id.
        @"goodbye!",
    };

    pub fn expectsResponse(msg: *const @This()) bool {
        return switch (msg.content) {
            .@"are_you_there?", .@"what_time_is_it?" => true,
            .@"goodbye!" => false,
        };
    }
};

test HostMessage {
    const msg: HostMessage = .{
        .content = .{ .@"are_you_there?" = VERSION },
    };

    const bytes = try serialize(HostMessage, std.testing.allocator, &msg);
    defer std.testing.allocator.free(bytes);

    const msg2 = try deserialize(HostMessage, bytes);

    try std.testing.expectEqual(msg, msg2);
}

// -- Device Message -- //
//
/// Messages to send _to_ the host from the device.
pub const DeviceMessage = struct {
    /// The content of the message.
    content: Content,

    pub const MAGIC: u8 = 0x02;

    pub const Content = union(enum) {
        /// A response to the host's "are_you_there?" message.
        @"i_am_here!",

        /// A response to the host's "what_time_is_it?" message.
        /// Returns the current time in both ticks along with the timebase frequency.
        the_time_is: TheTimeIs,

        pub const TheTimeIs = extern struct {
            ticks: u64,
            freq: u64,
        };
    };
};

test DeviceMessage {
    const msg: DeviceMessage = .{
        .content = .@"i_am_here!",
    };

    const bytes = try serialize(DeviceMessage, std.testing.allocator, &msg);
    defer std.testing.allocator.free(bytes);

    const msg2 = try deserialize(DeviceMessage, bytes);

    try std.testing.expectEqual(msg, msg2);
}

// -- Serialization -- //

pub fn serialize(comptime MessageType: type, allocator: std.mem.Allocator, self: *const MessageType) ![:SENTINAL]u8 {
    var out = try allocator.allocSentinel(u8, MAX_MESSAGE_LENGTH - 1, SENTINAL);
    @memset(out, 0);

    out[0] = MessageType.MAGIC;
    out[1] = @intFromEnum(self.content);

    switch (self.content) {
        inline else => |content| blk: {
            if (@TypeOf(content) == void) break :blk;
            @memcpy(out[2 .. 2 + @sizeOf(@TypeOf(content))], std.mem.asBytes(&content));
        },
    }

    return out;
}

// -- Deserialization -- //

pub fn deserialize(comptime MessageType: type, bytes: [*:SENTINAL]const u8) !MessageType {
    const slice = std.mem.span(bytes);

    if (slice.len < 2) return error.TooShort;
    if (slice[0] != MessageType.MAGIC) return error.InvalidMagic;

    inline for (@typeInfo(MessageType.Content).@"union".fields, 0..) |field, i|
        if (slice[1] == i) {
            return .{
                .content = @unionInit(
                    MessageType.Content,
                    field.name,
                    if (field.type == void) {} else std.mem.bytesToValue(
                        field.type,
                        slice[2 .. 2 + @sizeOf(field.type)],
                    ),
                ),
            };
        };

    return error.UnknownContentType;
}
