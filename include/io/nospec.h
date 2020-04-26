#pragma once

#include <io/bitsperlong.h>
#include <io/build_bug.h>
#include <io/compiler.h>

/**
 * array_index_mask_nospec() - generate a ~0 mask when index < size, 0 otherwise
 * @index: array element index
 * @size: number of elements in array
 *
 * When @index is out of bounds (@index >= @size), the sign bit will be
 * set.  Extend the sign bit to all bits and invert, giving a result of
 * zero for an out of bounds index, or ~0 if within bounds [0, @size).
 */
static inline unsigned long array_index_mask_nospec(unsigned long index,
                                                    unsigned long size)
{
        /*
         * Always calculate and emit the mask even if the compiler
         * thinks the mask is not needed. The compiler does not take
         * into account the value of @index under speculation.
         */
        OPTIMIZER_HIDE_VAR(index);
        return ~(long)(index | (size - 1UL - index)) >> (BITS_PER_LONG - 1);
}

/*
 * array_index_nospec - sanitize an array index after a bounds check
 *
 * For a code sequence like:
 *
 *     if (index < size) {
 *         index = array_index_nospec(index, size);
 *         val = array[index];
 *     }
 *
 * ...if the CPU speculates past the bounds check then
 * array_index_nospec() will clamp the index within the range of [0,
 * size).
 */
#define array_index_nospec(index, size)                                 \
({                                                                      \
        typeof(index) _i = (index);                                     \
        typeof(size) _s = (size);                                       \
        unsigned long _mask = array_index_mask_nospec(_i, _s);          \
                                                                        \
        BUILD_BUG_ON(sizeof(_i) > sizeof(long));                        \
        BUILD_BUG_ON(sizeof(_s) > sizeof(long));                        \
                                                                        \
        (typeof(_i)) (_i & _mask);                                      \
})

