ENTRY(_start);

STACK_SIZE = 4K;
MAX_HARTS = 1;

MEMORY {
    kernel_space (rwx) : ORIGIN = 0x80200000, LENGTH = 2M
}

SECTIONS {
    .text : ALIGN(4K) {
        *(.text.init);
        *(.text*);
    } > kernel_space

    .rodata : ALIGN(4K) {
        *(.rodata*);
    } > kernel_space

    .data : ALIGN(4K) {
        *(.data*);
    } > kernel_space

    .bss : ALIGN(4K) {
        *(.bss*);
        . += STACK_SIZE * MAX_HARTS;
        PROVIDE(STACK_TOP = .);
    } > kernel_space
}