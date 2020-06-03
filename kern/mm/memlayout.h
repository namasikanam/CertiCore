#ifndef __KERN_MM_MEMLAYOUT_H__
#define __KERN_MM_MEMLAYOUT_H__

#include <mmu.h>

// NB: 4096 pages, excluding opensbi
// it's rather small, actually --hzl
// Notice: NPAGE is not the hardcoded npage
#ifdef IS_VERIF
#define NPAGE               0x0005
#else
#define NPAGE               0x1000
#endif

#define KERNEL_BEGIN_PADDR          0x80200000
#define PHYSICAL_MEMORY_OFFSET      0xFFFFFFFF40000000
#define PHYSICAL_MEMORY_END         0x88000000

/* All physical memory mapped at this virtual address */
#define KERNBASE            (KERNEL_BEGIN_PADDR + PHYSICAL_MEMORY_OFFSET)
// maximum amount of memory supported by certicore
#define KMEMSIZE            (NPAGE * PGSIZE)
// QEMU 缺省的RAM为 0x80000000到0x88000000, 128MiB, 0x80000000到0x80200000被OpenSBI占用
#define KERNTOP             (KERNBASE + KMEMSIZE)
#define KERNEL_MEMEND_PADDR (KERNEL_BEGIN_PADDR + KMEMSIZE)

#define NBASE               (KERNEL_BEGIN_PADDR >> PGSHIFT)

#define KSTACKPAGE          2                           // # of pages in kernel stack
#define KSTACKSIZE          (KSTACKPAGE * PGSIZE)       // sizeof kernel stack

#ifndef __ASSEMBLER__

#include <defs.h>
#include <atomic.h>
#include <list.h>

typedef uintptr_t pte_t;
typedef uintptr_t pde_t;

/* *
 * struct Page - Page descriptor structures. Each Page describes one
 * physical page. In kern/mm/pmm.h, you can find lots of useful functions
 * that convert Page to other data types, such as physical address.
 *
 * For convenience of verification, only flags here are reserved.
 * Other properties may be inserted in the future.
 * */
struct Page {
    uint64_t flags;                 // array of flags that describe the status of the page frame
};

/* Flags describing the status of a page frame */
#define PG_reserved                 0       // if this bit=1: the Page is reserved for kernel, cannot be used in alloc/free_pages; otherwise, this bit=0 
#define PG_allocated                1       // if this bit=1: the Page is allocated; otherwise, this bit=0

#define SetPageReserved(page)       set_bit(PG_reserved, &(pages[page].flags))
#define ClearPageReserved(page)     clear_bit(PG_reserved,&(pages[page].flags))
#define PageReserved(page)          test_bit(PG_reserved, &(pages[page].flags))

#define SetPageAllocated(page)       set_bit(PG_allocated, &(pages[page].flags))
#define ClearPageAllocated(page)     clear_bit(PG_allocated, &(pages[page].flags))
#define PageAllocated(page)          test_bit(PG_allocated, &(pages[page].flags))

#endif /* !__ASSEMBLER__ */

#endif /* !__KERN_MM_MEMLAYOUT_H__ */
