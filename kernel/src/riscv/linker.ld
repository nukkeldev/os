ENTRY(_start);

__stack_size = 4K;
__max_harts = 1;

MEMORY {
    RAM (rwx) : ORIGIN = 0x80200000, LENGTH = 2M
}

SECTIONS {
    .text : ALIGN(4K) {
        *(.init);
        *(.text*);
    } > RAM

    .rodata : ALIGN(4K) {
        *(.rodata*);
    } > RAM

    .data : ALIGN(4K) {
        *(.data*);
    } > RAM

    .bss : ALIGN(4K) {
        __bss_start = .;
        *(.bss*);
        . = ALIGN(8);
        __bss_end = .;

        . += __stack_size * __max_harts;
        __stack_top = .;
    } > RAM

    __kernel_end = .;
}