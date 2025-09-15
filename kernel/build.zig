const std = @import("std");

pub fn build(b: *std.Build) void {
    // const target = b.standardTargetOptions(.{
    //     // TODO: Add the supported systems and the default target.
    // });
    // const optimize = b.standardOptimizeOption(.{});

    // const mod = b.createModule(.{
    //     .target = target,
    //     .optimize = optimize,
    // });

    // const exe = b.addExecutable(.{
    //     .name = "kernel",
    //     .root_module = mod,
    // });
    _ = b;
}

pub fn registerQemuTLS(b: *std.Build, target: *std.Target, kernel: *std.Build.Step.Compile) *std.Build.Step {
    // const qemu_system = switch (target.cpu.arch) {
    //     .riscv64, .x86_64 => @tagName(),
    // };
    _ = b;
    _ = target;
    _ = kernel;
}
