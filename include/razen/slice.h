#ifndef RAZEN_SLICE_H
#define RAZEN_SLICE_H

#include <stddef.h>
#include <string.h>
// allocator.h must be included before this (razen_core.h handles order)

// =============================================================
// SLICE  [T]
//
// Razen:  [u8]   = a view into an array. Does NOT own memory.
// C:      struct { T* ptr; size_t len; }
//
// Like Rust's &[T] or Zig's []T.
// You can't grow a slice. You can only read/write elements.
//
// Usage in generated C:
//   SliceI32 s = { .ptr = some_array, .len = 5 };
//   i32 first = s.ptr[0];
// =============================================================
#define RAZEN_DEFINE_SLICE(TYPE, NAME)  \
    typedef struct {                    \
        TYPE*  ptr;                     \
        usize  len;                     \
    } NAME

// Pre-defined slices for common types
RAZEN_DEFINE_SLICE(u8,    SliceU8);
RAZEN_DEFINE_SLICE(u16,   SliceU16);
RAZEN_DEFINE_SLICE(u32,   SliceU32);
RAZEN_DEFINE_SLICE(u64,   SliceU64);
RAZEN_DEFINE_SLICE(i8,    SliceI8);
RAZEN_DEFINE_SLICE(i16,   SliceI16);
RAZEN_DEFINE_SLICE(i32,   SliceI32);
RAZEN_DEFINE_SLICE(i64,   SliceI64);
RAZEN_DEFINE_SLICE(f32,   SliceF32);
RAZEN_DEFINE_SLICE(f64,   SliceF64);
RAZEN_DEFINE_SLICE(bool,  SliceBool);

// Create a slice from a C array literal — used in generated code
// Example: SliceI32 s = RAZEN_SLICE_FROM_ARRAY(((i32[]){1, 2, 3}), 3);
#define RAZEN_SLICE_FROM_ARRAY(arr_ptr, count) { .ptr = (arr_ptr), .len = (count) }

// =============================================================
// FIXED ARRAY  [T; N]
//
// Razen:  [i32; 4]   = stack-allocated, fixed size array
// C:      i32 arr[4];
//
// No struct needed — C arrays work directly.
// Your emitter should output:
//   i32 arr[4] = {1, 2, 3, 4};
// =============================================================

// =============================================================
// VEC  vec[T]
//
// Razen:  vec[i32]  = growable heap array
// C:      VecI32    = struct with ptr, len, capacity, allocator
//
// Like Rust's Vec<T> or Zig's std.ArrayList(T).
// Owns its memory. Must be freed when done.
//
// Usage in generated C:
//   VecI32 v = razen_vec_i32_new(&razen_c_allocator);
//   razen_vec_i32_push(&v, 42);
//   i32 x = razen_vec_i32_get(&v, 0);
//   razen_vec_i32_free(&v);
// =============================================================
#define RAZEN_DEFINE_VEC(TYPE, NAME)                                              \
    typedef struct {                                                               \
        TYPE*           ptr;       /* heap pointer to the data */                 \
        usize           len;       /* number of items currently in the vec */     \
        usize           capacity;  /* number of items we have space for */        \
        RazenAllocator* allocator; /* which allocator owns this memory */         \
    } NAME;                                                                        \
                                                                                   \
    /* Create a new empty vec */                                                   \
    static inline NAME NAME##_new(RazenAllocator* a) {                            \
        return (NAME){ .ptr = NULL, .len = 0, .capacity = 0, .allocator = a };   \
    }                                                                              \
                                                                                   \
    /* Push one item. Grows if needed. */                                          \
    static inline void NAME##_push(NAME* v, TYPE item) {                          \
        if (v->len >= v->capacity) {                                               \
            usize new_cap = v->capacity == 0 ? 8 : v->capacity * 2;              \
            v->ptr = (TYPE*)razen_resize(v->allocator, v->ptr,                   \
                         v->capacity * sizeof(TYPE),                              \
                         new_cap    * sizeof(TYPE), _Alignof(TYPE));             \
            v->capacity = new_cap;                                                \
        }                                                                          \
        v->ptr[v->len++] = item;                                                  \
    }                                                                              \
                                                                                   \
    /* Get item at index (no bounds check — your compiler should do that) */      \
    static inline TYPE NAME##_get(const NAME* v, usize i) {                      \
        return v->ptr[i];                                                          \
    }                                                                              \
                                                                                   \
    /* Set item at index */                                                        \
    static inline void NAME##_set(NAME* v, usize i, TYPE item) {                 \
        v->ptr[i] = item;                                                          \
    }                                                                              \
                                                                                   \
    /* Pop last item (undefined behavior if len == 0) */                          \
    static inline TYPE NAME##_pop(NAME* v) {                                      \
        return v->ptr[--v->len];                                                   \
    }                                                                              \
                                                                                   \
    /* Get a slice view into the vec (no copy, no allocation) */                  \
    static inline struct { TYPE* ptr; usize len; } NAME##_as_slice(NAME* v) {    \
        return (struct { TYPE* ptr; usize len; }){ .ptr = v->ptr, .len = v->len };\
    }                                                                              \
                                                                                   \
    /* Free the vec's memory */                                                    \
    static inline void NAME##_free(NAME* v) {                                     \
        if (v->ptr) razen_free(v->allocator, v->ptr, v->capacity * sizeof(TYPE), _Alignof(TYPE)); \
        v->ptr = NULL; v->len = 0; v->capacity = 0;                              \
    }

// Pre-defined vecs for common types
RAZEN_DEFINE_VEC(u8,   VecU8)
RAZEN_DEFINE_VEC(u32,  VecU32)
RAZEN_DEFINE_VEC(i32,  VecI32)
RAZEN_DEFINE_VEC(i64,  VecI64)
RAZEN_DEFINE_VEC(f32,  VecF32)
RAZEN_DEFINE_VEC(f64,  VecF64)

// =============================================================
// LOOP OVER SLICE — for your `loop items |i| {}` construct
//
// Razen:
//   loop items |x| {
//       std.io.print(x)
//   }
//
// Your emitter should generate:
//   for (usize _idx = 0; _idx < items.len; _idx++) {
//       i32 x = items.ptr[_idx];
//       razen_io_print_i32(x);
//   }
//
// The macro below is a shorthand for that pattern.
// =============================================================
#define RAZEN_FOREACH(item_var, item_type, slice) \
    for (usize _foreach_idx = 0; _foreach_idx < (slice).len; _foreach_idx++) \
        for (item_type item_var = (slice).ptr[_foreach_idx]; _foreach_idx < (slice).len; _foreach_idx = (usize)-1)

// =============================================================
// TUPLE  .{T1, T2, ...}
//
// Razen doesn't have named fields for tuples — just position.
// In C, tuples become anonymous structs.
// Your emitter generates a unique struct for each tuple type it sees.
//
// Example:
//   Razen:  .{i32, bool}  used as return type
//   C:      typedef struct { i32 _0; bool _1; } Tuple_i32_bool;
//
// No macro needed — your Zig emitter generates these on demand.
// =============================================================

#endif // RAZEN_SLICE_H