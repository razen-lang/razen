#ifndef RAZEN_DEFER_H
#define RAZEN_DEFER_H

// =============================================================
// HOW `defer` WORKS IN C
//
// Razen:
//   pub func handle_conn() -> void {
//       defer std.io.print("Closed!")
//       // ... rest of function
//   }
//
// `defer` means: run this code when the current SCOPE exits,
// no matter how it exits (return, break, end of block).
// Multiple defers run in REVERSE order (last defer runs first).
//
// C has NO defer keyword. There are two ways to implement it:
//
// =============================================================
// METHOD 1: GOTO CLEANUP (RECOMMENDED — works on all C compilers)
//
// Your emitter transforms the function like this:
//
//   void handle_conn() {
//       // --- function body ---
//       razen_io_print(RAZEN_STR("open"));
//
//       goto _cleanup_handle_conn;  // normal exit
//
//   _cleanup_handle_conn:
//       // deferred statements in REVERSE order
//       razen_io_print(RAZEN_STR("Closed!"));
//       return;
//   }
//
// For early returns, EVERY return statement becomes:
//   goto _cleanup_handle_conn;
//
// This is exactly how Zig implements defer internally.
// =============================================================

// =============================================================
// METHOD 2: GCC CLEANUP ATTRIBUTE (auto, but GCC/Clang only)
//
// GCC has __attribute__((cleanup(fn))) that calls fn when a
// variable goes out of scope. We can abuse this for defer.
//
// Example:
//   void _print_closed(int* _unused) {
//       razen_io_print(RAZEN_STR("Closed!"));
//   }
//   void handle_conn() {
//       int _defer0 __attribute__((cleanup(_print_closed))) = 0;
//       // rest of function — _print_closed runs automatically at end
//   }
//
// This works but requires generating a wrapper function per defer.
// =============================================================

// =============================================================
// WHAT YOUR EMITTER SHOULD DO (simple version):
//
// When emitting a function that has defer statements:
//
//   1. Collect all defer nodes during AST walk
//   2. At every ReturnStatement: emit defers in reverse, then return
//   3. At end of function body: emit defers in reverse, then return
//
// Pseudo-code in your Zig emitter:
//
//   fn emitFunction(func: FunctionDecl) void {
//       var defers = ArrayList(Node).init(allocator);
//
//       for (func.body) |stmt| {
//           if (stmt == .defer_stmt) {
//               defers.append(stmt.inner);
//           } else if (stmt == .return_stmt) {
//               // emit defers in reverse BEFORE the return
//               var i = defers.items.len;
//               while (i > 0) { i -= 1; emitNode(defers.items[i]); }
//               emitReturn(stmt);
//           } else {
//               emitNode(stmt);
//           }
//       }
//       // end of function — emit defers in reverse
//       var i = defers.items.len;
//       while (i > 0) { i -= 1; emitNode(defers.items[i]); }
//   }
// =============================================================

// Helper macro for the GCC cleanup approach (optional, advanced)
#if defined(__GNUC__) || defined(__clang__)
    #define RAZEN_DEFER_ATTR(cleanup_fn) __attribute__((cleanup(cleanup_fn)))
#else
    // On MSVC, you must use the goto method — no macro available
    #define RAZEN_DEFER_ATTR(cleanup_fn)
#endif

#endif // RAZEN_DEFER_H