.section .text
.global trap_handler_riscv

trap_handler_riscv:
        sret
        
