#include <mmu.h>
#include <memlayout.h>
#include <defs.h>

#define __aligned(x)            __attribute__((aligned(x)))

uint64_t bootstack[KSTACKSIZE / sizeof(uint64_t)] __aligned(PGSIZE);
