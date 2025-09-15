// The kernel's entrypoint.
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

// Place the below code in the `.init` section.
// TODO: Not sure if this is convention or preference.
.section .init

.option norvc // [#2 9.38.2] Disable compressed instructions.

.type _start, @function // [DEBUG] Indicate `_start` to be a function.
.global _start // Export `_start`.

_start: // Define the start symbol.
        .cfi_startproc // [DEBUG, #2 7.13]
        
        .option push // Push the options stack.
        .option norelax // [#2 9.38.2] Ensures the following instructions aren't "optimized" away.
        // [#3] `la` is a pseudo-instruction that maps (on 32-bit) to a `lui` and `addi`, which first
        // load the upper 20 bits of the symbol's address due to `lui` being a U-Type instruction with an imm20
        // parameter, then adds the lower 12 bits with `addi`'s I-Type imm12. See the documentation for a better
        // explanation.
        la gp, global_pointer // Loads the `global_pointer` linker symbol into the global pointer register.
        .option pop // Pop the options stack.

        // [#4 12.1.11] Zero out the "Supervisor Address Translation and Protection (`satp`) Register",
        // which sets the mode to "Bare" and performs "no translation or protection". The entire register
        // MUST be set to zero when in this mode.
        csrw satp, zero

        la sp, stack_top // Set the stack pointer to the top of the stack (as specified by the linker).

        // Temporarily store the BSS's start and end.
        la t5, bss_start
        la t6, bss_end
        
        // Loop through the BSS section until it's all zeros.
        bss_clear:
                sd zero, (t5) // "Store double" of zero in the address of `t5`.
                addi t5, t5, 8 // Move forward 8 bytes.
                // [#5 2.5.2] Jump back to the start of the loop if `t5` is less than `t6` (the end of bss)
                // when interpreted unsigned-ly.
                bltu t5, t6, bss_clear

        tail kmain

        # la t0, kmain // Load the address of the `kmain` function into `t0`.
        # // [#4 3.1.14] Writes the address of `kmain` to the CSR "Machine Exception Program Counter (mepc)".
        # // This defines where `mret` will jump to.
        # csrw mepc, t0

        # // [#4 3.1.6] Read one the "Machine Status (`mstatus` and `mstatush`) Registers" into `t1`.
        # // `mstatus` "keeps track of and controls the hart’s current operating state".
        # csrr t1, mstatus
        # // Load a mask of the MPP bits into a register. We can't use `andi` because it only uses imm12.
        # li   t2, ~(3 << 11)
        # and  t1, t1, t2 // Clear the MPP bits.
        # li   t2,  (1 << 11)
        # or   t1, t1, t2 // Enable Supervisor mode.
        # csrw mstatus, t1 // Write back to the status.
        
        # mret // Jump to `kmain`.

        .cfi_endproc // [DEBUG, #2 7.13]
.end