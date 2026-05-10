#ifndef RAZEN_PANIC_H
#define RAZEN_PANIC_H

#include <stdio.h>
#include <stdlib.h>

// =============================================================
// PANIC, ASSERT, UNREACHABLE
//
// These match std.debug in your standard library.
// Every Razen program needs these — they're the safety net.
// =============================================================

// --- panic ---
// Razen: debug.panic("something went wrong")
// Prints a message and exits immediately with code 1.
// Like Rust's panic!() or Zig's @panic()
static inline RAZEN_NORETURN void razen_panic(const char* msg, const char* file, int line) {
    fprintf(stderr, "\npanic at %s:%d\n  %s\n", file, line, msg);
    abort(); // abort() causes a crash dump, exit(1) just exits cleanly
}

// Macro so the file/line info is automatically filled in
#define razen_panic_msg(msg) razen_panic(msg, __FILE__, __LINE__)

// --- assert ---
// Razen: debug.assert(cond)
// In debug builds: if cond is false, panic.
// In release builds: removed (NDEBUG flag).
#ifndef NDEBUG
    #define razen_assert(cond) \
        do { if (!(cond)) razen_panic("assertion failed: " #cond, __FILE__, __LINE__); } while(0)
    #define razen_assert_msg(cond, msg) \
        do { if (!(cond)) razen_panic(msg, __FILE__, __LINE__); } while(0)
#else
    #define razen_assert(cond)          ((void)(cond))
    #define razen_assert_msg(cond, msg) ((void)(cond))
#endif

// --- unreachable ---
// Razen: debug.unreachable()
// Tells the compiler "this code should never run".
// If it DOES run in debug mode, it panics. In release, undefined behavior (optimizer hint).
#ifndef NDEBUG
    #define razen_unreachable() razen_panic("entered unreachable code", __FILE__, __LINE__)
#else
    #if defined(__GNUC__) || defined(__clang__)
        #define razen_unreachable() __builtin_unreachable()
    #elif defined(_MSC_VER)
        #define razen_unreachable() __assume(0)
    #else
        #define razen_unreachable() ((void)0)
    #endif
#endif

// --- todo ---
// Razen: debug.todo("not implemented yet")
#define razen_todo(msg) razen_panic("TODO: " msg, __FILE__, __LINE__)

// --- bounds check ---
// Your emitter adds this before every array index
// Example: razen_bounds_check(idx, slice.len)
#ifndef NDEBUG
    #define razen_bounds_check(idx, len) \
        razen_assert_msg((usize)(idx) < (usize)(len), "index out of bounds")
#else
    #define razen_bounds_check(idx, len) ((void)0)
#endif

#endif // RAZEN_PANIC_H