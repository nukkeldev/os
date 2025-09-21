const std = @import("std");

pub fn build(b: *std.Build) void {
    // -- Compilation -- //

    // Options

    const optimize = b.standardOptimizeOption(.{});
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .riscv64,
        .os_tag = .freestanding,
        .abi = .none,
    });

    const uart = b.option(bool, "uart", "Enable UART output (default=false)") orelse false;

    // Options Module

    const options = b.addOptions();
    options.addOption(bool, "uart", uart);

    // ---

    const mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        // Ensure the kernel uses relative symbol addresses so things work after vm relocation.
        .code_model = .medany,
        .strip = false,
    });
    mod.addImport("options", options.createModule());

    const exe = b.addExecutable(.{
        .name = "kernel.elf",
        .root_module = mod,
    });

    exe.addAssemblyFile(b.path("src/riscv/trap.s"));
    exe.addAssemblyFile(b.path("src/riscv/startup.s"));
    exe.setLinkerScript(b.path("src/riscv/linker.ld"));

    const install_exe = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install_exe.step);

    // -- Run Steps -- //

    // Options

    const nographic = b.option(bool, "run-nographic", "Whether to pass -nographic to QEMU (default=true)") orelse true;
    const gdb = b.option(bool, "run-gdb", "Whether to pass -gdb tcp::{gdb_port} to QEMU (default=false)") orelse false;
    const gdb_port = b.option(usize, "run-gdb-port", "The port to start the gdb server (default=1234)") orelse 1234;
    const freeze = b.option(bool, "run-freeze", "Whether to pass -S to QEMU (default=false)") orelse false;

    {
        const run_step = b.step("run", "Builds and runs the kernel in qemu");
        const cmd = b.addSystemCommand(&.{
            "qemu-system-riscv64",
            "-machine",
            "virt",
            "-m",
            "1G",
            "-device",
            "virtio-vga", // VGA over PCI
            "-kernel",
        });
        cmd.addFileArg(b.path("zig-out/bin/kernel.elf"));

        if (nographic) cmd.addArg("-nographic");
        if (gdb) {
            cmd.addArg("-gdb");
            cmd.addArg(b.fmt("tcp::{}", .{gdb_port}));
        }
        if (freeze) cmd.addArg("-S");

        cmd.step.dependOn(&install_exe.step);
        run_step.dependOn(&cmd.step);
    }
}
