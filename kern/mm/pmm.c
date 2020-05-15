#include <default_pmm.h>
#include <defs.h>
#include <error.h>
#include <memlayout.h>
#include <mmu.h>
#include <pmm.h>
#include <sbi.h>
#include <stdio.h>
#include <string.h>
#include <sync.h>
#include <riscv.h>

// virtual address of physical page array
struct Page pages[NPAGE];
// amount of physical memory (in pages)
size_t npage;
// start of physical memory (in pages)
size_t nbase;
// the kernel image is mapped at VA=KERNBASE and PA=info.base
uint64_t va_pa_offset;

// virtual address of boot-time page directory
uintptr_t satp_virtual;
// physical address of boot-time page directory
uintptr_t satp_physical;

// physical memory management
struct pmm_manager pmm_manager;

static void check_alloc_page(void);

// init_pmm_manager - initialize a pmm_manager instance
static void init_pmm_manager(void) {
    pmm_manager = default_pmm_manager;
    cprintf("memory management: %s\n", pmm_manager.name);
    pmm_manager.init();
}

// init_memmap - call pmm->init_memmap to build Page struct for free memory
static void init_memmap(size_t base, size_t n) {
    pmm_manager.init_memmap(base, n);
}

// alloc_pages - call pmm->alloc_pages to allocate a continuous n*PAGESIZE
// memory
size_t alloc_pages(size_t n) {
    size_t page = NULLPAGE;
    bool intr_flag;
    local_intr_save(intr_flag);
    {
        page = pmm_manager.alloc_pages(n);
    }
    local_intr_restore(intr_flag);
    return page;
}

// free_pages - call pmm->free_pages to free a continuous n*PAGESIZE memory
void free_pages(size_t base, size_t n) {
    bool intr_flag;
    local_intr_save(intr_flag);
    {
        pmm_manager.free_pages(base, n);
    }
    local_intr_restore(intr_flag);
}

// nr_free_pages - call pmm->nr_free_pages to get the size (nr*PAGESIZE)
// of current free memory
size_t nr_free_pages(void) {
    size_t ret;
    bool intr_flag;
    local_intr_save(intr_flag);
    {
        ret = pmm_manager.nr_free_pages();
    }
    local_intr_restore(intr_flag);
    return ret;
}

static void page_init(void) {
    va_pa_offset = PHYSICAL_MEMORY_OFFSET;
    nbase = NBASE;
    npage = NBASE + NPAGE;

    uint64_t mem_begin = KERNEL_BEGIN_PADDR;
    uint64_t mem_size = KERNEL_MEMEND_PADDR - KERNEL_BEGIN_PADDR;
    uint64_t mem_end = KERNEL_MEMEND_PADDR; // 硬编码

    cprintf("physcial memory:\n");
    cprintf("  memory: 0x%016lx, [0x%016lx, 0x%016lx].\n", mem_size, mem_begin, mem_end - 1);

    extern char end[];

    for (size_t i = 0; i < NPAGE; i++) {
        // clear flag for the beauty of zero
        pages[i].flags= 0; 
        SetPageReserved(i);
    }

    uintptr_t freemem = PADDR((uintptr_t)end);
    mem_begin = ROUNDUP(freemem, PGSIZE);
    mem_end = ROUNDDOWN(mem_end, PGSIZE);
    if (mem_end > npage * PGSIZE) {
        mem_end = npage * PGSIZE;
    }

    if (freemem < mem_end) {
        init_memmap(pa2page(mem_begin), (mem_end - mem_begin) / PGSIZE);

        // just debugging
        cprintf("free memory :\n");
        cprintf("  memory: 0x%016lx, [0x%016lx, 0x%016lx].\n", mem_end - mem_begin, mem_begin, mem_end - 1);
    }
}

/* pmm_init - initialize the physical memory management */
void pmm_init(void) {
    // We need to alloc/free the physical memory (granularity is 4KB or other size).
    // So a framework of physical memory manager (struct pmm_manager)is defined in pmm.h
    // First we should init a physical memory manager(pmm) based on the framework.
    // Then pmm can alloc/free the physical memory.
    // Now the first_fit/best_fit/worst_fit/buddy_system pmm are available.
    init_pmm_manager();

    // detect physical memory space, reserve already used memory,
    // then use pmm->init_memmap to create free page list
    page_init();

    // use pmm->check to verify the correctness of the alloc/free function in a pmm
    check_alloc_page();

    extern char boot_page_table_sv39[];
    satp_virtual = (uintptr_t)boot_page_table_sv39;
    satp_physical = PADDR(satp_virtual);
    cprintf("satp virtual address: 0x%016lx\nsatp physical address: 0x%016lx\n", satp_virtual, satp_physical);
}

static void check_alloc_page(void) {
    pmm_manager.check();
    cprintf("check_alloc_page() succeeded!\n");
}
