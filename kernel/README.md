# `nukkel/os/kernel`

A modular, monolithic kernel (similar in architecture to Linux). It doesn't particularly have
any features as of now, but hopefully that changes. Currently, I intend for the kernel to be
as small as possible, in the spirit of RISC-V, and to load further functionality based on priority
or need. The kernel will provide an API for the modules to implement their functionality, `SBI` will 
not be exposed, and modules will be compiled into the kernel itself (unlike Linux).

## File Structure

As this kernel will eventually be cross-platform, the file structure makes an attempt to separate
and minimize the amount of platform-dependent code. Unfortunately, this is quite difficult.

Below lists the `src` directory, notable files within, and comments as to their purpose: 

```bash
src
├── io # General platform-independent I/O-related files
│   └── uart.zig
├── riscv # RISC-V-specific files (startup, linking, kmain, *AL impl, etc.)
│   ├── kernel.zig
│   ├── linker.ld
│   ├── sbi.zig
│   └── startup.s
├── root.zig # Defines src root and exposes platform-specific symbols
└── util # Platform-independent utility files
    └── devicetree
        ├── devicetree.zig
        └── devicetree_blob.zig
```