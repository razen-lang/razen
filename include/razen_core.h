#ifndef RAZEN_CORE_H
#define RAZEN_CORE_H

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>

// --- Core Macros ---

// Error Handling Simulation (Simplified for now)
// In standard C, try/catch is usually implemented via setjmp/longjmp or goto.
// For this simple version, RAZEN_TRY assumes the expression evaluates to something valid or crashes.
// RAZEN_CATCH simply evaluates the left side. A robust version requires a global error context.
#define RAZEN_TRY(expr) (expr)
#define RAZEN_CATCH(expr, catch_block) (expr)

// --- Builtin Types ---

// Razen String slice (stack allocated, utf-8)
typedef struct {
    const char* ptr;
    size_t len;
} RazenStr;

// --- Allocators (Simplified Stubs) ---
// Note: These are simplified stubs of the complex Zig-style allocators for now.

// @c allocator (Standard malloc/free)
typedef struct {
    void* (*alloc)(size_t size);
    void (*free)(void* ptr);
    void* (*resize)(void* ptr, size_t new_size);
} CAllocator;

static inline void* c_alloc_impl(size_t size) { return malloc(size); }
static inline void c_free_impl(void* ptr) { free(ptr); }
static inline void* c_resize_impl(void* ptr, size_t size) { return realloc(ptr, size); }

static const CAllocator builtin_c_allocator = {
    .alloc = c_alloc_impl,
    .free = c_free_impl,
    .resize = c_resize_impl
};

// @arena allocator (Simplified stub)
typedef struct {
    void* (*alloc)(size_t size);
    void (*free)(void* ptr);
} ArenaAllocator;

// @page allocator (Simplified stub)
typedef struct {
    void* (*alloc)(size_t size);
    void (*free)(void* ptr);
} PageAllocator;

#endif // RAZEN_CORE_H
