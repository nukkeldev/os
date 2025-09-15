const std = @import("std");

const buildKernel = @import("kernel/build.zig").build;

pub fn build(b: *std.Build) void {
    buildKernel(b);
}