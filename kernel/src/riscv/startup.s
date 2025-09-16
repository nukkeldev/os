// The kernel's entrypoint after SBI.
//
// SBI leaves the hart in the following state:
// - S-mode (hence SBI).
// - a0 = hartid, a1 = devicetree blob ptr
// - (I believe) SBI leaves all harts, besides id=0, parked in M-Mode until they are started with HSM.
// 
// Referencing:
// 1. https://wiki.osdev.org/RISC-V_Bare_Bones
// 2. https://sourceware.org/binutils/docs/as.html#RISC_002dV_002dDirectives
// 3. https://github.com/riscv-non-isa/riscv-asm-manual/blob/main/src/asm-manual.adoc
// 4. The RISC-V Instruction Set Manual Volume II: Privileged Architecture [Version 20250508]
// 5. The RISC-V Instruction Set Manual Volume II: Unprivileged ISA [Version 20250508]
// 6. https://www.cs.sfu.ca/~ashriram/Courses/CS295/assets/notebooks/RISCV/RISCV_CARD.pdf
//
// Terminology:
// - `XLEN`: The width of registers in the _current_ mode.
//   - When prefixed with `U/S/M`, refers to the width in `User`, `Supervisor`, and `Machine` modes respectively.
// - `hart`: Hardware Thread; A basic unit of execution (i.e. a CPU core).

.section .init
.global _start

_start:
        // Set the stack pointer to the top of the stack.
        la sp, __stack_top 
        
        // Compute the stack offset for this hartid.
        // NOTE: We can't use la here as __stack_size is absolute (outside of a section).
        lui t0, %hi(__stack_size)
        addi t0, t0, %lo(__stack_size)
        mul t0, t0, a0

        // Add the offset to the stack pointer.
        add sp, sp, t0

        // Zero BSS
        la t0, __bss_start
        la t1, __bss_end
        bss:
                sd zero, (t0)
                addi t0, t0, 0x8
                bltu t0, t1, bss

        
        // Invoke `kmain_riscv` with a0=hartid and a1=dtb_ptr, setting the return address to ra.
        jal ra, kmain_riscv 

        // Hang if kmain returns.        
        1:
                wfi
                j 1b
.end