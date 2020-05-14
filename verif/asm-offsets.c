#include "mmu.h"
#include "memlayout.h"
#include "riscv.h"

#define DEFINE(sym, val) \
        asm volatile("\n.ascii \"->" #sym " %0 " #val "\"" : : "i" (val))

void asm_offsets(void)
{
    DEFINE(KSTACKSIZE, KSTACKSIZE);
    DEFINE(IRQ_S_TIMER, IRQ_S_TIMER);
    DEFINE(NPAGE, NPAGE);
    DEFINE(PG_RESERVED, PG_reserved);
    DEFINE(PG_PROPERTY, PG_property);
}
