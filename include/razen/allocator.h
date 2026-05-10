#ifndef RAZEN_ALLOCATOR_H
#define RAZEN_ALLOCATOR_H

#include <stddef.h>
#include <stdlib.h>
#include <string.h>

// =============================================================
// HOW ALLOCATORS WORK IN RAZEN → C
//
// In Razen, every heap allocation goes through an Allocator.
// This is the same idea as Zig's std.mem.Allocator.
//
// Instead of calling malloc() directly, generated C code calls:
//   allocator->alloc(allocator, size, align)
//
// This means you can swap allocators without changing your Razen code.
// Example: use an arena allocator during parsing (fast, free all at once),
//          use the C allocator for long-lived data.
//
// Your emitter should pass allocators around for anything heap-allocated:
//   vec[T], map{K,V}, set{T}, string, etc.
// =============================================================

// Forward declare so function pointers can reference this struct
typedef struct RazenAllocator RazenAllocator;

struct RazenAllocator {
    void* ctx; // internal state pointer (e.g. arena's bump pointer)

    // alloc: get `size` bytes with `align` alignment
    // Returns NULL on failure
    void* (*alloc)  (RazenAllocator* self, size_t size, size_t align);

    // resize: grow or shrink an existing allocation
    // old_size = what you originally asked for
    // Returns NULL on failure (original ptr still valid)
    void* (*resize) (RazenAllocator* self, void* ptr, size_t old_size, size_t new_size, size_t align);

    // free: give memory back
    // You MUST pass the same size and align you used for alloc
    void  (*free)   (RazenAllocator* self, void* ptr, size_t size, size_t align);
};

// =============================================================
// CONVENIENCE WRAPPERS
// Your generated C code calls these instead of the function pointers directly.
// Cleaner than writing allocator->alloc(allocator, ...) everywhere.
// =============================================================

static inline void* razen_alloc(RazenAllocator* a, size_t size, size_t align) {
    return a->alloc(a, size, align);
}

static inline void* razen_resize(RazenAllocator* a, void* ptr, size_t old_size, size_t new_size, size_t align) {
    return a->resize(a, ptr, old_size, new_size, align);
}

static inline void razen_free(RazenAllocator* a, void* ptr, size_t size, size_t align) {
    a->free(a, ptr, size, align);
}

// =============================================================
// C ALLOCATOR  (@c in Razen)
// Wraps malloc/realloc/free. The simplest allocator.
// Use this as the default when you don't care about performance.
// =============================================================

static void* _c_alloc(RazenAllocator* self, size_t size, size_t align) {
    (void)self; (void)align;
    return malloc(size);
}

static void* _c_resize(RazenAllocator* self, void* ptr, size_t old_size, size_t new_size, size_t align) {
    (void)self; (void)old_size; (void)align;
    return realloc(ptr, new_size);
}

static void _c_free(RazenAllocator* self, void* ptr, size_t size, size_t align) {
    (void)self; (void)size; (void)align;
    free(ptr);
}

// Global C allocator instance — use this in generated code like:
//   RazenAllocator* alloc = &razen_c_allocator;
static RazenAllocator razen_c_allocator = {
    .ctx    = NULL,
    .alloc  = _c_alloc,
    .resize = _c_resize,
    .free   = _c_free,
};

// =============================================================
// ARENA ALLOCATOR  (@arena in Razen)
// Bump pointer allocator: allocations are O(1), freeing is all-or-nothing.
// Perfect for: parsing phase, temporary scratch memory.
// How it works:
//   - You give it a big block of memory upfront
//   - Each alloc just moves a pointer forward ("bumps" it)
//   - You can't free individual items — you reset the whole arena
// =============================================================

typedef struct {
    u8*    buf;      // start of the memory block
    size_t len;      // total size of the block
    size_t pos;      // current position (next free byte)
} RazenArenaState;

static void* _arena_alloc(RazenAllocator* self, size_t size, size_t align) {
    RazenArenaState* s = (RazenArenaState*)self->ctx;
    // Align the current position up to `align`
    size_t aligned_pos = (s->pos + align - 1) & ~(align - 1);
    if (aligned_pos + size > s->len) return NULL; // out of space
    s->pos = aligned_pos + size;
    return s->buf + aligned_pos;
}

static void* _arena_resize(RazenAllocator* self, void* ptr, size_t old_size, size_t new_size, size_t align) {
    // Arena can only resize the LAST allocation (optimization)
    // For simplicity, just alloc new and copy. A real impl would check if ptr is last.
    void* new_ptr = _arena_alloc(self, new_size, align);
    if (new_ptr && ptr) memcpy(new_ptr, ptr, old_size < new_size ? old_size : new_size);
    return new_ptr;
}

static void _arena_free(RazenAllocator* self, void* ptr, size_t size, size_t align) {
    // Arena doesn't free individual items — no-op
    (void)self; (void)ptr; (void)size; (void)align;
}

// Create an arena allocator from a buffer
// Usage:
//   uint8_t buf[4096];
//   RazenArenaState arena_state;
//   RazenAllocator arena = razen_arena_init(buf, sizeof(buf), &arena_state);
static inline RazenAllocator razen_arena_init(void* buf, size_t len, RazenArenaState* state) {
    state->buf = (u8*)buf;
    state->len = len;
    state->pos = 0;
    return (RazenAllocator){
        .ctx    = state,
        .alloc  = _arena_alloc,
        .resize = _arena_resize,
        .free   = _arena_free,
    };
}

// Reset arena — all previously allocated memory becomes reusable
static inline void razen_arena_reset(RazenAllocator* a) {
    ((RazenArenaState*)a->ctx)->pos = 0;
}

// =============================================================
// PAGE ALLOCATOR  (@page in Razen)
// Uses OS directly (mmap on Linux/Mac, VirtualAlloc on Windows).
// Allocates in whole pages (4KB minimum). Use for large allocations.
// For now, falls back to malloc — real impl adds mmap later.
// =============================================================
static RazenAllocator razen_page_allocator = {
    .ctx    = NULL,
    .alloc  = _c_alloc,
    .resize = _c_resize,
    .free   = _c_free,
};

#endif // RAZEN_ALLOCATOR_H