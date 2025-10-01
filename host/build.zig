const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
        .imports = &.{
            .{ .name = "common", .module = b.dependency("common", .{}).module("common") },
        },
    });

    const exe = b.addExecutable(.{
        .root_module = mod,
        .name = "rvhwi",
    });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    const run_step = b.step("run", "");
    run_step.dependOn(&run.step);
}
