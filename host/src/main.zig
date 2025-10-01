const builtin = @import("builtin");

const std = @import("std");
const common = @import("common");

// -- Actions & Commands -- //

/// Actions that a command expects to be performed.
const Action = union(enum) {
    /// Sends a message to the device. If the message expects a response, blocks until
    /// it is recieved or the `RecvTimeout` is hit.
    SendMessage: struct {
        /// The message to send.
        message: common.HostMessage,
        /// What to do with the response, if there is one.
        callback: RecvCallback = defaultRecvCallback,

        /// The maximum time we wait to recieve a message back from the device.
        pub const RecvTimeout = 0.1;
        /// How to respond to the recieved message.
        pub const RecvCallback = *const fn (common.DeviceMessage) CommandError!void;

        /// A RecvCallback implementation that discards the message.
        pub fn defaultRecvCallback(message: common.DeviceMessage) CommandError!void {
            std.log.debug("Recieved message: {any}", .{message});
        }
    },
    /// Quits the application.
    Quit,
    /// Do nothing.
    NoOp,
};

/// Errors that a command could respond with.
const CommandError = error{
    /// The command was not found.
    NotFound,
};

/// Commands implementations.
const Commands = struct {
    const Command = struct {
        func: *const fn (*Args) CommandError!Action,
        brief: []const u8,
        help: []const u8,

        const Args = std.mem.TokenIterator(u8, .scalar);
    };

    const COMMAND_MAP: std.StaticStringMap(Command) = blk: {
        const decls = @typeInfo(@This()).@"struct".decls;

        var kvs: []const struct { []const u8, Command } = &.{};
        for (decls) |decl| {
            if (std.mem.eql(u8, "process", decl.name)) continue;
            var names = std.mem.splitScalar(u8, decl.name, ' ');
            while (names.next()) |name| {
                kvs = kvs ++ .{.{
                    name, Command{
                        .func = @field(@This(), decl.name),
                        .brief = @field(@This(), "BRIEF_" ++ decl.name),
                        .help = @field(@This(), "HELP_" ++ decl.name),
                    },
                }};
            }
        }

        break :blk .initComptime(kvs);
    };

    pub fn process(raw_cmd: []const u8) CommandError!Action {
        if (raw_cmd.len == 0) return Action.NoOp;

        std.log.debug("Processing command '{s}'.", .{raw_cmd});

        var cmd = std.mem.tokenizeScalar(u8, raw_cmd, ' ');
        const command = COMMAND_MAP.get(cmd.next().?) orelse return error.NotFound;
        return command.func(&cmd);
    }

    // -- Implementations -- //

    // Manual Send Message

    const @"BRIEF_send s": []const u8 =
        "(DEBUG) Manually sends a message to the device.";

    const @"HELP_send s": []const u8 =
        \\Manually sends a message to the device. This should only be used when
        \\debugging as higher-level commands properly compose messages together.
        \\If the message expects a reponse, the responses is printed out.
        \\
        \\Usage: (s)end <message-type> [message-data-field=data...]
        \\
        \\Required Arguments:
        \\    message-type - The type of the message. Must be one of:
        \\        TODO: Convert to a function to generate dynamically.
        \\
        \\Optional Arguments:
        \\    message-data-field - A key-value argument, seperated by an '=', for
        \\        messages that require additional data. For information on the fields
        \\        on each message, see 'help send <message-type>' (TODO).
        \\
    ;

    pub fn @"send s"(_: *Command.Args) CommandError!Action {
        return .{
            .SendMessage = .{
                .message = .{
                    .content = .{
                        .@"are_you_there?" = common.VERSION,
                    },
                },
            },
        };
    }

    // Help

    const @"BRIEF_help h ?": []const u8 =
        "Prints out all available commands or help on an individual command";

    const @"HELP_help h ?": []const u8 =
        \\When supplied with a command identifier, prints out the full help for that
        \\command if available. Otherwise, prints out the available commands and
        \\a brief description of each.
        \\
        \\Usage: (help|?) [command]
        \\
        \\Optional Arguments:
        \\    command - The command to print help for (if available)
        \\
    ;

    pub fn @"help h ?"(args: *Command.Args) CommandError!Action {
        if (args.next()) |alias| {
            if (COMMAND_MAP.get(alias)) |command| {
                std.debug.print("{s}\n", .{command.help});
            } else {
                return error.NotFound;
            }
        } else {
            const message = comptime getAvailableCommandsMessage();
            std.debug.print(message, .{});
        }

        return .NoOp;
    }

    fn getAvailableCommandsMessage() []const u8 {
        var message: []const u8 =
            \\Available Commands:
            \\
        ;

        const decls = @typeInfo(@This()).@"struct".decls;
        inline for (decls) |decl| {
            if (std.mem.eql(u8, "process", decl.name)) continue;

            message = message ++ "\t";
            var names = std.mem.splitScalar(u8, decl.name, ' ');
            while (names.next()) |name| {
                message = message ++ name;
                if (names.peek() != null) message = message ++ ", ";
            }

            message = message ++ " - " ++ @field(@This(), "BRIEF_" ++ decl.name) ++ "\n";
        }

        return message;
    }

    // Quit

    const @"BRIEF_quit q": []const u8 =
        "Quits the program";

    const @"HELP_quit q": []const u8 =
        \\Quits the program.
        \\
        \\Usage: (q)uit
        \\
    ;

    pub fn @"quit q"(_: *Command.Args) CommandError!Action {
        return Action.Quit;
    }
};

