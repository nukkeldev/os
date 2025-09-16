ENTRY(_start);

STACK_SIZE = 4K;
MAX_HARTS = 1;

MEMORY {
    KERNEL (rwx) : ORIGIN = 0x80200000, LENGTH = 2M
}

SECTIONS {
    .text : ALIGN(4K) {
        *(.text.init);
        *(.text*);
    } > KERNEL

    .rodata : ALIGN(4K) {
        *(.rodata*);
    } > KERNEL

    .data : ALIGN(4K) {
        *(.data*);
    } > KERNEL

    .bss : ALIGN(4K) {
        *(.bss*);
        . += STACK_SIZE * MAX_HARTS;
        PROVIDE(__stack_top = .);
    } > KERNEL

    PROVIDE(__kernel_end = .);
}