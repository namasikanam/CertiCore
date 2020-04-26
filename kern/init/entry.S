#include <mmu.h>
#include <memlayout.h>

    .section .text,"ax",%progbits
    .globl kern_entry
kern_entry:
    la sp, bootstack + KSTACKSIZE

    tail kern_init

// changed the section to bss because of Serval's restriction
// -- hzl
