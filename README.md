# `rvhw`

An S-mode RISC-V kernel for on-device or "remote" hardware introspection. When loaded on device,
the kernel presents either an interactive shell or connects to a companion program, both over UART.
The companion program is the primary user target and is more featureful consequentially.

Features available in at least one method of interaction include:
> This list is proactive an not all features are implemented yet.
- Devicetree exploration
  - Downloading to a host computer
  - Viewing as DTS or graph
  - Inspecting individual devices
- Device interaction
 - Writing and reading from MMIO devices (with included drivers if available)
- Benchmarking
  - TODO

The kernel does not have `satp` enabled and does not allow for arbitrary code execution.

## See Also

The below resource were either referenced or intend to be referenced in the development of the
project.

### Blogs & Wikis

- [Uros Popovic's Blog](https://popovicu.com/)
  - Specifically his articles on RISC-V programming.
  - Served as the "push" to start this project.
- [RISC-V OS using Rust](https://osblog.stephenmarz.com/)
- [OSDev.org](https://wiki.osdev.org)

### Documentation and Manuals

- [The RISC-V Instruction Set Manual Volume I & II](https://riscv.org/specifications/ratified)
- [RISC-V Assembly Programmer's Manual](https://github.com/riscv-non-isa/riscv-asm-manual)
- [RISC-V Supervisor Binary Interface Documentation](https://github.com/riscv-non-isa/riscv-sbi-doc)
- [RISC-V Resource Collection](https://github.com/riscv/learn)

### Books

- [Edson Borin - An Introduction to Assembly Programming with RISC-V](https://riscv-programming.org/book/riscv-book.html)

## License

This project is licensed under the [MIT License](https://opensource.org/licenses/MIT).

You are free to use, modify, and distribute this software under the terms of the MIT license.  
See the [LICENSE](./LICENSE) file for full details.
