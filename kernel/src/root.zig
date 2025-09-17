comptime {
    _ = @import("riscv/kernel.zig");
}

pub const panic = @import("riscv/kernel.zig").panic;