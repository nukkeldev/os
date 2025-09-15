pub export fn kmain() noreturn {
    UART.print("Hello, World!\n");
    while (true) {}
}

// -- UART -- //

pub const UART = struct {
    const ADDR: *u8 = @ptrFromInt(0x10_000_000);

    fn putChar(c: u8) void {
        ADDR.* = c;
    }

    fn print(str: []const u8) void {
        for (str) |c| putChar(c);
    }
};
