.section .text.init
.global _start
.type   _start, @function

_start:
        // Park all harts but the boot.
        bnez a0, halt

        // Set the stack pointer to the top of the stack.
        la sp, __stack_top
        
        // Compute the stack offset for this hartid.
        // NOTE: We can't use la here as __stack_size is absolute (outside of a section).
        lui t0, %hi(__stack_size)
        addi t0, t0, %lo(__stack_size)
        mul t0, t0, a0

        // Add the offset to the stack pointer.
        add sp, sp, t0

        // Zero BSS because it's annotated as NOLOAD.
        la t0, __bss_start
        la t1, __bss_end
        bgeu t0, t1, 2f
        1:
                sd zero, (t0)
                addi t0, t0, 8
                bltu t0, t1, 1b
        2:
        
        // Reset timer interrupts
        mv t0, a0
        mv t1, a1
        jal ra, reset_time_interrupts_riscv
        mv a0, t0
        mv a1, t1

        // Setup S-mode traps
        la t0, interrupt_handler_riscv
        csrw stvec, t0

        // Configure interrupts
        li t0, (1 << 1) | (1 << 5) | (1 << 8)
        csrs sstatus, t0      

        // Set sret to return to kmain
        la t1, kmain
        csrw sepc, t1

        // Enable interrupts
        li t3, (1 << 9) | (1 << 1) | (1 << 5)
        csrs sie, t3

        // If we return, park the hart.
        la ra, halt
        sret

        // Hang if kmain returns.        
        halt:
                wfi
                j halt
.end
