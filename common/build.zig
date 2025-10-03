const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("common", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/root.zig"),
    });

    const test_exe = b.addTest(.{ .root_module = mod });
    const run_test = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Tests");
    test_step.dependOn(&run_test.step);
}