// -- Main -- //

/// The maximum number of bytes read from stdin at once.
const MAXIMUM_COMMAND_LENGTH = 2048;

const MAX_SOCKET_CONNECTION_ATTEMPTS = std.math.maxInt(usize);
const SOCKET_CONNECTION_DELAY = std.time.ns_per_s;
const UART_SOCKET_PATH = "/tmp/rvhw.uart.sock";

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{}).init;

    const gpa, const is_debug = switch (builtin.mode) {
        .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
        .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    var arena_instance = std.heap.ArenaAllocator.init(gpa);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    var uart_stream: std.net.Stream = undefined;

    var connection_attempts: usize = 0;
    while (connection_attempts < MAX_SOCKET_CONNECTION_ATTEMPTS) {
        uart_stream = std.net.connectUnixSocket(UART_SOCKET_PATH) catch |e| {
            std.log.err("[{}/{}] Failed to connect to UART socket! Error: {}", .{
                connection_attempts,
                MAX_SOCKET_CONNECTION_ATTEMPTS,
                e,
            });
            std.log.info("Retrying in {D}...", .{SOCKET_CONNECTION_DELAY});
            std.Thread.sleep(SOCKET_CONNECTION_DELAY);
            connection_attempts += 1;
            continue;
        };
        break;
    } else {
        std.log.err("Maximum connection attempts hit! Exiting...", .{});
        return;
    }

    std.log.info("Connected to UART socket \"{s}\".", .{UART_SOCKET_PATH});
    defer uart_stream.close();

    var uart_reader_buf: [1024]u8 = undefined;
    var uart_writer_buf: [1024]u8 = undefined;

    var uart_reader = uart_stream.reader(&uart_reader_buf);
    var uart_writer = uart_stream.writer(&uart_writer_buf);
    const uart_reader_in: *std.Io.Reader = uart_reader.interface();
    const uart_writer_in: *std.Io.Writer = &uart_writer.interface;

    var stdout = std.fs.File.stdout().writerStreaming(&.{});
    var stdin = std.fs.File.stdin().readerStreaming(&.{});

    var buf: [MAXIMUM_COMMAND_LENGTH]u8 = undefined;
    var buf_in: std.Io.Writer = .fixed(&buf);

    var uart_buf: [common.MAX_MESSAGE_LENGTH - 1:common.SENTINAL]u8 = undefined;
    var uart_buf_in: std.Io.Writer = .fixed(&uart_buf);

    while (stdin.interface.stream(&buf_in, .limited(MAXIMUM_COMMAND_LENGTH))) |n| {
        if (n > 0) blk: {
            const cmd = std.mem.trim(u8, buf[0..n], &std.ascii.whitespace);
            const action = Commands.process(cmd) catch |e| {
                std.log.err("Command returned an error: {}", .{e});
                break :blk;
            };

            sw: switch (action) {
                .SendMessage => |payload| {
                    const bytes = try common.serialize(common.HostMessage, arena, &payload.message);
                    std.log.debug("Sending serialized message {any} to the device.", .{bytes});
                    _ = uart_writer_in.write(bytes) catch unreachable;
                    uart_writer_in.flush() catch |e| {
                        std.log.err("Failed to send message over UART! Error: {}", .{e});
                        break :sw;
                    };

                    if (payload.message.expectsResponse()) {
                        uart_buf_in.end = 0;
                        while (uart_reader_in.takeByte()) |b| {
                            if (b == common.DeviceMessage.MAGIC) {
                                std.log.debug("Read magic byte from UART.", .{});
                                uart_buf_in.writeByte(b) catch {};
                                break;
                            } else {
                                if (b == 0) continue;
                                std.log.debug("Discarding byte: {}", .{b});
                            }
                        } else |e| {
                            std.log.err("Error while reading response! Error: {}", .{e});
                            break :sw;
                        }
                        const len = uart_reader_in.stream(&uart_buf_in, .limited(common.MAX_MESSAGE_LENGTH - 2)) catch |e| {
                            std.log.err("Error while reading response after magic! Error: {}", .{e});
                            break :sw;
                        };
                        if (len != common.MAX_MESSAGE_LENGTH - 2) {
                            std.log.err("Recieved incomplete message ({} bytes)!", .{len + 1});
                            break :sw;
                        }

                        std.log.debug("Recieved response: '{s}' ({any})", .{ uart_buf, uart_buf });

                        const response = common.deserialize(common.DeviceMessage, @ptrCast(&uart_buf)) catch |e| {
                            std.log.err("Failed to deserialize recieved message: {}", .{e});
                            break :sw;
                        };
                        std.log.debug("Deserialized message: {any}", .{response});
                    }
                },
                .Quit => {
                    std.log.info("Goodbye!", .{});
                    break;
                },
                .NoOp => {},
            }
        }

        buf_in.end = 0;
        _ = try stdout.interface.write("\n> ");
    } else |e| return e;
}
