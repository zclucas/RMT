/*
 * Copyright 2021 Stanislav Paskalev <spaskalev@protonmail.com>
 *
 * A binary buddy memory allocator
 *
 * To include and use it in your project do the following
 * 1. Add buddy_alloc.h (this file) to your include directory
 * 2. Include the header in places where you need to use the allocator
 * 3. In one of your source files #define BUDDY_ALLOC_IMPLEMENTATION
 *    and then import the header. This will insert the implementation.
 *
 * Latest version is available at https://github.com/spaskalev/buddy_alloc
 */

#ifndef BUDDY_ALLOC_H
#define BUDDY_ALLOC_H

#ifndef BUDDY_HEADER
#include <limits.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <sys/types.h>
#ifndef BUDDY_PRINTF
#include <stdio.h>
#endif
#endif

#ifdef __cplusplus
#ifndef BUDDY_CPP_MANGLED
extern "C" {
#endif
#endif

struct buddy;

/* Returns the size of a buddy required to manage a block of the specified size */
size_t buddy_sizeof(size_t memory_size);

/*
 * Returns the size of a buddy required to manage a block of the specified size
 * using a non-default alignment.
 */
size_t buddy_sizeof_alignment(size_t memory_size, size_t alignment);

/* Initializes a binary buddy memory allocator at the specified location */
struct buddy *buddy_init(unsigned char *at, unsigned char *main, size_t memory_size);

/* Initializes a binary buddy memory allocator at the specified location using a non-default alignment */
struct buddy *buddy_init_alignment(unsigned char *at, unsigned char *main, size_t memory_size, size_t alignment);

/*
 * Initializes a binary buddy memory allocator embedded in the specified arena.
 * The arena's capacity is reduced to account for the allocator metadata.
 */
struct buddy *buddy_embed(unsigned char *main, size_t memory_size);

/*
 * Returns the address of a previously-created buddy allocator at the arena.
 * Use to get a new handle to the allocator when the arena is moved or copied.
 */
struct buddy *buddy_get_embed_at(unsigned char *main, size_t memory_size);

/*
 * Initializes a binary buddy memory allocator embedded in the specified arena
 * using a non-default alignment.
 * The arena's capacity is reduced to account for the allocator metadata.
 */
struct buddy *buddy_embed_alignment(unsigned char *main, size_t memory_size, size_t alignment);

/*
 * Returns the address of a previously-created buddy allocator at the arena.
 * Use to get a new handle to the allocator when the arena is moved or copied.
 */
struct buddy *buddy_get_embed_at_alignment(unsigned char *main, size_t memory_size, size_t alignment);

/* 
 * Resizes the arena and allocator metadata to a new size.
 *
 * Existing allocations are preserved. If an allocation is to fall outside
 * of the arena after a downsizing the resize operation fails.
 *
 * Returns a pointer to allocator on successful resize. This will be
 * the same pointer when the allocator is external to the arena. If the
 * allocator is embedded in the arena the old pointer to the allocator
 * must not be used after resizing!
 *
 * Returns NULL on failure. The allocations and allocator pointer
 * are preserved.
 */
struct buddy *buddy_resize(struct buddy *buddy, size_t new_memory_size);

/* Tests if the arena can be shrunk in half */
bool buddy_can_shrink(struct buddy *buddy);

/* Tests if the arena is completely empty */
bool buddy_is_empty(struct buddy *buddy);

/* Tests if the arena is completely full */
bool buddy_is_full(struct buddy *buddy);

/* Reports the arena size */
size_t buddy_arena_size(struct buddy *buddy);

/* Reports the arena's free size. Note that this is (often) not a continuous size
   but the sum of all free slots in the buddy. */
size_t buddy_arena_free_size(struct buddy *buddy);

/*
 * Allocation functions
 */

/* Use the specified buddy to allocate memory. See malloc. */
void *buddy_malloc(struct buddy *buddy, size_t requested_size);

/* Use the specified buddy to allocate zeroed memory. See calloc. */
void *buddy_calloc(struct buddy *buddy, size_t members_count, size_t member_size);

/* Realloc semantics are a joke. See realloc. */
void *buddy_realloc(struct buddy *buddy, void *ptr, size_t requested_size, bool ignore_data);

/* Realloc-like behavior that checks for overflow. See reallocarray */
void *buddy_reallocarray(struct buddy *buddy, void *ptr,
    size_t members_count, size_t member_size, bool ignore_data);

/* Use the specified buddy to free memory. See free. */
void buddy_free(struct buddy *buddy, void *ptr);

enum buddy_safe_free_status {
    BUDDY_SAFE_FREE_SUCCESS,
    BUDDY_SAFE_FREE_BUDDY_IS_NULL,
    BUDDY_SAFE_FREE_INVALID_ADDRESS,
    BUDDY_SAFE_FREE_SIZE_MISMATCH,
    BUDDY_SAFE_FREE_ALREADY_FREE,
};

/* A (safer) free with a size. Will not free unless the size fits the target span. */
enum buddy_safe_free_status buddy_safe_free(struct buddy *buddy, void *ptr, size_t requested_size);

/* Reports the allocation size. This could be bigger than the requested size,
   it's the exact size that this allocation occupies in the arena.
   Returns 0 on failure, and a non-zero value on success. */
size_t buddy_alloc_size(struct buddy *buddy, void *ptr);

/*
 * Reservation functions
 */

/* Reserve a range by marking it as allocated. Useful for dealing with physical memory. */
void buddy_reserve_range(struct buddy *buddy, void *ptr, size_t requested_size);

/* Release a reserved memory range. Unsafe, this can mess up other allocations if called with wrong parameters! */
void buddy_unsafe_release_range(struct buddy *buddy, void *ptr, size_t requested_size);

/*
 * Iteration functions
 */

/*
 * Iterate through the free and allocated slots and call the provided function for each of them.
 *
 * If the provided function returns a non-NULL result the iteration stops and the result
 * is returned to called. NULL is returned upon completing iteration without stopping.
 *
 * The iteration order is implementation-defined and may change between versions.
 */
void *buddy_walk(struct buddy *buddy, void *(fp)(void *ctx, void *addr, size_t slot_size, size_t allocated), void *ctx);

/*
 * Miscellaneous functions
 */

/*
 * Calculates the fragmentation in the allocator in a 0 - 255 range.
 * NOTE: if you are using a non-power-of-two sized arena the maximum upper bound can be lower.
 */
unsigned char buddy_fragmentation(struct buddy *buddy);

#ifdef BUDDY_EXPERIMENTAL_CHANGE_TRACKING
/*
 * Enable change tracking for this allocator instance.
 *
 * This will store a header at the start of the arena that contains the function pointer (tracker) and
 * a void* (context). The tracker will be called with the context, the start of changed memory and its length.
 *
 * This function MUST be called before any allocations are performed!
 *
 * Change tracking is in effect only for allocation functions, resizing functions are excluded from it.
 *
 * This is an experimental feature designed to facilitate integration with https://github.com/spaskalev/libpvl
 *
 * The API is not (yet) part of the allocator contract and its semantic versioning!
 */
void buddy_enable_change_tracking(struct buddy* buddy, void* context, void (*tracker) (void*, unsigned char*, size_t));
#endif

#ifdef __cplusplus
#ifndef BUDDY_CPP_MANGLED
}
#endif
#endif

#endif /* BUDDY_ALLOC_H */

#ifdef BUDDY_ALLOC_IMPLEMENTATION
#undef BUDDY_ALLOC_IMPLEMENTATION

