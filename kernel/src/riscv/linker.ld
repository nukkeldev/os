ENTRY(_start);

__stack_size = 4K;
__max_harts = 1;

MEMORY {
    KERNEL (rwx) : ORIGIN = 0x80200000, LENGTH = 2M
}

SECTIONS {
    .text : ALIGN(4K) {
        *(.init);
        *(.text*);
    } > KERNEL

    .rodata : ALIGN(4K) {
        *(.rodata*);
    } > KERNEL

    .data : ALIGN(4K) {
        *(.data*);
    } > KERNEL

    .bss : ALIGN(4K) {
        __bss_start = .;
        *(.bss*);
        . = ALIGN(8);
        __bss_end = .;

        . += __stack_size * __max_harts;
        __stack_top = .;
    } > KERNEL

    __kernel_end = .;
}