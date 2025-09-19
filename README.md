# `nukkel/os`

An operating system targeting 64-bit RISC-V written in Zig with no external libraries. It does not 
intend to be anything groundbreaking, rather it serves as a learning exercise.

Currently, only a basic S-mode kernel that supports the below features has been implemented.

- Startup (per-hart stack, clearing bss, etc.)
  - Though, only the boot hart is not parked.
- UART Output
- SBI Interaction
- Heap Allocation (as basic as possible)
- Devicetree parsing and traversal
- Panic handling

See the issue tracker for upcoming changes.

## See Also

The below resource were either referenced or intend to be referenced in the development of the
operating system.

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