#ifdef __cplusplus
#ifndef BUDDY_CPP_MANGLED
extern "C" {
#endif
#endif

#ifndef BUDDY_ALLOC_ALIGN
#define BUDDY_ALLOC_ALIGN (sizeof(size_t) * CHAR_BIT)
#endif

#ifdef __cplusplus
#ifndef BUDDY_ALIGNOF
#define BUDDY_ALIGNOF(x) alignof(x)
#endif

#else /* not __cplusplus */

#ifndef BUDDY_ALIGNOF
#ifndef _MSC_VER
#define BUDDY_ALIGNOF(x) __alignof__(x)
#else
#define BUDDY_ALIGNOF(x) _Alignof(x)
#endif
#endif

#endif /* __cplusplus */

/* ssize_t is a POSIX extension */
#if defined(_MSC_VER) && !defined(_SSIZE_T_DEFINED)
#if _WIN64
typedef signed long long ssize_t;
#else
typedef signed long ssize_t;
#endif
#define _SSIZE_T_DEFINED
#endif

/* Support compiling with Pelles C */
#if defined(__POCC__) && defined(__POCC_TARGET__)
#if __POCC_TARGET__ == 3
typedef signed long long ssize_t;
#elif __POCC_TARGET__ == 1
typedef signed long ssize_t;
#else
#error Uknown POCC target
#endif
#endif

#ifndef BUDDY_PRINTF
#define BUDDY_PRINTF printf
#endif

/*
 * Debug functions
 */

/* Implementation defined */
void buddy_debug(struct buddy *buddy);

struct buddy_change_tracker {
    void* context;
    void (*tracker) (void*, unsigned char*, size_t);
};

struct buddy_tree;

struct buddy_tree_pos {
    size_t index;
    size_t depth;
};

#ifdef __cplusplus
#define INVALID_POS buddy_tree_pos{ 0, 0 }
#else
#define INVALID_POS ((struct buddy_tree_pos){ 0, 0 })
#endif

struct buddy_tree_interval {
    struct buddy_tree_pos from;
    struct buddy_tree_pos to;
};

struct buddy_tree_walk_state {
    struct buddy_tree_pos starting_pos;
    struct buddy_tree_pos current_pos;
    unsigned int going_up;
    unsigned int walk_done;
};

/*
 * Initialization functions
 */

/* Returns the size of a buddy allocation tree of the desired order*/
static size_t buddy_tree_sizeof(uint8_t order);

/* Initializes a buddy allocation tree at the specified location */
static struct buddy_tree *buddy_tree_init(unsigned char *at, uint8_t order);

/* Indicates whether this is a valid position for the tree */
static bool buddy_tree_valid(struct buddy_tree *t, struct buddy_tree_pos pos);

/* Returns the order of the specified buddy allocation tree */
static uint8_t buddy_tree_order(struct buddy_tree *t);

/*
 * Resize the tree to the new order. When downsizing the left subtree is picked.
 * Caller must ensure enough space for the new order.
 */
static void buddy_tree_resize(struct buddy_tree *t, uint8_t desired_order);

#ifdef BUDDY_EXPERIMENTAL_CHANGE_TRACKING
/* Enable change tracking state for this tree. */
static void buddy_tree_enable_change_tracking(struct buddy_tree *t);
#endif /* BUDDY_EXPERIMENTAL_CHANGE_TRACKING */

/*
 * Navigation functions
 */

/* Returns a position at the root of a buddy allocation tree */
static struct buddy_tree_pos buddy_tree_root(void);

/* Returns the leftmost child node */
static struct buddy_tree_pos buddy_tree_leftmost_child(struct buddy_tree *t);

/* Returns the tree depth of the indicated position */
static inline size_t buddy_tree_depth(struct buddy_tree_pos pos);

/* Returns the left child node position. Does not check if that is a valid position */
static inline struct buddy_tree_pos buddy_tree_left_child(struct buddy_tree_pos pos);

/* Returns the right child node position. Does not check if that is a valid position */
static inline struct buddy_tree_pos buddy_tree_right_child(struct buddy_tree_pos pos);

/* Returns the current sibling node position. Does not check if that is a valid position */
static inline struct buddy_tree_pos buddy_tree_sibling(struct buddy_tree_pos pos);

/* Returns the parent node position or an invalid position if there is no parent node */
static inline struct buddy_tree_pos buddy_tree_parent(struct buddy_tree_pos pos);

/* Returns the right adjacent node position or an invalid position if there is no right adjacent node */
static struct buddy_tree_pos buddy_tree_right_adjacent(struct buddy_tree_pos pos);

/* Returns the at-depth index of the indicated position */
static size_t buddy_tree_index(struct buddy_tree_pos pos);

/* Return the interval of the deepest positions spanning the indicated position */
static struct buddy_tree_interval to_buddy_tree_interval(struct buddy_tree *t, struct buddy_tree_pos pos);

/* Checks if one interval contains another */
static bool buddy_tree_interval_contains(struct buddy_tree_interval outer,
    struct buddy_tree_interval inner);

/* Return a walk state structure starting from the root of a tree */
static struct buddy_tree_walk_state buddy_tree_walk_state_root(void);

/* Walk the tree, keeping track in the provided state structure */
static unsigned int buddy_tree_walk(struct buddy_tree *t, struct buddy_tree_walk_state *state);


/*
 * Allocation functions
 */

/* Returns the free capacity at or underneath the indicated position */
static size_t buddy_tree_status(struct buddy_tree *t, struct buddy_tree_pos pos);

/* Marks the indicated position as allocated and propagates the change */
static void buddy_tree_mark(struct buddy_tree *t, struct buddy_tree_pos pos);

enum buddy_tree_release_status {
    BUDDY_TREE_RELEASE_SUCCESS,
    BUDDY_TREE_RELEASE_FAIL_PARTIALLY_USED,
};

/* Marks the indicated position as free and propagates the change */
static enum buddy_tree_release_status buddy_tree_release(struct buddy_tree *t, struct buddy_tree_pos pos);

/* Returns a free position at the specified depth or an invalid position */
static struct buddy_tree_pos buddy_tree_find_free(struct buddy_tree *t, uint8_t depth);

/* Tests if the indicated position is available for allocation */
static bool buddy_tree_is_free(struct buddy_tree *t, struct buddy_tree_pos pos);

/* Tests if the tree can be shrank in half */
static bool buddy_tree_can_shrink(struct buddy_tree *t);

/*
 * Integration functions
 */

#ifdef BUDDY_EXPERIMENTAL_CHANGE_TRACKING
/* Get a pointer to the parent buddy struct */
static struct buddy* buddy_tree_buddy(struct buddy_tree* t);
#endif /* BUDDY_EXPERIMENTAL_CHANGE_TRACKING */

/*
 * Debug functions
 */

/* Implementation defined */
static void buddy_tree_debug(struct buddy_tree *t, struct buddy_tree_pos pos, size_t start_size);

/* Implementation defined */
unsigned int buddy_tree_check_invariant(struct buddy_tree *t, struct buddy_tree_pos pos);

/* Report fragmentation in a 0 - 255 range */
static unsigned char buddy_tree_fragmentation(struct buddy_tree *t);

/*
 * A char-backed bitset implementation
 */

static size_t bitset_sizeof(size_t elements);

struct bitset_range {
    size_t from_bucket;
    size_t to_bucket;

    uint8_t from_index;
    uint8_t to_index;
};

static inline struct bitset_range to_bitset_range(size_t from_pos, size_t to_pos);

static void bitset_set_range(unsigned char *bitset, struct bitset_range range);

static void bitset_clear_range(unsigned char *bitset, struct bitset_range range);

static size_t bitset_count_range(unsigned char *bitset, struct bitset_range range);

static inline void bitset_set(unsigned char *bitset, size_t pos);

static inline void bitset_clear(unsigned char *bitset, size_t pos);

static inline bool bitset_test(const unsigned char *bitset, size_t pos);

static void bitset_shift_left(unsigned char *bitset, size_t from_pos, size_t to_pos, size_t by);

static void bitset_shift_right(unsigned char *bitset, size_t from_pos, size_t to_pos, size_t by);

/*
 * Debug functions
 */

/* Implementation defined */
void bitset_debug(unsigned char *bitset, size_t length);

/*
 * Bits
 */

/* Returns the number of set bits in the given byte */
static unsigned int popcount_byte(unsigned char b);

/* Count the number of trailing zeroes in the given value */
static unsigned char count_trailing_zeroes(size_t val);

/* Returns the index of the highest bit set (1-based) */
static size_t highest_bit_position(size_t value);

/* Returns the nearest larger or equal power of two */
static inline size_t ceiling_power_of_two(size_t value);

/* Return two to the power of order */
static inline size_t two_to_the_power_of(size_t order);

/*
 * Math
 */

/* Calculates the integer square root of an integer */
static inline size_t integer_square_root(size_t f);

/*
 Implementation
*/

const unsigned int BUDDY_RELATIVE_MODE = 1;

/*
 * A binary buddy memory allocator
 */

struct buddy {
    size_t memory_size;
    size_t alignment;
    union {
        unsigned char *main;
        ptrdiff_t main_offset;
    } arena;
    size_t buddy_flags;
};

struct buddy_embed_check {
    unsigned int can_fit;
    size_t offset;
    size_t buddy_size;
};

static unsigned int is_valid_alignment(size_t alignment);
static size_t buddy_tree_order_for_memory(size_t memory_size, size_t alignment);
static size_t depth_for_size(struct buddy *buddy, size_t requested_size);
static inline size_t size_for_depth(struct buddy *buddy, size_t depth);
static unsigned char *address_for_position(struct buddy *buddy, struct buddy_tree_pos pos);
static struct buddy_tree_pos position_for_address(struct buddy *buddy, const unsigned char *addr);
static unsigned char *buddy_main(struct buddy *buddy);
static unsigned int buddy_relative_mode(struct buddy *buddy);
static struct buddy_tree *buddy_tree_for(struct buddy *buddy);
static size_t buddy_effective_memory_size(struct buddy *buddy);
static size_t buddy_virtual_slots(struct buddy *buddy);
static void buddy_toggle_virtual_slots(struct buddy *buddy, unsigned int state);
static void buddy_toggle_range_reservation(struct buddy *buddy, void *ptr, size_t requested_size, unsigned int state);
static struct buddy *buddy_resize_standard(struct buddy *buddy, size_t new_memory_size);
static struct buddy *buddy_resize_embedded(struct buddy *buddy, size_t new_memory_size);
static bool buddy_is_free(struct buddy *buddy, size_t from);
static struct buddy_embed_check buddy_embed_offset(size_t memory_size, size_t alignment);
static struct buddy_tree_pos deepest_position_for_offset(struct buddy *buddy, size_t offset);

size_t buddy_sizeof(size_t memory_size) {
    return buddy_sizeof_alignment(memory_size, BUDDY_ALLOC_ALIGN);
}

size_t buddy_sizeof_alignment(size_t memory_size, size_t alignment) {
    size_t buddy_tree_order;

    if (!is_valid_alignment(alignment)) {
        return 0; /* invalid */
    }
    if (memory_size < alignment) {
        return 0; /* invalid */
    }
    buddy_tree_order = buddy_tree_order_for_memory(memory_size, alignment);
    return sizeof(struct buddy) + buddy_tree_sizeof((uint8_t)buddy_tree_order);
}

struct buddy *buddy_init(unsigned char *at, unsigned char *main, size_t memory_size) {
    return buddy_init_alignment(at, main, memory_size, BUDDY_ALLOC_ALIGN);
}

struct buddy *buddy_init_alignment(unsigned char *at, unsigned char *main, size_t memory_size,
        size_t alignment) {
    size_t at_alignment, main_alignment, buddy_size, buddy_tree_order;
    struct buddy *buddy;

    if (at == NULL) {
        return NULL;
    }
    if (main == NULL) {
        return NULL;
    }
    if (at == main) {
        return NULL;
    }
    if (!is_valid_alignment(alignment)) {
        return NULL; /* invalid */
    }
    at_alignment = ((uintptr_t) at) % BUDDY_ALIGNOF(struct buddy);
    if (at_alignment != 0) {
        return NULL;
    }
    main_alignment = ((uintptr_t) main) % BUDDY_ALIGNOF(size_t);
    if (main_alignment != 0) {
        return NULL;
    }
    /* Trim down memory to alignment */
    if (memory_size % alignment) {
        memory_size -= (memory_size % alignment);
    }
    buddy_size = buddy_sizeof_alignment(memory_size, alignment);
    if (buddy_size == 0) {
        return NULL;
    }
    buddy_tree_order = buddy_tree_order_for_memory(memory_size, alignment);

    /* TODO check for overlap between buddy metadata and main block */
    buddy = (struct buddy *) at;
    buddy->arena.main = main;
    buddy->memory_size = memory_size;
    buddy->buddy_flags = 0;
    buddy->alignment = alignment;
    buddy_tree_init((unsigned char *)buddy + sizeof(*buddy), (uint8_t) buddy_tree_order);
    buddy_toggle_virtual_slots(buddy, 1);
    return buddy;
}

struct buddy *buddy_embed(unsigned char *main, size_t memory_size) {
    return buddy_embed_alignment(main, memory_size, BUDDY_ALLOC_ALIGN);
}

struct buddy *buddy_get_embed_at(unsigned char *main, size_t memory_size) {
    return buddy_get_embed_at_alignment(main, memory_size, BUDDY_ALLOC_ALIGN);
}

struct buddy *buddy_embed_alignment(unsigned char *main, size_t memory_size, size_t alignment) {
    struct buddy_embed_check check_result;
    struct buddy *buddy;

    if (! main) {
        return NULL;
    }
    if (!is_valid_alignment(alignment)) {
        return NULL; /* invalid */
    }
    check_result = buddy_embed_offset(memory_size, alignment);
    if (! check_result.can_fit) {
        return NULL;
    }

    buddy = buddy_init_alignment(main+check_result.offset, main, check_result.offset, alignment);
    if (! buddy) { /* regular initialization failed */
        return NULL;
    }

    buddy->buddy_flags |= BUDDY_RELATIVE_MODE;
    buddy->arena.main_offset = (unsigned char *)buddy - main;
    return buddy;
}

struct buddy *buddy_get_embed_at_alignment(unsigned char *main, size_t memory_size, size_t alignment) {
    struct buddy_embed_check check_result = buddy_embed_offset(memory_size, alignment);
    if (!check_result.can_fit) {
        return NULL;
    }
    return (struct buddy *)(main + check_result.offset);
}

struct buddy *buddy_resize(struct buddy *buddy, size_t new_memory_size) {
    if (new_memory_size == buddy->memory_size) {
        return buddy;
    }

    if (buddy_relative_mode(buddy)) {
        return buddy_resize_embedded(buddy, new_memory_size);
    } else {
        return buddy_resize_standard(buddy, new_memory_size);
    }
}

static struct buddy *buddy_resize_standard(struct buddy *buddy, size_t new_memory_size) {
    size_t new_buddy_tree_order;

    /* Trim down memory to alignment */
    if (new_memory_size % buddy->alignment) {
        new_memory_size -= (new_memory_size % buddy->alignment);
    }

    /* Account for tree use */
    if (!buddy_is_free(buddy, new_memory_size)) {
        return NULL;
    }

    /* Release the virtual slots */
    buddy_toggle_virtual_slots(buddy, 0);

    /* Calculate new tree order and resize it */
    new_buddy_tree_order = buddy_tree_order_for_memory(new_memory_size, buddy->alignment);
    buddy_tree_resize(buddy_tree_for(buddy), (uint8_t) new_buddy_tree_order);

    /* Store the new memory size and reconstruct any virtual slots */
    buddy->memory_size = new_memory_size;
    buddy_toggle_virtual_slots(buddy, 1);

    /* Resize successful */
    return buddy;
}

static struct buddy *buddy_resize_embedded(struct buddy *buddy, size_t new_memory_size) {
    struct buddy_embed_check check_result;
    unsigned char *main, *buddy_destination;
    struct buddy *resized, *relocated;

    /* Ensure that the embedded allocator can fit */
    check_result = buddy_embed_offset(new_memory_size, buddy->alignment);
    if (! check_result.can_fit) {
        return NULL;
    }

    /* Resize the allocator in the normal way */
    resized = buddy_resize_standard(buddy, check_result.offset);
    if (! resized) {
        return NULL;
    }

    /* Get the absolute main address. The relative will be invalid after relocation. */
    main = buddy_main(buddy);

    /* Relocate the allocator */
    buddy_destination = buddy_main(buddy) + check_result.offset;
    memmove(buddy_destination, resized, check_result.buddy_size);

    /* Update the main offset in the allocator */
    relocated = (struct buddy *) buddy_destination;
    relocated->arena.main_offset = buddy_destination - main;

    return relocated;
}

bool buddy_can_shrink(struct buddy *buddy) {
    if (buddy == NULL) {
        return false;
    }
    return buddy_is_free(buddy, buddy->memory_size / 2);
}

bool buddy_is_empty(struct buddy *buddy) {
    if (buddy == NULL) {
        return false;
    }
    return buddy_is_free(buddy, 0);
}

bool buddy_is_full(struct buddy *buddy) {
    struct buddy_tree *tree;
    struct buddy_tree_pos pos;

    if (buddy == NULL) {
        return false;
    }
    tree = buddy_tree_for(buddy);
    pos = buddy_tree_root();
    return buddy_tree_status(tree, pos) == buddy_tree_order(tree);
}

size_t buddy_arena_size(struct buddy *buddy) {
    if (buddy == NULL) {
        return 0;
    }
    return buddy->memory_size;
}

size_t buddy_arena_free_size(struct buddy *buddy) {
    size_t result = 0;
    struct buddy_tree *tree = buddy_tree_for(buddy);
    size_t tree_order = buddy_tree_order(tree);

    struct buddy_tree_walk_state state = buddy_tree_walk_state_root();
    do {
        size_t pos_status = buddy_tree_status(tree, state.current_pos);
        if (pos_status == (tree_order - state.current_pos.depth + 1)) { /* Fully-allocated */
            state.going_up = 1;
        } else if (pos_status == 0) { /* Free */
            state.going_up = 1;
            result += size_for_depth(buddy, state.current_pos.depth);
        } else { /* Partial */
            continue;
        }
    } while (buddy_tree_walk(tree, &state));
    return result;
}

static unsigned int is_valid_alignment(size_t alignment) {
    return ceiling_power_of_two(alignment) == alignment;
}

static size_t buddy_tree_order_for_memory(size_t memory_size, size_t alignment) {
    // cppcheck-suppress zerodiv
    size_t blocks = memory_size / alignment;
    return highest_bit_position(ceiling_power_of_two(blocks));
}

void *buddy_malloc(struct buddy *buddy, size_t requested_size) {
    size_t target_depth;
    struct buddy_tree *tree;
    struct buddy_tree_pos pos;

    if (buddy == NULL) {
        return NULL;
    }
    if (requested_size == 0) {
        /*
         * Batshit crazy code exists that calls malloc(0) and expects
         * a result that can be safely passed to free().
         * And even though this allocator will safely handle a free(NULL)
         * the particular batshit code will expect a non-NULL malloc(0) result!
         *
         * See also https://wiki.sei.cmu.edu/confluence/display/c/MEM04-C.+Beware+of+zero-length+allocations
         */
        requested_size = 1;
    }
    if (requested_size > buddy->memory_size) {
        return NULL;
    }

    target_depth = depth_for_size(buddy, requested_size);
    tree = buddy_tree_for(buddy);
    pos = buddy_tree_find_free(tree, (uint8_t) target_depth);

    if (! buddy_tree_valid(tree, pos)) {
        return NULL; /* no slot found */
    }

    /* Allocate the slot */
    buddy_tree_mark(tree, pos);

    /* Find and return the actual memory address */
    return address_for_position(buddy, pos);
}

void *buddy_calloc(struct buddy *buddy, size_t members_count, size_t member_size) {
    size_t total_size;
    void *result;

    if (members_count == 0 || member_size == 0) {
        /* See the gleeful remark in malloc */
        members_count = 1;
        member_size = 1;
    }
    /* Check for overflow */
    if (((members_count * member_size)/members_count) != member_size) {
        return NULL;
    }
    total_size = members_count * member_size;
    result = buddy_malloc(buddy, total_size);
    if (result) {
        memset(result, 0, total_size);
    }
    return result;
}

void *buddy_realloc(struct buddy *buddy, void *ptr, size_t requested_size, bool ignore_data) {
    struct buddy_tree *tree;
    struct buddy_tree_pos origin, new_pos;
    size_t current_depth, target_depth;
    void *source, *destination;

    /*
     * realloc is a joke:
     * - NULL ptr degrades into malloc
     * - Zero size degrades into free
     * - Same size as previous malloc/calloc/realloc is a no-op or a rellocation
     * - Smaller size than previous *alloc decrease the allocated size with an optional rellocation
     * - If the new allocation cannot be satisfied NULL is returned BUT the slot is preserved
     * - Larger size than previous *alloc increase tha allocated size with an optional rellocation
     */
    if (ptr == NULL) {
        return buddy_malloc(buddy, requested_size);
    }
    if (requested_size == 0) {
        buddy_free(buddy, ptr);
        return NULL;
    }
    if (requested_size > buddy->memory_size) {
        return NULL;
    }

    /* Find the position tracking this address */
    tree = buddy_tree_for(buddy);
    origin = position_for_address(buddy, (unsigned char *) ptr);
    if (! buddy_tree_valid(tree, origin)) {
        return NULL;
    }
    current_depth = buddy_tree_depth(origin);
    target_depth = depth_for_size(buddy, requested_size);

    /* Release the position and perform a search */
    buddy_tree_release(tree, origin);
    new_pos = buddy_tree_find_free(tree, (uint8_t) target_depth);

    if (! buddy_tree_valid(tree, new_pos)) {
        /* allocation failure, restore mark and return null */
        buddy_tree_mark(tree, origin);
        return NULL;
    }

    if (origin.index == new_pos.index) {
        /* Allocated to the same slot, restore mark and return null */
        buddy_tree_mark(tree, origin);
        return ptr;
    }

    destination = address_for_position(buddy, new_pos);

    if (! ignore_data) {
        /* Copy the content */
        source = address_for_position(buddy, origin);
        memmove(destination, source, size_for_depth(buddy,
            current_depth > target_depth ? current_depth : target_depth));
    }

    /* Allocate and return */
    buddy_tree_mark(tree, new_pos);
    return destination;
}

void *buddy_reallocarray(struct buddy *buddy, void *ptr,
        size_t members_count, size_t member_size, bool ignore_data) {
    if (members_count == 0 || member_size == 0) {
        return buddy_realloc(buddy, ptr, 0, ignore_data);
    }
    /* Check for overflow */
    if ((members_count * member_size)/members_count != member_size) {
        return NULL;
    }
    return buddy_realloc(buddy, ptr, members_count * member_size, ignore_data);
}

void buddy_free(struct buddy *buddy, void *ptr) {
    unsigned char *dst, *main;
    struct buddy_tree *tree;
    struct buddy_tree_pos pos;

    if (buddy == NULL) {
        return;
    }
    if (ptr == NULL) {
        return;
    }
    dst = (unsigned char *)ptr;
    main = buddy_main(buddy);
    if ((dst < main) || (dst >= (main + buddy->memory_size))) {
        return;
    }

    /* Find the position tracking this address */
    tree = buddy_tree_for(buddy);
    pos = position_for_address(buddy, dst);

    if (! buddy_tree_valid(tree, pos)) {
        return;
    }

    /* Release the position */
    buddy_tree_release(tree, pos);
}

enum buddy_safe_free_status buddy_safe_free(struct buddy* buddy, void* ptr, size_t requested_size) {
    unsigned char* dst, * main;
    struct buddy_tree* tree;
    struct buddy_tree_pos pos;
    size_t allocated_size_for_depth;
    enum buddy_tree_release_status status;

    if (buddy == NULL) {
        return BUDDY_SAFE_FREE_BUDDY_IS_NULL;
    }
    if (ptr == NULL) {
        return BUDDY_SAFE_FREE_INVALID_ADDRESS;
    }
    dst = (unsigned char*)ptr;
    main = buddy_main(buddy);
    if ((dst < main) || (dst >= (main + buddy->memory_size))) {
        return BUDDY_SAFE_FREE_INVALID_ADDRESS;
    }

    /* Find an allocated position tracking this address */
    tree = buddy_tree_for(buddy);
    pos = position_for_address(buddy, dst);

    if (!buddy_tree_valid(tree, pos)) {
        return BUDDY_SAFE_FREE_INVALID_ADDRESS;
    }

    allocated_size_for_depth = size_for_depth(buddy, pos.depth);
    if (requested_size < buddy->alignment) {
        requested_size = buddy->alignment;
    }
    if (requested_size > allocated_size_for_depth) {
        return BUDDY_SAFE_FREE_SIZE_MISMATCH;
    }
    if (requested_size <= (allocated_size_for_depth / 2)) {
        return BUDDY_SAFE_FREE_SIZE_MISMATCH;
    }

    /* Release the position */
    status = buddy_tree_release(tree, pos);

    switch (status) {
    case BUDDY_TREE_RELEASE_FAIL_PARTIALLY_USED:
        return BUDDY_SAFE_FREE_INVALID_ADDRESS;
    case BUDDY_TREE_RELEASE_SUCCESS:
        break;
    }

    return BUDDY_SAFE_FREE_SUCCESS;
}

size_t buddy_alloc_size(struct buddy *buddy, void *ptr) {
    unsigned char* dst, * main;
    struct buddy_tree* tree;
    struct buddy_tree_pos pos;

    if (buddy == NULL) {
        return 0;
    }
    if (ptr == NULL) {
        return 0;
    }
    dst = (unsigned char*)ptr;
    main = buddy_main(buddy);
    if ((dst < main) || (dst >= (main + buddy->memory_size))) {
        return 0;
    }

    /* Find an allocated position tracking this address */
    tree = buddy_tree_for(buddy);
    pos = position_for_address(buddy, dst);

    if (!buddy_tree_valid(tree, pos)) {
        return 0;
    }

    return size_for_depth(buddy, pos.depth);
}

void buddy_reserve_range(struct buddy *buddy, void *ptr, size_t requested_size) {
    buddy_toggle_range_reservation(buddy, ptr, requested_size, 1);
}

void buddy_unsafe_release_range(struct buddy *buddy, void *ptr, size_t requested_size) {
    buddy_toggle_range_reservation(buddy, ptr, requested_size, 0);
}

void *buddy_walk(struct buddy *buddy,
        void *(fp)(void *ctx, void *addr, size_t slot_size, size_t allocated),
        void *ctx) {
    unsigned char *main;
    size_t effective_memory_size, tree_order, pos_status, pos_size;
    struct buddy_tree *tree;
    unsigned char *addr;
    struct buddy_tree_walk_state state;
    struct buddy_tree_pos test_pos;
    void *callback_result;

    if (buddy == NULL) {
        return NULL;
    }
    if (fp == NULL) {
        return NULL;
    }
    main = buddy_main(buddy);
    effective_memory_size = buddy_effective_memory_size(buddy);
    tree = buddy_tree_for(buddy);
    tree_order = buddy_tree_order(tree);

    state = buddy_tree_walk_state_root();
    do {
        pos_status = buddy_tree_status(tree, state.current_pos);
        if (pos_status != (tree_order - state.current_pos.depth + 1)) { /* Partially-allocated */
            continue;
        }

        /*
         * The tree doesn't make a distinction of a fully-allocated node
         *  due to a single allocation and a fully-allocated due to maxed out
         *  child allocations - we need to check the children.
         * A child-allocated node will have both children set to their maximum
         *  but it is sufficient to check just one for non-zero.
         */
        test_pos = buddy_tree_left_child(state.current_pos);
        if (buddy_tree_valid(tree, test_pos) && buddy_tree_status(tree, test_pos)) {
            continue;
        }

        /* Current node is free or allocated, process */
        pos_size = effective_memory_size >> (state.current_pos.depth - 1u);
        addr = address_for_position(buddy, state.current_pos);
        if (((size_t)(addr - main) + pos_size) > buddy->memory_size) {
            /*
             * Do not process virtual slots
             * As virtual slots are on the right side of the tree
             *  if we see a one with the current iteration order this
             *  means that all subsequent slots will be virtual,
             *  hence we can return early.
             */
            return NULL;
        }
        callback_result = (fp)(ctx, addr, pos_size, pos_status > 0);
        if (callback_result != NULL) {
            return callback_result;
        }
        state.going_up = 1;

    } while (buddy_tree_walk(tree, &state));
    return NULL;
}

unsigned char buddy_fragmentation(struct buddy *buddy) {
    if (buddy == NULL) {
        return 0;
    }
    return buddy_tree_fragmentation(buddy_tree_for(buddy));
}

#ifdef BUDDY_EXPERIMENTAL_CHANGE_TRACKING
void buddy_enable_change_tracking(struct buddy* buddy, void* context, void (*tracker) (void*, unsigned char*, size_t)) {
    struct buddy_tree *t = buddy_tree_for(buddy);
    struct buddy_change_tracker *header = (struct buddy_change_tracker *) buddy_main(buddy);

    /* Allocate memory for the change tracking header */
    buddy_reserve_range(buddy, buddy_main(buddy), sizeof(struct buddy_change_tracker));

    /* Fill in the change tracking header */
    header->context = context;
    header->tracker = tracker;

    /* Indicate that the tree should perform change tracking */
    buddy_tree_enable_change_tracking(t);
}
#endif


static size_t depth_for_size(struct buddy *buddy, size_t requested_size) {
    size_t depth, effective_memory_size, p2_of_requested_size;
    if (requested_size < buddy->alignment) {
        requested_size = buddy->alignment;
    }
    depth = 1;
    effective_memory_size = buddy_effective_memory_size(buddy);

    p2_of_requested_size = ceiling_power_of_two(requested_size);
    depth = (size_t)(count_trailing_zeroes(effective_memory_size) + 1
        - count_trailing_zeroes(p2_of_requested_size));
    return depth;
}

static inline size_t size_for_depth(struct buddy *buddy, size_t depth) {
    return ceiling_power_of_two(buddy->memory_size) >> (depth-1);
}

static struct buddy_tree *buddy_tree_for(struct buddy *buddy) {
    return (struct buddy_tree*) ((unsigned char *)buddy + sizeof(*buddy));
}

static size_t buddy_effective_memory_size(struct buddy *buddy) {
    return ceiling_power_of_two(buddy->memory_size);
}

static size_t buddy_virtual_slots(struct buddy *buddy) {
    size_t memory_size = buddy->memory_size;
    size_t effective_memory_size = buddy_effective_memory_size(buddy);
    if (effective_memory_size == memory_size) {
        return 0;
    }
    return (effective_memory_size - memory_size) / buddy->alignment;
}

static unsigned char *address_for_position(struct buddy *buddy, struct buddy_tree_pos pos) {
    size_t block_size = size_for_depth(buddy, buddy_tree_depth(pos));
    size_t addr = block_size * buddy_tree_index(pos);
    return buddy_main(buddy) + addr;
}

static struct buddy_tree_pos deepest_position_for_offset(struct buddy *buddy, size_t offset) {
    size_t index = offset / buddy->alignment;
    struct buddy_tree_pos pos = buddy_tree_leftmost_child(buddy_tree_for(buddy));
    pos.index += index;
    return pos;
}

static struct buddy_tree_pos position_for_address(struct buddy *buddy, const unsigned char *addr) {
    unsigned char *main;
    struct buddy_tree *tree;
    struct buddy_tree_pos pos;
    size_t offset;

    main = buddy_main(buddy);
    offset = (size_t) (addr - main);

    if (offset % buddy->alignment) {
        return INVALID_POS; /* invalid alignment */
    }

    tree = buddy_tree_for(buddy);
    pos = deepest_position_for_offset(buddy, offset);

    /* Find the actual allocated position tracking this address */
    while (!buddy_tree_status(tree, pos)) {
        pos = buddy_tree_parent(pos);

        if (!buddy_tree_valid(tree, pos)) {
            return INVALID_POS;
        }
    }

    if (address_for_position(buddy, pos) != addr) {
        return INVALID_POS; /* invalid alignment */
    }

    return pos;
}

static unsigned char *buddy_main(struct buddy *buddy) {
    if (buddy_relative_mode(buddy)) {
        return (unsigned char *)buddy - buddy->arena.main_offset;
    }
    return buddy->arena.main;
}

static unsigned int buddy_relative_mode(struct buddy *buddy) {
    return (unsigned int)buddy->buddy_flags & BUDDY_RELATIVE_MODE;
}

static void buddy_toggle_virtual_slots(struct buddy *buddy, unsigned int state) {
    size_t delta, memory_size, effective_memory_size;
    struct buddy_tree *tree;
    struct buddy_tree_pos pos;

    memory_size = buddy->memory_size;
    /* Mask/unmask the virtual space if memory is not a power of two */
    effective_memory_size = buddy_effective_memory_size(buddy);
    if (effective_memory_size == memory_size) {
        return;
    }

    /* Get the area that we need to mask and pad it to alignment */
    /* Node memory size is already aligned to buddy->alignment */
    delta = effective_memory_size - memory_size;

    tree = buddy_tree_for(buddy);
    pos = buddy_tree_right_child(buddy_tree_root());
    while (delta) {
        size_t current_pos_size = size_for_depth(buddy, buddy_tree_depth(pos));
        if (delta == current_pos_size) {
            /* toggle current pos */
            if (state) {
                buddy_tree_mark(tree, pos);
            }
            else {
                buddy_tree_release(tree, pos);
            }
            break;
        }
        if (delta <= (current_pos_size / 2)) {
            /* re-run for right child */
            pos = buddy_tree_right_child(pos);
            continue;
        } else {
            /* toggle right child */
            if (state) {
                buddy_tree_mark(tree, buddy_tree_right_child(pos));
            }
            else {
                buddy_tree_release(tree, buddy_tree_right_child(pos));
            }
            /* reduce delta */
            delta -= current_pos_size / 2;
            /* re-run for left child */
            pos = buddy_tree_left_child(pos);
            continue;
        }
    }
}

static void buddy_toggle_range_reservation(struct buddy *buddy, void *ptr, size_t requested_size, unsigned int state) {
    unsigned char *dst, *main;
    struct buddy_tree *tree;
    size_t offset;
    struct buddy_tree_pos pos;

    if (buddy == NULL) {
        return;
    }
    if (ptr == NULL) {
        return;
    }
    if (requested_size == 0) {
        return;
    }
    dst = (unsigned char *)ptr;
    main = buddy_main(buddy);
    if ((dst < main) || ((dst + requested_size) > (main + buddy->memory_size))) {
        return;
    }

    /* Find the deepest position tracking this address */
    tree = buddy_tree_for(buddy);
    offset = (size_t) (dst - main);
    pos = deepest_position_for_offset(buddy, offset);

    /* Advance one position at a time and process */
    while (requested_size) {
        if (state) {
            buddy_tree_mark(tree, pos);
        }
        else {
            buddy_tree_release(tree, pos);
        }
        requested_size = (requested_size < buddy->alignment) ? 0 : (requested_size - buddy->alignment);
        pos.index++;
    }

    return;
}

/* Internal function that checks if there are any allocations
 after the indicated relative memory index. Used to check if
 the arena can be downsized.
 The from argument is already adjusted for alignment by caller */
static bool buddy_is_free(struct buddy *buddy, size_t from) {
    struct buddy_tree *tree;
    struct buddy_tree_interval query_range;
    struct buddy_tree_pos pos;
    size_t effective_memory_size, virtual_slots, to;

    effective_memory_size = buddy_effective_memory_size(buddy);
    virtual_slots = buddy_virtual_slots(buddy);
    to = effective_memory_size -
        ((virtual_slots ? (virtual_slots + 1) : 1) * buddy->alignment);

    tree = buddy_tree_for(buddy);

    query_range.from = deepest_position_for_offset(buddy, from);
    query_range.to = deepest_position_for_offset(buddy, to);

    pos = deepest_position_for_offset(buddy, from);
    while(buddy_tree_valid(tree, pos) && (pos.index < query_range.to.index)) {
        struct buddy_tree_interval current_test_range = to_buddy_tree_interval(tree, pos);
        struct buddy_tree_interval parent_test_range =
            to_buddy_tree_interval(tree, buddy_tree_parent(pos));
        while(buddy_tree_interval_contains(query_range, parent_test_range)) {
            pos = buddy_tree_parent(pos);
            current_test_range = parent_test_range;
            parent_test_range = to_buddy_tree_interval(tree, buddy_tree_parent(pos));
        }
        /* pos is now tracking an overlapping segment */
        if (! buddy_tree_is_free(tree, pos)) {
            return false;
        }
        /* Advance check */
        pos = buddy_tree_right_adjacent(current_test_range.to);
    }
    return true;
}

static struct buddy_embed_check buddy_embed_offset(size_t memory_size, size_t alignment) {
    size_t buddy_size, offset;
    struct buddy_embed_check check_result;

    memset(&check_result, 0, sizeof(check_result));
    check_result.can_fit = 1;
    buddy_size = buddy_sizeof_alignment(memory_size, alignment);
    if (buddy_size >= memory_size) {
        check_result.can_fit = 0;
    }

    offset = memory_size - buddy_size;
    if (offset % BUDDY_ALIGNOF(struct buddy) != 0) {
        buddy_size += offset % BUDDY_ALIGNOF(struct buddy);
        if (buddy_size >= memory_size) {
            check_result.can_fit = 0;
        }
        offset = memory_size - buddy_size;
    }

    if (check_result.can_fit) {
        check_result.offset = offset;
        check_result.buddy_size = buddy_size;
    }
    return check_result;
}

void buddy_debug(struct buddy *buddy) {
    BUDDY_PRINTF("buddy allocator at: %p arena at: %p\n", (void *)buddy, (void *)buddy_main(buddy));
    BUDDY_PRINTF("memory size: %zu\n", buddy->memory_size);
    BUDDY_PRINTF("mode: ");
    if (buddy_relative_mode(buddy)) {
        BUDDY_PRINTF("embedded");
    } else {
        BUDDY_PRINTF("standard");
    }
    BUDDY_PRINTF("\n");
    BUDDY_PRINTF("virtual slots: %zu\n", buddy_virtual_slots(buddy));
    BUDDY_PRINTF("allocator tree follows:\n");
    buddy_tree_debug(buddy_tree_for(buddy), buddy_tree_root(), buddy_effective_memory_size(buddy));
}

/*
 * A buddy allocation tree
 */

struct buddy_tree {
    size_t upper_pos_bound;
    size_t size_for_order_offset;
    uint8_t order;
    uint8_t flags;
    /*
     * struct padding rules mean that there are
     * 16/48 bits available until the next increment
     */
};

enum buddy_tree_flags {
    BUDDY_TREE_CHANGE_TRACKING = 1,
};

struct internal_position {
    size_t local_offset;
    size_t bitset_location;
};

static inline size_t size_for_order(uint8_t order, uint8_t to);
static inline size_t buddy_tree_index_internal(struct buddy_tree_pos pos);
static struct buddy_tree_pos buddy_tree_leftmost_child_internal(size_t tree_order);
static struct internal_position buddy_tree_internal_position_order(
    size_t tree_order, struct buddy_tree_pos pos);
static struct internal_position buddy_tree_internal_position_tree(
    struct buddy_tree *t, struct buddy_tree_pos pos);
static void buddy_tree_grow(struct buddy_tree *t, uint8_t desired_order);
static void buddy_tree_shrink(struct buddy_tree *t, uint8_t desired_order);
static void update_parent_chain(struct buddy_tree *t, struct buddy_tree_pos pos,
    struct internal_position pos_internal, size_t size_current);
static inline unsigned char *buddy_tree_bits(struct buddy_tree *t);
static void buddy_tree_populate_size_for_order(struct buddy_tree *t);
static inline size_t buddy_tree_size_for_order(struct buddy_tree *t, uint8_t to);
static void write_to_internal_position(struct buddy_tree* t, struct internal_position pos, size_t value);
static inline size_t read_from_internal_position(unsigned char *bitset, struct internal_position pos);
static inline unsigned char compare_with_internal_position(unsigned char *bitset, struct internal_position pos, size_t value);

#ifdef BUDDY_EXPERIMENTAL_CHANGE_TRACKING
static inline void buddy_tree_track_change(struct buddy_tree* t, unsigned char* addr, size_t length);
#endif /* BUDDY_EXPERIMENTAL_CHANGE_TRACKING */

static inline size_t size_for_order(uint8_t order, uint8_t to) {
    size_t result = 0;
    size_t multi = 1u;
    while (order != to) {
        result += order * multi;
        order--;
        multi *= 2;
    }
    return result;
}

static inline struct internal_position buddy_tree_internal_position_order(
        size_t tree_order, struct buddy_tree_pos pos) {
    struct internal_position p;
    size_t total_offset, local_index;

    p.local_offset = tree_order - buddy_tree_depth(pos) + 1;
    total_offset = size_for_order((uint8_t) tree_order, (uint8_t) p.local_offset);
    local_index = buddy_tree_index_internal(pos);
    p.bitset_location = total_offset + (p.local_offset * local_index);
    return p;
}

static inline struct internal_position buddy_tree_internal_position_tree(
        struct buddy_tree *t, struct buddy_tree_pos pos) {
    struct internal_position p;
    size_t total_offset, local_index;

    p.local_offset = t->order - buddy_tree_depth(pos) + 1;
    total_offset = buddy_tree_size_for_order(t, (uint8_t) p.local_offset);
    local_index = buddy_tree_index_internal(pos);
    p.bitset_location = total_offset + (p.local_offset * local_index);
    return p;
}

static size_t buddy_tree_sizeof(uint8_t order) {
    size_t tree_size, bitset_size, size_for_order_size;

    tree_size = sizeof(struct buddy_tree);
    /* Account for the bitset */
    bitset_size = bitset_sizeof(size_for_order(order, 0));
    if (bitset_size % sizeof(size_t)) {
        bitset_size += (bitset_size % sizeof(size_t));
    }
    /* Account for the size_for_order memoization */
    size_for_order_size = ((order+2) * sizeof(size_t));
    return tree_size + bitset_size + size_for_order_size;
}

static struct buddy_tree *buddy_tree_init(unsigned char *at, uint8_t order) {
    size_t size = buddy_tree_sizeof(order);
    struct buddy_tree *t = (struct buddy_tree*) at;
    memset(at, 0, size);
    t->order = order;
    t->upper_pos_bound = two_to_the_power_of(t->order);
    buddy_tree_populate_size_for_order(t);
    return t;
}

#ifdef BUDDY_EXPERIMENTAL_CHANGE_TRACKING
static void buddy_tree_enable_change_tracking(struct buddy_tree* t) {
    t->flags |= BUDDY_TREE_CHANGE_TRACKING;
}
#endif /* BUDDY_EXPERIMENTAL_CHANGE_TRACKING */

static void buddy_tree_resize(struct buddy_tree *t, uint8_t desired_order) {
    if (t->order == desired_order) {
        return;
    }
    if (t->order < desired_order) {
        buddy_tree_grow(t, desired_order);
    } else {
        buddy_tree_shrink(t, desired_order);
    }
}

static void buddy_tree_grow(struct buddy_tree *t, uint8_t desired_order) {
    struct buddy_tree_pos pos;

    while (desired_order > t->order) {
        /* Grow the tree a single order at a time */
        size_t current_order = t->order;
        struct buddy_tree_pos current_pos = buddy_tree_leftmost_child_internal(current_order);
        struct buddy_tree_pos next_pos = buddy_tree_leftmost_child_internal(current_order + 1u);
        while(current_order) {
            /* Get handles into the rows at the tracked depth */
            struct internal_position current_internal = buddy_tree_internal_position_order(
                t->order, current_pos);
            struct internal_position next_internal = buddy_tree_internal_position_order(
                t->order + 1u, next_pos);

            /* There are this many nodes at the current level */
            size_t node_count = two_to_the_power_of(current_order - 1u);

            /* Transfer the bits*/
            bitset_shift_right(buddy_tree_bits(t),
                current_internal.bitset_location /* from here */,
                current_internal.bitset_location + (current_internal.local_offset * node_count) /* up to here */,
                next_internal.bitset_location - current_internal.bitset_location /* by */);

            /* Clear right section */
            bitset_clear_range(buddy_tree_bits(t),
                to_bitset_range(next_internal.bitset_location + (next_internal.local_offset * node_count),
                                next_internal.bitset_location + (next_internal.local_offset * node_count * 2) - 1));

            /* Handle the upper level */
            current_order -= 1u;
            current_pos = buddy_tree_parent(current_pos);
            next_pos = buddy_tree_parent(next_pos);
        }
        /* Advance the order and refresh the root */
        t->order += 1u;
        t->upper_pos_bound = two_to_the_power_of(t->order);
        buddy_tree_populate_size_for_order(t);

        /* Update the root */
        pos = buddy_tree_right_child(buddy_tree_root());
        update_parent_chain(t, pos, buddy_tree_internal_position_tree(t, pos), 0);
    }
}

static void buddy_tree_shrink(struct buddy_tree *t, uint8_t desired_order) {
    size_t current_order, next_order, node_count;
    struct buddy_tree_pos left_start;
    struct internal_position current_internal, next_internal;

    while (desired_order < t->order) {
        if (!buddy_tree_can_shrink(t)) {
            return;
        }

        /* Shrink the tree a single order at a time */
        current_order = t->order;
        next_order = current_order - 1;

        left_start = buddy_tree_left_child(buddy_tree_root());
        while(buddy_tree_valid(t, left_start)) {
            /* Get handles into the rows at the tracked depth */
            current_internal = buddy_tree_internal_position_order(current_order, left_start);
            next_internal = buddy_tree_internal_position_order(next_order, buddy_tree_parent(left_start));

            /* There are this many nodes at the current level */
            node_count = two_to_the_power_of(left_start.depth - 1u);

            /* Transfer the bits*/
            bitset_shift_left(buddy_tree_bits(t),
                current_internal.bitset_location /* from here */,
                current_internal.bitset_location + (current_internal.local_offset * node_count / 2) /* up to here */,
                current_internal.bitset_location - next_internal.bitset_location/* at here */);

            /* Handle the lower level */
            left_start = buddy_tree_left_child(left_start);
        }

        /* Advance the order */
        t->order = (uint8_t) next_order;
        t->upper_pos_bound = two_to_the_power_of(t->order);
        buddy_tree_populate_size_for_order(t);
    }
}

static bool buddy_tree_valid(struct buddy_tree *t, struct buddy_tree_pos pos) {
    return pos.index && (pos.index < t->upper_pos_bound);
}

static uint8_t buddy_tree_order(struct buddy_tree *t) {
    return t->order;
}

static struct buddy_tree_pos buddy_tree_root(void) {
    struct buddy_tree_pos identity = { 1, 1 };
    return identity;
}

static struct buddy_tree_pos buddy_tree_leftmost_child(struct buddy_tree *t) {
    return buddy_tree_leftmost_child_internal(t->order);
}

static struct buddy_tree_pos buddy_tree_leftmost_child_internal(size_t tree_order) {
    struct buddy_tree_pos result;
    result.index = two_to_the_power_of(tree_order - 1u);
    result.depth = tree_order;
    return result;
}

static inline size_t buddy_tree_depth(struct buddy_tree_pos pos) {
    return pos.depth;
}

static inline struct buddy_tree_pos buddy_tree_left_child(struct buddy_tree_pos pos) {
    pos.index *= 2;
    pos.depth++;
    return pos;
}

static inline struct buddy_tree_pos buddy_tree_right_child(struct buddy_tree_pos pos) {
    pos.index *= 2;
    pos.index++;
    pos.depth++;
    return pos;
}

static inline struct buddy_tree_pos buddy_tree_sibling(struct buddy_tree_pos pos) {
    pos.index ^= 1;
    return pos;
}

static inline struct buddy_tree_pos buddy_tree_parent(struct buddy_tree_pos pos) {
    pos.index /= 2;
    pos.depth--;
    return pos;
}

static struct buddy_tree_pos buddy_tree_right_adjacent(struct buddy_tree_pos pos) {
    if (((pos.index + 1) ^ pos.index) > pos.index) {
        return INVALID_POS;
    }
    pos.index++;
    return pos;
}

static size_t buddy_tree_index(struct buddy_tree_pos pos) {
    return buddy_tree_index_internal(pos);
}

static inline size_t buddy_tree_index_internal(struct buddy_tree_pos pos) {
    /* Clear out the highest bit, this gives us the index
     * in a row of sibling nodes */
    size_t mask = two_to_the_power_of(pos.depth - 1u);
    size_t result = pos.index & ~mask;
    return result;
}

static inline unsigned char *buddy_tree_bits(struct buddy_tree *t) {
    return ((unsigned char *) t) + sizeof(*t);
}

static void buddy_tree_populate_size_for_order(struct buddy_tree *t) {
    size_t bitset_offset = bitset_sizeof(size_for_order(t->order, 0));
    if (bitset_offset % sizeof(size_t)) {
        bitset_offset += (bitset_offset % sizeof(size_t));
    }
    t->size_for_order_offset = bitset_offset / sizeof(size_t);
    t->size_for_order_offset++;
    for (size_t i = 0; i <= t->order; i++) {
        *((size_t *)(((unsigned char *) t) + sizeof(*t)) + t->size_for_order_offset + i) = size_for_order(t->order, (uint8_t) i);
    }
}

static inline size_t buddy_tree_size_for_order(struct buddy_tree *t,
         uint8_t to) {
    return *((size_t *)(((unsigned char *) t) + sizeof(*t)) + t->size_for_order_offset + to);
}

static void write_to_internal_position(struct buddy_tree* t, struct internal_position pos, size_t value) {
    unsigned char *bitset = buddy_tree_bits(t);
    struct bitset_range clear_range = to_bitset_range(pos.bitset_location, pos.bitset_location + pos.local_offset - 1);

    bitset_clear_range(bitset, clear_range);
    if (value) {
        bitset_set_range(bitset, to_bitset_range(pos.bitset_location, pos.bitset_location+value-1));
    }

#ifdef BUDDY_EXPERIMENTAL_CHANGE_TRACKING
    /* Ignore the same bucket condition - we don't care if we track one more byte here */
    buddy_tree_track_change(t, bitset, clear_range.to_bucket - clear_range.from_bucket + 1);
#endif
}

static inline size_t read_from_internal_position(unsigned char *bitset, struct internal_position pos) {
    if (! bitset_test(bitset, pos.bitset_location)) {
        return 0; /* Fast test without complete extraction */
    }
    return bitset_count_range(bitset, to_bitset_range(pos.bitset_location, pos.bitset_location+pos.local_offset-1));
}

static inline unsigned char compare_with_internal_position(unsigned char *bitset, struct internal_position pos, size_t value) {
    return bitset_test(bitset, pos.bitset_location+value-1);
}

static struct buddy_tree_interval to_buddy_tree_interval(struct buddy_tree *t, struct buddy_tree_pos pos) {
    struct buddy_tree_interval result;
    size_t depth;

    result.from = pos;
    result.to = pos;
    depth = pos.depth;
    while (depth != t->order) {
        result.from = buddy_tree_left_child(result.from);
        result.to = buddy_tree_right_child(result.to);
        depth += 1;
    }
    return result;
}

static bool buddy_tree_interval_contains(struct buddy_tree_interval outer,
        struct buddy_tree_interval inner) {
    return (inner.from.index >= outer.from.index)
        && (inner.from.index <= outer.to.index)
        && (inner.to.index >= outer.from.index)
        && (inner.to.index <= outer.to.index);
}

static struct buddy_tree_walk_state buddy_tree_walk_state_root(void) {
    struct buddy_tree_walk_state state;
    memset(&state, 0, sizeof(state));
    state.starting_pos = buddy_tree_root();
    state.current_pos = buddy_tree_root();
    return state;
}

static unsigned int buddy_tree_walk(struct buddy_tree *t, struct buddy_tree_walk_state *state) {
    do {
        if (state->going_up) {
            if (state->current_pos.index == state->starting_pos.index) {
                state->walk_done = 1;
                state->going_up = 0;
            } else if (state->current_pos.index & 1u) {
                state->current_pos = buddy_tree_parent(state->current_pos); /* Ascend */
            } else {
                state->current_pos = buddy_tree_right_adjacent(state->current_pos); /* Descend right */
                state->going_up = 0;
            }
        } else if (buddy_tree_valid(t, buddy_tree_left_child(state->current_pos))) {
            /* Descend left */
            state->current_pos = buddy_tree_left_child(state->current_pos);
        } else { /* Ascend */
            state->going_up = 1;
        }
    } while(state->going_up);
    return ! state->walk_done;
}

static size_t buddy_tree_status(struct buddy_tree *t, struct buddy_tree_pos pos) {
    struct internal_position internal = buddy_tree_internal_position_tree(t, pos);
    return read_from_internal_position(buddy_tree_bits(t), internal);
}

static void buddy_tree_mark(struct buddy_tree *t, struct buddy_tree_pos pos) {
    /* Calling mark on a used position is a bug in caller */
    struct internal_position internal = buddy_tree_internal_position_tree(t, pos);

    /* Mark the node as used */
    write_to_internal_position(t, internal, internal.local_offset);

    /* Update the tree upwards */
    update_parent_chain(t, pos, internal, internal.local_offset);
}

static enum buddy_tree_release_status buddy_tree_release(struct buddy_tree *t, struct buddy_tree_pos pos) {
    /* Calling release on an unused or a partially-used position a bug in caller */
    struct internal_position internal = buddy_tree_internal_position_tree(t, pos);

    if (read_from_internal_position(buddy_tree_bits(t), internal) != internal.local_offset) {
        return BUDDY_TREE_RELEASE_FAIL_PARTIALLY_USED;
    }

    /* Mark the node as unused */
    write_to_internal_position(t, internal, 0);

    /* Update the tree upwards */
    update_parent_chain(t, pos, internal, 0);

    return BUDDY_TREE_RELEASE_SUCCESS;
}

static void update_parent_chain(struct buddy_tree *t, struct buddy_tree_pos pos,
        struct internal_position pos_internal, size_t size_current) {
    size_t size_sibling, size_parent, target_parent;
    unsigned char *bits = buddy_tree_bits(t);

    while (pos.index != 1) {
        pos_internal.bitset_location += pos_internal.local_offset
            - (2 * pos_internal.local_offset * (pos.index & 1u));
        size_sibling = read_from_internal_position(bits, pos_internal);

        pos = buddy_tree_parent(pos);
        pos_internal = buddy_tree_internal_position_tree(t, pos);
        size_parent = read_from_internal_position(bits, pos_internal);

        target_parent = (size_current || size_sibling)
            * ((size_current <= size_sibling ? size_current : size_sibling) + 1);
        if (target_parent == size_parent) {
            return;
        }

        write_to_internal_position(t, pos_internal, target_parent);
        size_current = target_parent;
    };
}

static struct buddy_tree_pos buddy_tree_find_free(struct buddy_tree *t, uint8_t target_depth) {
    struct buddy_tree_pos current_pos, left_pos, right_pos;
    uint8_t target_status;
    size_t current_depth, right_status;
    struct internal_position left_internal, right_internal;
    unsigned char *tree_bits;

    current_pos = buddy_tree_root();
    target_status = target_depth - 1;
    current_depth = buddy_tree_depth(current_pos);
    if (buddy_tree_status(t, current_pos) > target_status) {
        return INVALID_POS; /* No position available down the tree */
    }
    tree_bits = buddy_tree_bits(t);
    while (current_depth != target_depth) {
        /* Advance criteria */
        target_status -= 1;
        current_depth += 1;

        left_pos = buddy_tree_left_child(current_pos);
        right_pos = buddy_tree_sibling(left_pos);

        left_internal = buddy_tree_internal_position_tree(t, left_pos);

        right_internal = left_internal;
        right_internal.bitset_location += right_internal.local_offset; /* advance to the right */

        if (compare_with_internal_position(tree_bits, left_internal, target_status+1)) { /* left branch is busy, pick right */
            current_pos = right_pos;
        } else if (compare_with_internal_position(tree_bits, right_internal, target_status+1)) { /* right branch is busy, pick left */
            current_pos = left_pos;
        } else {
            /* One of the child nodes must be read in order to compare it to its sibling. */
            right_status = read_from_internal_position(tree_bits, right_internal);
            if (right_status) {
                if (compare_with_internal_position(tree_bits, left_internal, right_status)) {
                    current_pos = left_pos; /* Left is equal or more busy than right, prefer left */
                } else {
                    current_pos = right_pos;
                }
            } else { /* Right is empty, prefer left */
                current_pos = left_pos;
            }
        }
    }
    return current_pos;
}

static bool buddy_tree_is_free(struct buddy_tree *t, struct buddy_tree_pos pos) {
    if (buddy_tree_status(t, pos)) {
        return false;
    }
    pos = buddy_tree_parent(pos);
    while(buddy_tree_valid(t, pos)) {
        struct internal_position internal = buddy_tree_internal_position_tree(t, pos);
        size_t value = read_from_internal_position(buddy_tree_bits(t), internal);
        if (value) {
            return value != internal.local_offset;
        }
        pos = buddy_tree_parent(pos);
    }
    return true;
}

static bool buddy_tree_can_shrink(struct buddy_tree *t) {
    struct internal_position root_internal;
    size_t root_value;

    if (buddy_tree_status(t, buddy_tree_right_child(buddy_tree_root())) != 0) {
        return false; /* Refusing to shrink with right subtree still used! */
    }
    root_internal = buddy_tree_internal_position_tree(t, buddy_tree_root());
    root_value = read_from_internal_position(buddy_tree_bits(t), root_internal);
    if (root_value == root_internal.local_offset) {
        return false; /* Refusing to shrink with the root fully-allocated! */
    }
    return true;
}

#ifdef BUDDY_EXPERIMENTAL_CHANGE_TRACKING
static struct buddy* buddy_tree_buddy(struct buddy_tree* t) {
    return (struct buddy*)(((unsigned char*)t) - sizeof(struct buddy));
}
#endif /* BUDDY_EXPERIMENTAL_CHANGE_TRACKING */

static void buddy_tree_debug(struct buddy_tree *t, struct buddy_tree_pos pos,
        size_t start_size) {
    struct buddy_tree_walk_state state = buddy_tree_walk_state_root();
    state.current_pos = pos;
    do {
        struct internal_position pos_internal = buddy_tree_internal_position_tree(t, state.current_pos);
        size_t pos_status = read_from_internal_position(buddy_tree_bits(t), pos_internal);
        size_t pos_size = start_size >> ((buddy_tree_depth(state.current_pos) - 1u) % ((sizeof(size_t) * CHAR_BIT)-1));
        BUDDY_PRINTF("%.*s",
            (int) buddy_tree_depth(state.current_pos),
            "                                                               ");
        BUDDY_PRINTF("pos index: %zu pos depth: %zu status: %zu bitset-len: %zu bitset-at: %zu",
            state.current_pos.index, state.current_pos.depth, pos_status,
            pos_internal.local_offset, pos_internal.bitset_location);
        if (pos_status == pos_internal.local_offset) {
            BUDDY_PRINTF(" size: %zu", pos_size);
        }
        BUDDY_PRINTF("\n");
    } while (buddy_tree_walk(t, &state));
}

unsigned int buddy_tree_check_invariant(struct buddy_tree *t, struct buddy_tree_pos pos) {
    unsigned int fail = 0;
    struct buddy_tree_walk_state state = buddy_tree_walk_state_root();
    state.current_pos = pos;
    do {
        struct internal_position current_internal = buddy_tree_internal_position_tree(t, pos);
        size_t current_status = read_from_internal_position(buddy_tree_bits(t), current_internal);
        size_t left_child_status = buddy_tree_status(t, buddy_tree_left_child(pos));
        size_t right_child_status = buddy_tree_status(t, buddy_tree_right_child(pos));
        unsigned int violated = 0;

        if (left_child_status || right_child_status) {
            size_t min = left_child_status <= right_child_status
                ? left_child_status : right_child_status;
            if (current_status != (min + 1)) {
                violated = 1;
            }
        } else {
            if ((current_status > 0) && (current_status < current_internal.local_offset)) {
                violated = 1;
            }
        }

        if (violated) {
            fail = 1;
            BUDDY_PRINTF("invariant violation at position [ index: %zu depth: %zu ]!\n", pos.index, pos.depth);
            BUDDY_PRINTF("current: %zu left %zu right %zu max %zu\n",
                current_status, left_child_status, right_child_status, current_internal.local_offset);
        }

    } while (buddy_tree_walk(t, &state));
    return fail;
}

/*
 * Calculate tree fragmentation based on free slots.
 * Based on https://asawicki.info/news_1757_a_metric_for_memory_fragmentation
 */
static unsigned char buddy_tree_fragmentation(struct buddy_tree *t) {
    const unsigned char fractional_bits = 8;
    const unsigned char fractional_mask = 255;

    uint8_t tree_order;
    size_t root_status, quality, total_free_size, virtual_size, quality_percent;
    struct buddy_tree_walk_state state;

    tree_order = buddy_tree_order(t);
    root_status = buddy_tree_status(t, buddy_tree_root());
    if (root_status == 0) { /* Emptry tree */
        return 0;
    }

    quality = 0;
    total_free_size = 0;

    state = buddy_tree_walk_state_root();
    do {
        size_t pos_status = buddy_tree_status(t, state.current_pos);
        if (pos_status == 0) {
            /* Empty node, process */
            virtual_size = two_to_the_power_of((tree_order - state.current_pos.depth) % ((sizeof(size_t) * CHAR_BIT)-1));
            quality += (virtual_size * virtual_size);
            total_free_size += virtual_size;
            /* Ascend */
            state.going_up = 1;
        } else if (pos_status == (tree_order - state.current_pos.depth + 1)) {
            /* Busy node, ascend */
            state.going_up = 1;
        }
    } while (buddy_tree_walk(t, &state));

    if (total_free_size == 0) { /* Fully-allocated tree */
        return 0;
    }

    quality_percent = (integer_square_root(quality) << fractional_bits) / total_free_size;
    quality_percent *= quality_percent;
    quality_percent >>= fractional_bits;
    return (unsigned char)(fractional_mask - (quality_percent & fractional_mask));
}

#ifdef BUDDY_EXPERIMENTAL_CHANGE_TRACKING
static inline void buddy_tree_track_change(struct buddy_tree* t, unsigned char* addr, size_t length) {
    struct buddy_change_tracker *header;

    if (!(t->flags && BUDDY_TREE_CHANGE_TRACKING)) {
        return;
    }

    header = (struct buddy_change_tracker *) buddy_main(buddy_tree_buddy(t));
    header->tracker(header->context, addr, length);
}
#endif /* BUDDY_EXPERIMENTAL_CHANGE_TRACKING */

/*
 * A char-backed bitset implementation
 */

size_t bitset_sizeof(size_t elements) {
    return ((elements) + CHAR_BIT - 1u) / CHAR_BIT;
}

static uint8_t bitset_index_mask[8] = {1, 2, 4, 8, 16, 32, 64, 128};

static inline void bitset_set(unsigned char *bitset, size_t pos) {
    size_t bucket = pos / CHAR_BIT;
    size_t index = pos % CHAR_BIT;
    bitset[bucket] |= bitset_index_mask[index];
}

static inline void bitset_clear(unsigned char *bitset, size_t pos) {
    size_t bucket = pos / CHAR_BIT;
    size_t index = pos % CHAR_BIT;
    bitset[bucket] &= ~bitset_index_mask[index];
}

static inline bool bitset_test(const unsigned char *bitset, size_t pos) {
    size_t bucket = pos / CHAR_BIT;
    size_t index = pos % CHAR_BIT;
    return bitset[bucket] & bitset_index_mask[index];
}

static const uint8_t bitset_char_mask[8][8] = {
    {1, 3, 7, 15, 31, 63, 127, 255},
    {0, 2, 6, 14, 30, 62, 126, 254},
    {0, 0, 4, 12, 28, 60, 124, 252},
    {0, 0, 0,  8, 24, 56, 120, 248},
    {0, 0, 0,  0, 16, 48, 112, 240},
    {0, 0, 0,  0,  0, 32,  96, 224},
    {0, 0, 0,  0,  0,  0,  64, 192},
    {0, 0, 0,  0,  0,  0,   0, 128},
};

static inline struct bitset_range to_bitset_range(size_t from_pos, size_t to_pos) {
    struct bitset_range range = {0};
    range.from_bucket = from_pos / CHAR_BIT;
    range.to_bucket = to_pos / CHAR_BIT;

    range.from_index = from_pos % CHAR_BIT;
    range.to_index = to_pos % CHAR_BIT;
    return range;
}

static void bitset_set_range(unsigned char *bitset, struct bitset_range range) {
    if (range.from_bucket == range.to_bucket) {
        bitset[range.from_bucket] |= bitset_char_mask[range.from_index][range.to_index];
    } else {
        bitset[range.from_bucket] |= bitset_char_mask[range.from_index][7];
        bitset[range.to_bucket] |= bitset_char_mask[0][range.to_index];

        range.from_bucket++;

        if (range.to_bucket - range.from_bucket) {
            memset(bitset + range.from_bucket, 255u, range.to_bucket - range.from_bucket);
        }
    }
}

static void bitset_clear_range(unsigned char* bitset, struct bitset_range range) {
    if (range.from_bucket == range.to_bucket) {
        bitset[range.from_bucket] &= ~bitset_char_mask[range.from_index][range.to_index];
    }
    else {
        bitset[range.from_bucket] &= ~bitset_char_mask[range.from_index][7];
        bitset[range.to_bucket] &= ~bitset_char_mask[0][range.to_index];

        range.from_bucket++;

        if (range.to_bucket - range.from_bucket) {
            memset(bitset + range.from_bucket, 0, range.to_bucket - range.from_bucket);
        }
    }
}

static size_t bitset_count_range(unsigned char *bitset, struct bitset_range range) {
    size_t result;

    if (range.from_bucket == range.to_bucket) {
        return popcount_byte(bitset[range.from_bucket] & bitset_char_mask[range.from_index][range.to_index]);
    }

    result = popcount_byte(bitset[range.from_bucket] & bitset_char_mask[range.from_index][7])
        + popcount_byte(bitset[range.to_bucket]  & bitset_char_mask[0][range.to_index]);
    while(++range.from_bucket != range.to_bucket) {
        result += popcount_byte(bitset[range.from_bucket]);
    }
    return result;
}

static void bitset_shift_left(unsigned char *bitset, size_t from_pos, size_t to_pos, size_t by) {
    size_t length = to_pos - from_pos;
    for(size_t i = 0; i < length; i++) {
        size_t at = from_pos + i;
        if (bitset_test(bitset, at)) {
            bitset_set(bitset, at-by);
        } else {
            bitset_clear(bitset, at-by);
        }
        bitset_clear(bitset, at);
    }
}

static void bitset_shift_right(unsigned char *bitset, size_t from_pos, size_t to_pos, size_t by) {
    ssize_t length = (ssize_t) to_pos - (ssize_t) from_pos;
    while (length >= 0) {
        size_t at = from_pos + (size_t) length;
        if (bitset_test(bitset, at)) {
            bitset_set(bitset, at+by);
        } else {
            bitset_clear(bitset, at+by);
        }
        bitset_clear(bitset, at);
        length -= 1;
    }
}

void bitset_debug(unsigned char *bitset, size_t length) {
    for (size_t i = 0; i < length; i++) {
        BUDDY_PRINTF("%zu: %d\n", i, bitset_test(bitset, i) > 0);
    }
}

/*
 Bits
*/

static inline unsigned int popcount_byte(unsigned char b) {
    static const unsigned char popcount_lookup[256] = {
        0,1,1,2,1,2,2,3,1,2,2,3,2,3,3,4,1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,
        1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,
        1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,
        2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,
        1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,
        2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,
        2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,
        3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,4,5,5,6,5,6,6,7,5,6,6,7,6,7,7,8
    };
    return popcount_lookup[b];
}

static unsigned char count_trailing_zeroes(size_t val) {
   /* Implementation from https://www.chessprogramming.org/BitScan */
   static const signed char lookup67[67+1] = {
      64,  0,  1, 39,  2, 15, 40, 23,
       3, 12, 16, 59, 41, 19, 24, 54,
       4, -1, 13, 10, 17, 62, 60, 28,
      42, 30, 20, 51, 25, 44, 55, 47,
       5, 32, -1, 38, 14, 22, 11, 58,
      18, 53, 63,  9, 61, 27, 29, 50,
      43, 46, 31, 37, 21, 57, 52,  8,
      26, 49, 45, 36, 56,  7, 48, 35,
       6, 34, 33, -1 };
   return ((unsigned char) lookup67[(val & -val) % 67]);
}

/* Returns the highest set bit position for the given value. Returns zero for zero. */
static size_t highest_bit_position(size_t value) {
    size_t result = 0;
    /* some other millennia when size_t becomes 128-bit this will break :) */
#if SIZE_MAX == 0xFFFFFFFFFFFFFFFF
    const size_t all_set[] = {4294967295, 65535, 255, 15, 7, 3, 1};
    const size_t count[] = {32, 16, 8, 4, 2, 1, 1};
#elif SIZE_MAX == 0xFFFFFFFF
    const size_t all_set[] = {65535, 255, 15, 7, 3, 1};
    const size_t count[] = {16, 8, 4, 2, 1, 1};
#else
#error Unsupported platform
#endif

    for (size_t i = 0; i < (sizeof all_set / sizeof *all_set); i++) {
        if (value >= all_set[i]) {
            value >>= count[i];
            result += count[i];
        }
    }
    return result + value;
}

static inline size_t ceiling_power_of_two(size_t value) {
    value += !value; /* branchless x -> { 1 for 0, x for x } */
    return two_to_the_power_of(highest_bit_position(value + value - 1)-1);
}

static inline size_t two_to_the_power_of(size_t order) {
    return ((size_t)1) << order;
}

static inline size_t integer_square_root(size_t op) {
    /* by Martin Guy, 1985 - http://medialab.freaknet.org/martin/src/sqrt/ */
    size_t result = 0;
    size_t cursor = (SIZE_MAX - (SIZE_MAX >> 1)) >> 1; /* second-to-top bit set */
    while (cursor > op) {
        cursor >>= 2;
    }
    /* "cursor" starts at the highest power of four <= than the argument. */
    while (cursor != 0) {
        if (op >= result + cursor) {
            op -= result + cursor;
            result += 2 * cursor;
        }
        result >>= 1;
        cursor >>= 2;
    }
    return result;
}

#ifdef __cplusplus
#ifndef BUDDY_CPP_MANGLED
}
#endif
#endif

#endif /* BUDDY_ALLOC_IMPLEMENTATION */
