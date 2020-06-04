#include <defs.h>
#include <riscv.h>
#include <stdio.h>
#include <string.h>
#include <swap.h>
#include <swap_clock.h>
#include <list.h>

/* [wikipedia]The simplest Page Replacement Algorithm(PRA) is a FIFO algorithm. The first-in, first-out
 * page replacement algorithm is a low-overhead algorithm that requires little book-keeping on
 * the part of the operating system. The idea is obvious from the name - the operating system
 * keeps track of all the pages in memory in a queue, with the most recent arrival at the back,
 * and the earliest arrival in front. When a page needs to be replaced, the page at the front
 * of the queue (the oldest page) is selected. While FIFO is cheap and intuitive, it performs
 * poorly in practical application. Thus, it is rarely used in its unmodified form. This
 * algorithm experiences Belady's anomaly.
 *
 * Details of FIFO PRA
 * (1) Prepare: In order to implement FIFO PRA, we should manage all swappable pages, so we can
 *              link these pages into pra_list_head according the time order. At first you should
 *              be familiar to the struct list in list.h. struct list is a simple doubly linked list
 *              implementation. You should know howto USE: list_init, list_add(list_add_after),
 *              list_add_before, list_del, list_next, list_prev. Another tricky method is to transform
 *              a general list struct to a special struct (such as struct page). You can find some MACRO:
 *              le2page (in memlayout.h), (in future labs: le2vma (in vmm.h), le2proc (in proc.h),etc.
 */

list_entry_t pra_list_head, *curr_ptr;
/*
 * (2) _fifo_init_mm: init pra_list_head and let  mm->sm_priv point to the addr of pra_list_head.
 *              Now, From the memory control struct mm_struct, we can access FIFO PRA
 */
static int
_clock_init_mm(struct mm_struct *mm)
{     
     list_init(&pra_list_head);
     curr_ptr = &pra_list_head;
     mm->sm_priv = &pra_list_head;
     //cprintf(" mm->sm_priv %x in fifo_init_mm\n",mm->sm_priv);
     return 0;
}
/*
 * (3)_fifo_map_swappable: According FIFO PRA, we should link the most recent arrival page at the back of pra_list_head qeueue
 */
static int
_clock_map_swappable(struct mm_struct *mm, uintptr_t addr, struct Page *page, int swap_in)
{
    list_entry_t *entry=&(page->pra_page_link);
 
    assert(entry != NULL && curr_ptr != NULL);
    //record the page access situlation
    /*LAB3 EXERCISE 2: YOUR CODE*/ 
    //(1)link the most recent arrival page at the back of the pra_list_head qeueue.
    list_add(curr_ptr, entry);
    page->visited = 1;
    return 0;
}
/*
 *  (4)_fifo_swap_out_victim: According FIFO PRA, we should unlink the  earliest arrival page in front of pra_list_head qeueue,
 *                            then set the addr of addr of this page to ptr_page.
 */
static int
_clock_swap_out_victim(struct mm_struct *mm, struct Page ** ptr_page, int in_tick)
{
     list_entry_t *head=(list_entry_t*) mm->sm_priv;
         assert(head != NULL);
     assert(in_tick==0);
     /* Select the victim */
     /*LAB3 EXERCISE 2: YOUR CODE*/ 
     //(1)  unlink the  earliest arrival page in front of pra_list_head qeueue
     //(2)  set the addr of addr of this page to ptr_page
    while (1) {
        if (curr_ptr == head) {
            curr_ptr = list_prev(curr_ptr);
            continue;
        }
        cprintf("curr_ptr %p\n", curr_ptr);
        struct Page* curr_page = le2page(curr_ptr, pra_page_link);
        if (curr_page->visited == 0) {
            curr_ptr = list_prev(curr_ptr);
            list_del(list_next(curr_ptr));
            *ptr_page = curr_page;
            return 0;
        } else {
            curr_page->visited = 0;
        }
    }
    return 0;
}

static int
_clock_check_swap(void) {
    /*cprintf("write Virt Page c in clock_check_swap\n");*/
    /**(unsigned char *)0x3000 = 0x0c;*/
    /*assert(pgfault_num==4);*/
    /*cprintf("write Virt Page a in clock_check_swap\n");*/
    /**(unsigned char *)0x1000 = 0x0a;*/
    /*assert(pgfault_num==4);*/
    /*cprintf("write Virt Page d in clock_check_swap\n");*/
    /**(unsigned char *)0x4000 = 0x0d;*/
    /*assert(pgfault_num==4);*/
    /*cprintf("write Virt Page b in clock_check_swap\n");*/
    /**(unsigned char *)0x2000 = 0x0b;*/
    /*assert(pgfault_num==4);*/
    /*cprintf("write Virt Page e in clock_check_swap\n");*/
    /**(unsigned char *)0x5000 = 0x0e;*/
    /*assert(pgfault_num==5);*/
    /*cprintf("write Virt Page b in clock_check_swap\n");*/
    /**(unsigned char *)0x2000 = 0x0b;*/
    /*assert(pgfault_num==5);*/
    /*cprintf("write Virt Page a in clock_check_swap\n");*/
    /**(unsigned char *)0x1000 = 0x0a;*/
    /*assert(pgfault_num==6);*/
    /*cprintf("write Virt Page b in clock_check_swap\n");*/
    /**(unsigned char *)0x2000 = 0x0b;*/
    /*assert(pgfault_num==7);*/
    /*cprintf("write Virt Page c in clock_check_swap\n");*/
    /**(unsigned char *)0x3000 = 0x0c;*/
    /*assert(pgfault_num==8);*/
    /*cprintf("write Virt Page d in clock_check_swap\n");*/
    /**(unsigned char *)0x4000 = 0x0d;*/
    /*assert(pgfault_num==9);*/
    /*cprintf("write Virt Page e in clock_check_swap\n");*/
    /**(unsigned char *)0x5000 = 0x0e;*/
    /*assert(pgfault_num==10);*/
    /*cprintf("write Virt Page a in clock_check_swap\n");*/
    /*assert(*(unsigned char *)0x1000 == 0x0a);*/
    /**(unsigned char *)0x1000 = 0x0a;*/
    /*assert(pgfault_num==11);*/
    return 0;
}


static int
_clock_init(void)
{
    return 0;
}

static int
_clock_set_unswappable(struct mm_struct *mm, uintptr_t addr)
{
    return 0;
}

static int
_clock_tick_event(struct mm_struct *mm)
{ return 0; }


struct swap_manager swap_manager_clock =
{
     .name            = "clock swap manager",
     .init            = &_clock_init,
     .init_mm         = &_clock_init_mm,
     .tick_event      = &_clock_tick_event,
     .map_swappable   = &_clock_map_swappable,
     .set_unswappable = &_clock_set_unswappable,
     .swap_out_victim = &_clock_swap_out_victim,
     .check_swap      = &_clock_check_swap,
};
