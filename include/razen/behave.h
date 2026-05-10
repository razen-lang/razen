#ifndef RAZEN_BEHAVE_H
#define RAZEN_BEHAVE_H

// =============================================================
// HOW `behave` WORKS IN C  (Razen's trait/interface system)
//
// Razen:
//   behave Display {
//       func display(a: @Self) -> str
//   }
//   struct Point ~> Display {
//       x: i32, y: i32,
//       func display(a: @Self) -> str { ... }
//   }
//
// C doesn't have interfaces. We use "vtables" — the same trick
// C++ uses internally, and the same way Zig does dynamic dispatch.
//
// A vtable is a struct of function pointers.
// An "object" that implements a behave = { data pointer + vtable pointer }
//
// STATIC dispatch (most common, no overhead):
//   When the type is known at compile time, your emitter calls
//   the function directly: Point_display(p)
//   No vtable needed!
//
// DYNAMIC dispatch (@Dyn in Razen):
//   When you have a `@Dyn Display`, you need a vtable.
//   The vtable struct + dyn object are generated below.
// =============================================================

// =============================================================
// HOW TO USE THIS IN YOUR EMITTER
//
// For each `behave Foo { func bar(a: @Self) -> RetType }`:
//
//   1. Emit a vtable struct:
//      typedef struct { RetType (*bar)(void* self); } Foo_vtable;
//
//   2. For each `struct MyType ~> Foo`:
//      Emit the actual function: RetType MyType_bar(MyType* self) { ... }
//      Emit a vtable instance:
//        static Foo_vtable MyType_Foo_vtable = { .bar = MyType_bar };
//
//   3. For `@Dyn Foo` variables, emit:
//      typedef struct { void* data; Foo_vtable* vtable; } Dyn_Foo;
//      Dyn_Foo obj = { .data = &my_point, .vtable = &Point_Foo_vtable };
//
//   4. To call through dyn:
//      obj.vtable->bar(obj.data)
// =============================================================

// Macro to define a Dyn object for any behave
// Your emitter calls this once per @Dyn usage
#define RAZEN_DEFINE_DYN(VTABLE_TYPE, DYN_NAME) \
    typedef struct {                             \
        void*         data;                      \
        VTABLE_TYPE*  vtable;                    \
    } DYN_NAME

// =============================================================
// CORE BEHAVIOURS — always in scope (from std.core)
// Your emitter auto-generates these vtables for built-in behaviours.
// =============================================================

// --- Ordering (for Ord behave) ---
typedef enum {
    Ordering_Less    = -1,
    Ordering_Equal   =  0,
    Ordering_Greater =  1,
} Ordering;

// --- Eq behave vtable ---
typedef struct {
    bool (*eq)(void* self, void* other);
    bool (*ne)(void* self, void* other);
} Eq_vtable;

// --- Ord behave vtable (extends Eq) ---
typedef struct {
    // Eq methods
    bool (*eq)(void* self, void* other);
    bool (*ne)(void* self, void* other);
    // Ord methods
    Ordering (*cmp)(void* self, void* other);
    bool     (*lt) (void* self, void* other);
    bool     (*le) (void* self, void* other);
    bool     (*gt) (void* self, void* other);
    bool     (*ge) (void* self, void* other);
} Ord_vtable;

// --- Hash behave vtable ---
typedef struct {
    u64 (*hash)(void* self);
} Hash_vtable;

// --- Clone behave vtable ---
typedef struct {
    void* (*clone)(void* self); // returns a heap copy; caller owns it
} Clone_vtable;

// --- Display behave vtable ---
typedef struct {
    RazenStr (*display)(void* self);
} Display_vtable;

// --- Debug behave vtable ---
typedef struct {
    RazenStr (*debug)(void* self);
} Debug_vtable;

// --- Drop behave vtable ---
typedef struct {
    void (*drop)(void* self);
} Drop_vtable;

// Dyn versions of the core behaviours (for @Dyn Display etc.)
RAZEN_DEFINE_DYN(Display_vtable, Dyn_Display);
RAZEN_DEFINE_DYN(Debug_vtable,   Dyn_Debug);
RAZEN_DEFINE_DYN(Eq_vtable,      Dyn_Eq);
RAZEN_DEFINE_DYN(Ord_vtable,     Dyn_Ord);
RAZEN_DEFINE_DYN(Hash_vtable,    Dyn_Hash);
RAZEN_DEFINE_DYN(Clone_vtable,   Dyn_Clone);
RAZEN_DEFINE_DYN(Drop_vtable,    Dyn_Drop);

#endif // RAZEN_BEHAVE_H