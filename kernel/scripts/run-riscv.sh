#!/bin/sh

qemu-system-riscv64 -machine virt -kernel zig-out/bin/kernel.elf -nographic