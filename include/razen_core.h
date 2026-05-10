#ifndef RAZEN_CORE_H
#define RAZEN_CORE_H

// =============================================================
// RAZEN CORE RUNTIME
//
// Every generated C file includes this one header.
// It pulls in everything your generated code needs.
//
// ORDER MATTERS in C:
//   types.h       first — everything else depends on these typedefs
//   error.h       second — needs RazenError, uses types
//   allocator.h   third — needs usize from types
//   slice.h       fourth — needs RazenAllocator, usize
//   behave.h      fifth — needs RazenStr, Ordering
//   defer.h       sixth — standalone, no deps
//   panic.h       last — needs RAZEN_NORETURN from types
// =============================================================

#include "razen/types.h"      // i32, u8, str, RazenStr, Option, etc.
#include "razen/error.h"      // RazenError, ErrorUnion, try/catch macros
#include "razen/allocator.h"  // RazenAllocator, arena, c_allocator
#include "razen/slice.h"      // [T] slices, vec[T] growable arrays
#include "razen/behave.h"     // vtables for @Dyn dispatch
#include "razen/defer.h"      // defer implementation notes
#include "razen/panic.h"      // razen_panic, razen_assert, razen_unreachable

// =============================================================
// TYPE MAPPING TABLE
// This is the reference for your Zig emitter.
// When you see a Razen type, emit the corresponding C type.
//
// Razen type     → C type
// ------------------------------------
// i8             → i8
// i16            → i16
// i32 / int      → i32
// i64            → i64
// i128           → i128
// isize          → isize
// u8             → u8
// u16            → u16
// u32 / uint     → u32
// u64            → u64
// u128           → u128
// usize          → usize
// f16            → f16   (stubbed as u16, careful!)
// f32 / float    → f32
// f64            → f64
// f128           → f128
// bool           → bool
// char           → razen_char  (u32, Unicode codepoint)
// void           → void
// noret          → RAZEN_NORETURN  (use as return type)
// any            → void*
// str            → str  (= RazenStr struct, ptr+len)
// string         → string (= RazenString, heap-owned)
// *T             → T*
// ?T             → OptionX  (use RAZEN_DEFINE_OPTION if not pre-defined)
// !T             → ErrorUnionX  (use RAZEN_DEFINE_ERROR_UNION)
// [T]            → SliceX (ptr+len, no ownership)
// [T; N]         → T arr[N]  (C array, stack allocated)
// vec[T]         → VecX (ptr+len+cap+alloc)
// map{K,V}       → RazenMap (stub for now)
// set{T}         → RazenSet (stub for now)
// .{T1,T2}       → struct { T1 _0; T2 _1; }  (generated inline)
// =============================================================

// =============================================================
// CONST vs MUT
//
// Razen:  const x : i32 = 5    →  const i32 x = 5;
// Razen:  mut x : i32 = 5      →  i32 x = 5;   (mutable by default in C)
// Razen:  x : i32 = 5          →  const i32 x = 5;  (immutable by default)
//
// Rule: if Razen variable has NO `mut` → add `const` in C
//       if Razen variable HAS `mut`   → no const in C
// =============================================================

// =============================================================
// PUB vs PRIVATE FUNCTIONS
//
// Razen:  pub func foo()  →  (no prefix, just: void foo())
// Razen:  func foo()      →  static void foo()
//                               ^ `static` in C = only visible in this file
//                                 This matches Razen's default private visibility
// =============================================================

// =============================================================
// EXT FUNC  (external C function declaration)
//
// Razen:  ext func bind(port: int) -> int
// C:      extern int bind(int port);
//                   ^ no body! just a declaration
//
// Your emitter MUST output `extern` and NO body `{}`
// =============================================================

#endif // RAZEN_CORE_H