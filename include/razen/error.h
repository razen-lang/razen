#ifndef RAZEN_ERROR_H
#define RAZEN_ERROR_H

#include <stdint.h>
#include <stdbool.h>
// Note: types.h must be included before this file (razen_core.h handles order)

// =============================================================
// HOW ERRORS WORK IN RAZEN → C
//
// Razen:     func read(f: File) -> IoError!i32
// C output:  ErrorUnionI32 read(RazenFile f);
//
// The ErrorUnion struct holds EITHER an error code OR a value.
// error == 0 (RAZEN_OK) means success, value field is valid.
// error != 0 means failure, value field is garbage — don't read it.
//
// This is exactly how Zig does it internally.
// =============================================================

// Every error is just an i32 under the hood.
// 0 = no error. Anything else = some error code.
typedef int32_t RazenError;
#define RAZEN_OK 0

// =============================================================
// ERROR UNION MACRO  (!T or Error!T)
//
// `!i32` in Razen becomes ErrorUnionI32 in C.
// Define one for each type you need.
//
// Usage:
//   RAZEN_DEFINE_ERROR_UNION(i32, ErrorUnionI32)
//
//   ErrorUnionI32 divide(i32 a, i32 b) {
//       if (b == 0) return (ErrorUnionI32){ .error = ERR_DIV_ZERO };
//       return (ErrorUnionI32){ .error = RAZEN_OK, .value = a / b };
//   }
// =============================================================
#define RAZEN_DEFINE_ERROR_UNION(TYPE, NAME) \
    typedef struct {                         \
        RazenError error;                    \
        TYPE       value;                    \
    } NAME

// Pre-defined common error unions
RAZEN_DEFINE_ERROR_UNION(void*,    ErrorUnionPtr);
RAZEN_DEFINE_ERROR_UNION(int32_t,  ErrorUnionI32);
RAZEN_DEFINE_ERROR_UNION(uint32_t, ErrorUnionU32);
RAZEN_DEFINE_ERROR_UNION(int64_t,  ErrorUnionI64);
RAZEN_DEFINE_ERROR_UNION(uint64_t, ErrorUnionU64);
RAZEN_DEFINE_ERROR_UNION(float,    ErrorUnionF32);
RAZEN_DEFINE_ERROR_UNION(double,   ErrorUnionF64);
RAZEN_DEFINE_ERROR_UNION(bool,     ErrorUnionBool);

// For !void (function that can fail but returns nothing on success)
typedef struct { RazenError error; } ErrorUnionVoid;

// Helper to build a success value — your emitter outputs this
#define RAZEN_OK_VAL(TYPE, val)  ((TYPE){ .error = RAZEN_OK, .value = (val) })
#define RAZEN_OK_VOID            ((ErrorUnionVoid){ .error = RAZEN_OK })
#define RAZEN_ERR_VAL(TYPE, err) ((TYPE){ .error = (err) })

// =============================================================
// RESULT TYPE  (Result[T, E])
//
// Razen:  Result[i32, str]
// C:      result is a tagged union — tag tells you Ok vs Err
//
// This is different from ErrorUnion:
//   !T         = error is just an int code
//   Result[T,E] = error can be any type E (like Rust's Result<T,E>)
//
// For now we use a simple bool tag. Your emitter generates
// a specific struct for each Result[T, E] combination it sees.
// =============================================================
#define RAZEN_DEFINE_RESULT(OK_TYPE, ERR_TYPE, NAME) \
    typedef struct {                                  \
        bool is_ok;                                   \
        union {                                       \
            OK_TYPE  ok;                              \
            ERR_TYPE err;                             \
        };                                            \
    } NAME

// =============================================================
// TRY / CATCH MACROS
//
// Razen:  res := try some_func() catch |e| { ret }
//
// Your emitter should expand `try` into explicit if-checks,
// NOT these macros, for maximum compatibility.
// But these macros are here as a fallback for GCC/Clang.
//
// The CLEAN way your emitter should generate:
//
//   ErrorUnionI32 _tmp0 = some_func();
//   if (_tmp0.error != RAZEN_OK) {
//       /* catch block here */
//       return;
//   }
//   i32 res = _tmp0.value;
//
// That works on ALL C compilers, no GNU extensions needed.
// =============================================================
#if defined(__GNUC__) || defined(__clang__)

// GNU extension version (shorter but GCC/Clang only)
#define RAZEN_TRY(expr, ReturnType) ({          \
    __auto_type _r = (expr);                    \
    if (_r.error != RAZEN_OK) {                 \
        return (ReturnType){ .error = _r.error };\
    }                                           \
    _r.value;                                   \
})

#define RAZEN_CATCH(expr, catch_block) ({       \
    __auto_type _r = (expr);                    \
    if (_r.error != RAZEN_OK) { catch_block; }  \
    _r.value;                                   \
})

#else
// Standard C fallback — your emitter should prefer explicit expansion
#define RAZEN_TRY(expr, ReturnType)  (expr).value
#define RAZEN_CATCH(expr, catch_block) (expr).value
#endif

// =============================================================
// COMMON ERROR CODES
// Your compiler generates specific error enums per `error Foo {}`
// declaration. These are the built-in ones from std.
// =============================================================
typedef enum {
    RazenError_Ok           = 0,
    RazenError_OutOfMemory  = 1,
    RazenError_InvalidArg   = 2,
    RazenError_NotFound     = 3,
    RazenError_Overflow     = 4,
    RazenError_Underflow    = 5,
    RazenError_DivByZero    = 6,
    RazenError_IoError      = 7,
    RazenError_Eof          = 8,
    RazenError_AccessDenied = 9,
} RazenErrorCode;

#endif // RAZEN_ERROR_H