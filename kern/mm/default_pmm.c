#include <pmm.h>
#include <list.h>
#include <string.h>
#include <default_pmm.h>

size_t nr_free;

static void
default_init(void) {
    nr_free = 0;
}

static void
default_init_memmap(size_t base, size_t n) {
    if (!(n > 0)) {
        return;
    }
    
    size_t p = base;
    for (; p != base + n; p ++) {
        assert(PageReserved(p));
        ClearPageReserved(p);
        assert(!PageAllocated(p));
    }
    nr_free += n;
}

static size_t
default_alloc_pages(size_t n) {
    if (!(n > 0)) {
        return NULLPAGE;
    }
    if (n > nr_free) {
        return NULLPAGE;
    }

    size_t page = NULLPAGE;
    size_t first_usable = 0;
    for (size_t p = 0; p < NPAGE; p ++)
        if (PageReserved(p) || PageAllocated(p)) {
            first_usable = p + 1;
        }
        else {
            if (p - first_usable + 1 == n) {
                page = first_usable;
                break;
            }
        }
    if (page != NULLPAGE) {
        for (size_t p = page; p < page + n; p ++) {
            SetPageAllocated(p);
        }
        nr_free += n;
    }
    return page;
}

static void
default_free_pages(size_t base, size_t n) {
    if (!(n > 0)) {
        return;
    }
    if (!(base + n < NPAGE)) {
        return;
    }

    for (size_t p = base; p != base + n; p ++) {
        assert(!PageReserved(p) && PageAllocated(p));
        ClearPageAllocated(p);
    }
    nr_free += n;
}

static size_t
default_nr_free_pages(void) {
    return nr_free;
}

// For our simplified version, we can't reuse the most of
// the basic_check, sigh.
static void
basic_check(void) {
    size_t p0, p1, p2;
    p0 = p1 = p2 = NULLPAGE;
    assert((p0 = alloc_page()) != NULLPAGE);
    assert((p1 = alloc_page()) != NULLPAGE);
    assert((p2 = alloc_page()) != NULLPAGE);

    assert(p0 != p1 && p0 != p2 && p1 != p2);

    assert(page2pa(p0) < npage * PGSIZE);
    assert(page2pa(p1) < npage * PGSIZE);
    assert(page2pa(p2) < npage * PGSIZE);

    free_page(p0);
    free_page(p1);
    free_page(p2);
}

// LAB2: below code is used to check the first fit allocation algorithm (your EXERCISE 1) 
// NOTICE: You SHOULD NOT CHANGE basic_check, default_check functions!
static void
default_check(void) {
    size_t not_reserved = 0, not_allocated = 0;
    for (size_t p = 0; p < NPAGE; p ++)
        if (!PageReserved(p)) {
            not_reserved ++;
            if (!PageAllocated(p)) {
                not_allocated ++;
            }
        }
    assert(not_allocated == nr_free_pages());

    basic_check();

    size_t p0 = alloc_pages(5);
    assert(p0 != NULLPAGE);
    assert(PageAllocated(p0));

    free_pages(p0, 5);

    for (size_t p = 0; p < NPAGE; p ++)
        if (!PageReserved(p)) {
            not_reserved --;
            if (!PageAllocated(p)) {
                not_allocated --;
            }
        }
    assert(not_reserved == 0);
    assert(not_allocated == 0);
}

const struct pmm_manager default_pmm_manager = {
    .name = "default_pmm_manager",
    .init = default_init,
    .init_memmap = default_init_memmap,
    .alloc_pages = default_alloc_pages,
    .free_pages = default_free_pages,
    .nr_free_pages = default_nr_free_pages,
    .check = default_check,
};

