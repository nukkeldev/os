#!/bin/sh

mkdir -p zig-out/bin/

zig build-exe \
    -target riscv64-freestanding \
    --script src/linker.ld \
    -fno-ubsan-rt \
    -mcmodel=medany \
    -femit-bin=zig-out/bin/kernel.elf \
    src/entry.s src/main.zig