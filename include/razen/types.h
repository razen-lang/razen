#ifndef RAZEN_TYPES_H
#define RAZEN_TYPES_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

// =============================================================
// PRIMITIVE INTEGER TYPES
// These match Razen's type names directly.
// i8 = signed 8-bit, u8 = unsigned 8-bit, etc.
// =============================================================

// Sub-byte types: C has no i1/i2/i4, so we use i8 for all of them.
// Your compiler should warn if someone tries to store >1 bit in i1.
typedef int8_t   i1;
typedef int8_t   i2;
typedef int8_t   i4;
typedef int8_t   i8;
typedef int16_t  i16;
typedef int32_t  i32;
typedef int64_t  i64;

typedef uint8_t  u1;
typedef uint8_t  u2;
typedef uint8_t  u4;
typedef uint8_t  u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;

// `int` in Razen = i32. `uint` = u32.
typedef i32 razen_int;
typedef u32 razen_uint;

// 128-bit: only GCC and Clang support this natively.
// Think of it like Rust's i128 — same limitation on MSVC.
#if defined(__GNUC__) || defined(__clang__)
typedef __int128_t  i128;
typedef __uint128_t u128;
#else
// Fallback on MSVC: two 64-bit halves. Math won't work automatically.
typedef struct { int64_t  high; uint64_t low; } i128;
typedef struct { uint64_t high; uint64_t low; } u128;
#endif

// isize = signed pointer-sized int (like Rust's isize)
// usize = unsigned pointer-sized int (like Rust's usize / C's size_t)
typedef ptrdiff_t isize;
typedef size_t    usize;

// =============================================================
// FLOAT TYPES
// =============================================================

// f16: C has no standard f16. We stub it as u16.
// Your compiler should handle f16 math by promoting to f32.
typedef uint16_t f16;
typedef float    f32;
typedef double   f64;

#if defined(__GNUC__) || defined(__clang__)
typedef __float128 f128;
#else
typedef long double f128; // closest fallback
#endif

typedef f32 razen_float;

// =============================================================
// OTHER SCALAR TYPES
// =============================================================

typedef bool razen_bool;
typedef u32  razen_char; // char in Razen = Unicode codepoint = u32

// `any` = untyped pointer. Like void* in C, or *anyopaque in Zig.
typedef void* any;

// =============================================================
// VOID / NORET
// `void`  = function returns nothing
// `noret` = function never returns (panic, exit, infinite loop)
// Like Rust's `!` or Zig's `noreturn`
// =============================================================
typedef void razen_void;

// _Noreturn is standard C11. __attribute__((noreturn)) is GCC/Clang.
// We define a macro so your emitter can use RAZEN_NORETURN on functions.
#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
    #define RAZEN_NORETURN _Noreturn void
#elif defined(__GNUC__) || defined(__clang__)
    #define RAZEN_NORETURN __attribute__((noreturn)) void
#else
    #define RAZEN_NORETURN void
#endif

// =============================================================
// STR TYPE
// `str` in Razen = a UTF-8 string slice. NOT null-terminated.
// It's just a pointer + length. Like &str in Rust or []const u8 in Zig.
// IMPORTANT: str does NOT own its memory. It's a view into existing data.
// =============================================================
typedef struct {
    const u8* ptr; // pointer to the bytes
    usize     len; // number of bytes (NOT characters — UTF-8 can be multi-byte)
} RazenStr;

// This is how your emitter creates a str literal from a C string literal.
// Example: str s = RAZEN_STR("hello");
// The "" trick gets the length at compile time without calling strlen.
#define RAZEN_STR(literal) ((RazenStr){ .ptr = (const u8*)(literal), .len = sizeof(literal) - 1 })

// Short alias — your emitter should output `str` not `RazenStr`
typedef RazenStr str;

// =============================================================
// STRING TYPE (heap-allocated, mutable)
// `string` in Razen = owns its memory, can grow.
// Like String in Rust or std.ArrayList(u8) in Zig.
// =============================================================
typedef struct {
    u8*    ptr;       // pointer to heap memory
    usize  len;       // current number of bytes used
    usize  capacity;  // total allocated bytes
    void*  allocator; // which allocator owns this (cast to RazenAllocator* when used)
} RazenString;

typedef RazenString string;

// =============================================================
// OPTION TYPE  (?T)
// `?i32` in Razen = either Some(value) or None.
// Like Option<T> in Rust or ?T in Zig.
// Use the macro to define an Option for any type you need.
//
// Example:
//   RAZEN_DEFINE_OPTION(i32, OptionI32)
//   OptionI32 x = { .has_value = true, .value = 42 };
//   OptionI32 y = { .has_value = false };
// =============================================================
#define RAZEN_DEFINE_OPTION(TYPE, NAME)  \
    typedef struct {                     \
        bool has_value;                  \
        TYPE value;                      \
    } NAME

// Pre-defined common options so you don't have to define them every time
RAZEN_DEFINE_OPTION(void*,  OptionPtr);
RAZEN_DEFINE_OPTION(i32,    OptionI32);
RAZEN_DEFINE_OPTION(u32,    OptionU32);
RAZEN_DEFINE_OPTION(i64,    OptionI64);
RAZEN_DEFINE_OPTION(u64,    OptionU64);
RAZEN_DEFINE_OPTION(isize,  OptionIsize);
RAZEN_DEFINE_OPTION(usize,  OptionUsize);
RAZEN_DEFINE_OPTION(f32,    OptionF32);
RAZEN_DEFINE_OPTION(f64,    OptionF64);
RAZEN_DEFINE_OPTION(bool,   OptionBool);
RAZEN_DEFINE_OPTION(RazenStr, OptionStr);

// Helper macros — your emitter can output these instead of struct literals
#define RAZEN_SOME(val)  { .has_value = true,  .value = (val) }
#define RAZEN_NONE       { .has_value = false }

// =============================================================
// MAP AND SET (stubs — real implementation needs hash table)
// For now these are opaque blobs. Real impl comes later.
// =============================================================
typedef struct { void* ptr; usize len; void* allocator; } RazenMap;
typedef struct { void* ptr; usize len; void* allocator; } RazenSet;

#endif // RAZEN_TYPES_H