.section .text
.global trap_handler_riscv
.type  trap_handler_riscv, @function

trap_handler_riscv:
        addi sp, sp, -128
        sd ra, 120(sp)

        csrr a0, scause
        csrr a1, sepc
        csrr a2, stval
        mv   a3, sp

        j trap_handler_body_riscv

        ld ra, 120(sp)
        addi sp, sp, 128
        
        sret
        
