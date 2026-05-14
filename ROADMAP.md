# Razen Compiler Roadmap

**Philosophy:** Meaningful. Accurate. Simple. Maximum Performance. No Hidden Magic.
**Style:** Direct. No fluff. Every checkbox is a concrete deliverable.

---

## Legend

| Mark | Meaning |
|------|---------|
| ✓ | Done — tested and working in pipeline |
| ◐ | Partial — parsed/validated but codegen missing or broken |
| ☐ | Not started |

---

## Stage 0: Project Infrastructure

### Build System
- ✓ Zig build system (build.zig + build.zig.zon) with `zig build run`
- ✓ Dependency on Zig 0.16.0
- ☐ `razenc` CLI binary (separate from host build)
- ☐ Source file input (currently hardcoded samples)
- ☐ Output file flags (`--emit=ir`, `--emit=obj`, `--emit=bin`)
- ☐ Target triple specification for cross-compilation
- ☐ Optimization level flags (-O0 through -O3)
- ☐ DWARF debug info generation

### Documentation
- ✓ README.md with philosophy and quick start
- ✓ ROADMAP.md (this file)
- ✓ docs/ — introduction, basics, types, functions, control flow, behaviours, std_lib
- ✓ design/ — keywords, std_new (detailed std spec)
- ☐ Language specification (formal grammar)
- ☐ Compiler internals guide

### Testing
- ✓ Sample programs in src/samples/ (39 test cases: 28 original + 10 error detection + 1 semantic)
- ☐ Automated test runner (`zig build test`)
- ☐ Unit tests for lexer, parser, semantic, codegen
- ☐ Integration tests (compile + verify LLVM IR output)
- ☐ Fuzz testing for parser and semantic analyzer
- ☐ Regression test suite for all open issues

---

## Stage 1: Lexer (Phase 1)

### Token Types — All Tokens Defined and Lexed
- ✓ Keywords: `func`, `ret`, `if`, `else`, `loop`, `break`, `skip`, `match`, `const`, `mut`, `pub`, `use`, `mod`, `struct`, `enum`, `union`, `error`, `behave`, `ext`, `async`, `defer`, `try`, `catch`, `type`, `true`, `false`, `void`, `noret`, `any`
- ✓ Primitive types: `i1`-`i128`, `u1`-`u128`, `isize`, `usize`, `int`, `uint`, `f16`-`f128`, `float`, `bool`, `char`, `str`, `string`
- ✓ Operators: `+`, `-`, `*`, `/`, `%`, `=`, `==`, `!=`, `<`, `>`, `<=`, `>=`, `+=`, `-=`, `*=`, `/=`, `%=`, `!`, `&&`, `||`, `&`, `|`, `^`, `~`, `<<`, `>>`, `.`, `..`, `...`, `..=`, `->`, `=>`, `~>`, `:`, `:=`, `,`, `;`, `@`
- ✓ Delimiters: `(`, `)`, `{`, `}`, `[`, `]`
- ✓ Integer literals (decimal)
- ✓ Float literals
- ✓ String literals with escape sequences (`\n`, `\t`, `\"`, `\\`, etc.)
- ✓ Char literals with escape sequences
- ✓ Bool literals (`true`, `false`)
- ✓ Single-line comments (`//`)
- ✓ Block comments (`/* */`)
- ✓ Line/column tracking on every token
- ✓ EOF token

### Lexer Architecture
- ✓ Stateful Lexer struct with position, line, char tracking
- ✓ Character-by-character processing loop
- ✓ Operator multi-character peek-ahead
- ✓ Dot operator differentiation (`.`, `..`, `...`, `..=`)
- ✓ Word/keyword/number disambiguation
- ✓ Identifier tokenization
- ✓ Unrecognized character handling

---

## Stage 2: Parser & AST (Phase 2)

### AST Node Types (63 node types)
- ✓ Literal nodes: IntegerLiteral, FloatLiteral, StringLiteral, CharLiteral, BoolLiteral
- ✓ Identifier node
- ✓ Type nodes: VarType, PointerType, ArrayType, OptionalType, FailableType, ErrorUnionType
- ✓ Declaration nodes: FunctionDeclaration, VarDeclaration, ConstDeclaration, StructDeclaration, EnumDeclaration, UnionDeclaration, ErrorMapDeclaration, TypeAliasDeclaration, ModuleDeclaration, UseDeclaration, BehaviourDeclaration, ExtDeclaration
- ✓ Statement nodes: ReturnStatement, IfStatement, LoopStatement, MatchStatement, TryStatement, CatchBlock, DeferStatement, BreakStatement, SkipStatement, Assignment, Block
- ✓ Expression nodes: BinaryExpression, UnaryExpression, FunctionCall, MemberAccess, ArrayLiteral, Argument, Parameters, Parameter
- ✓ Structural nodes: ReturnType, IfBody, ElseBody, LoopBody, MatchBody
- ✓ Annotation node (for `@` attributes)
- ✓ Comment node

### Declaration Parsing
- ✓ `func name(params) -> ret_type { body }` — full function parsing
- ✓ `pub func` / `async func` / `const func` / `ext func` variants
- ✓ Generic parameters: `@Generic(T)`, `@Generic(T, E)`
- ✓ Parameter parsing with `mut`/`const` prefix, variadic `...`
- ✓ `struct Name { fields... }` with methods, `~>` trait impls, field defaults
- ✓ `enum Name: backing_type { variants... }` with explicit values, methods, `~>`
- ✓ `union Name { variants... }` — tuple-style, struct-variant, recursive variants
- ✓ `error Name { variants... }` — error set declaration
- ✓ `behave Name { needs..., func... }` — behaviour/trait declaration
- ✓ `const Name: type = expr` — compile-time constants
- ✓ `type Name = Type` — type aliases
- ✓ `mod Name;` — module declarations
- ✓ `use dotted.path;` — import statements
- ✓ `pub` visibility flag on declarations

### Statement Parsing
- ✓ Variable declarations: `name: type = expr`, `name := expr`, `mut` variant
- ✓ Assignment: `name = expr`, name `+=`/`-=`/`*=`/`/=`/`%=` expr
- ✓ `ret expr` / `ret` (void return)
- ✓ `if cond { ... } else { ... }`
- ✓ `loop { ... }` — infinite loop
- ✓ `loop cond { ... }` — conditional loop (parsed)
- ✓ `loop expr |item| { ... }` — iterator loop (parsed)
- ✓ `break`, `skip`
- ✓ `defer { ... }`, `defer stmt`
- ✓ `match expr { pat => body, ... }` with literal/enum/destructure/wildcard patterns
- ✓ `try expr`, `try expr catch |err| { ... }`
- ✓ `@as(Type, expr)` and other `@` builtins (parsed)

### Expression Parsing
- ✓ Full precedence-climbing expression parser (12 levels)
- ✓ All binary operators with correct associativity
- ✓ Unary: `-`, `!`, `&` (address-of), `*` (dereference?) — actually `ptr.*`
- ✓ Pointer dereference: `ptr.*` (postfix)
- ✓ Member access: `a.b.c`
- ✓ Function calls: `f(args)` with argument lists
- ✓ Array literals: `[1, 2, 3]`
- ✓ Tuple literals: `.{a, b, c}`
- ✓ Range expressions: `a..b`, `a..=b`
- ✓ Capture blocks: `|e| expr`
- ✓ Parenthesized grouping
- ✓ Type annotations in expression context

### Type Parsing
- ✓ All primitive types (i8-u128, f16-f128, bool, char, void, noret, any)
- ✓ Pointer types: `*T`
- ✓ Optional types: `?T`
- ✓ Failable types: `!T`
- ✓ Error union types: `Error!T`
- ✓ Array types: `[T]`, `[T; N]`
- ✓ Collection types: `vec[T]`, `map{K,V}`, `set{T}`
- ✓ Builtin types: `@Self`, `@Type`, `@Generic(T)`
- ✓ `mut` type modifier

### AST Builder Architecture
- ✓ ASTData cursor with token navigation (getToken, peekToken, advance)
- ✓ ASTNode allocation with left/middle/right/children tree structure
- ✓ Child list management
- ✓ Error reporting with context
- ✓ Recursive descent through all constructs

---

## Stage 3: Semantic Analysis (Phase 3)

### Symbol Table & Scope Management
- ✓ Scope struct with parent chain for lexical scoping
- ✓ Symbol types: Variable, Function, Struct, Enum, Union, Trait
- ✓ PushScope / PopScope for block boundaries
- ✓ Function, loop, if, else, match body scope management
- ✓ Symbol definition with duplicate detection
- ✓ Symbol resolution with parent scope walk
- ✓ Two-pass design: pass 1 (declare globals) + pass 2 (analyze bodies)

### Name Resolution
- ✓ Global declaration registration (functions, structs, enums, unions, traits, behaviours)
- ✓ Variable name resolution in expressions
- ✓ Function name resolution for calls
- ☐ Module-scoped name resolution (mod / use paths)
- ✓ `std` identifier whitelisted — all std function names properly resolved
- ✓ `self`/`true`/`false` whitelisted as built-in identifiers

### Declaration Validation
- ✓ Duplicate declaration detection in same scope
- ✓ Function parameter count validation on calls
- ✓ Function argument count validation
- ✓ Mutability checks: `Cannot reassign to constant`
- ✓ Undeclared identifier detection
- ✓ Return type validation — declared return type vs actual expression
- ✓ Function parameter type matching — parameter types tracked
- ☐ Constant expression evaluation (comptime)
- ✓ Struct field declaration tracking with per-field type info
- ✓ Enum variant tracking
- ✓ Global duplicate detection (functions, constants, types)

### Type Checking
- ✓ Expression type inference for `:=` — RHS type resolved
- ✓ Operator type compatibility — arithmetic, comparison, logical, bitwise all validated
- ✓ Assignment type compatibility — LHS vs RHS type check
- ✓ Pointer/reference type validation — `&` address-of, `.*` dereference checked
- ✓ If condition must be boolean — non-bool rejected
- ✓ Loop condition must be boolean — non-bool rejected
- ✓ Break/skip outside loop detected — error reported
- ✓ Struct field access validation — non-existent field rejected
- ☐ Error union handling (try/catch completeness)
- ☐ Array/slice index validation
- ☐ Behaviour implementation signature checking
- ☐ Comptime const expression validation

---

## Stage 4: LLVM IR Code Generation (Phase 4)

### Phase 4 Architecture
- ✓ Module preamble: `source_filename`, target layout
- ✓ Libc function declarations (printf, puts, exit, abort)
- ✓ Std library IR injection (fmt, os, debug)
- ✓ Global node dispatch
- ✓ ConvertData shared state (tmp counter, label counter, var types, deferred stmts)
- ✓ StringBuilder for efficient IR assembly
- ✓ Comment nodes emitted as LLVM comments

### Type Mapping to LLVM
- ✓ i1, i2, i4, i8, i16, i32, i64, i128, isize, usize
- ✓ u1, u2, u4, u8, u16, u32, u64, u128
- ✓ f16 (half), f32 (float), f64 (double), f128 (fp128)
- ✓ bool → i1
- ✓ void → void
- ✓ noret (token exists, no special mapping)
- ✓ str → i32 (stub — no real string type yet)
- ◐ Pointer types → `ptr` (opaque pointer, functional for `&`/`.*`)
- ◐ *T → ptr
- ☐ Struct types → `%T = type { ... }`
- ☐ Enum types → integer backing type
- ☐ Union types → packed struct with tag + payload
- ☐ Error union types → struct { i1 success, union { T, error } }
- ☐ Fixed arrays → `[N x T]`
- ☐ Slices → `{ *T, i64 }`

### Variable Declarations
- ✓ Local `alloca` with optional `store`
- ✓ Type-inferred (`:=`) and explicit (`: type =`)
- ✓ Mutable (`mut`) and immutable
- ✓ Global constants tracked (not yet emitted as globals)
- ◐ Non-i32 types in alloca (resolved via resolveTypeNode but ops hardcode i32)
- ☐ Global constant emission as LLVM `@constants`

### Function Code Generation
- ✓ `define <ret> @<name>(<params>) { entry: ... }`
- ✓ Return type mapping (void, i32, i1 for bool)
- ✓ Parameter declaration with type
- ✓ Default return value for non-returning paths

### Expression Code Generation
- ✓ Integer literals
- ✓ Float literals
- ✓ Bool literals (true→"1", false→"0")
- ✓ Char literals (raw byte value)
- ◐ String literals — **BROKEN:** returns `"0"` placeholder
- ✓ Identifier resolution (local load, param ref, global const)
- ◐ Binary arithmetic: +, -, *, /, % → i32 ops
- ◐ Binary comparison: ==, !=, <, <=, >, >= → icmp + zext + trunc
- ✓ Binary logical: && (and i1), || (or i1)
- ✓ Binary bitwise: & (and), | (or), ^ (xor), << (shl), >> (ashr)
- ✓ Unary negate: `-x` → sub 0, x
- ✓ Unary logical not: `!x` → xor i1 x, true
- ✓ Address-of: `&x` → alloca pointer
- ✓ Dereference: `ptr.*` → load from pointer
- ◐ Member access: `a.b` — **BROKEN:** returns `"0"` placeholder
- ✓ Function calls: `call i32 @fn(i32 args)`
- ◐ Std function name mapping (print→std_print, etc.)
- ☐ Tuple literal codegen
- ☐ Array literal codegen
- ☐ Range expression codegen

### Statement Code Generation
- ✓ Simple assignment: `name = expr` → load + store
- ✓ Compound assignment: `+=`, `-=`, `*=`, `/=`, `%=` → load + op + store
- ✓ If/else: `br i1 cond` + basic blocks (true/else/merge)
- ✓ Infinite loop: back-edge branch + exit label
- ✓ `break`: branch to exit label
- ✓ `skip`: branch to continue label
- ✓ Defer: LIFO stack, flushed at return/break
- ◐ Match statement — **TODO:** emits `; TODO: MatchStatement`
- ◐ Try expression — **TODO:** emits `; TODO: TryExpression`
- ◐ Catch expression — **TODO:** emits `; TODO: CatchExpression`
- ◐ Builtin expression (`@as`, etc.) — **TODO:** emits `; TODO: BuiltinExpression`
- ☐ Iterator loop (`loop expr |i| { ... }`)
- ☐ Conditional loop (`loop cond { ... }`)

### Struct Code Generation — NOT IMPLEMENTED
- ☐ `%StructName = type { type1, type2, ... }` type definition
- ☐ `getelementptr` (GEP) for field access
- ☐ Struct construction (alloca + per-field store)
- ☐ Struct method calls (implicit self parameter)
- ☐ Nested struct layout with padding
- ☐ `~>` behaviour implementation (method wrapping)

### Enum Code Generation — NOT IMPLEMENTED
- ☐ Simple enum → integer constant map
- ☐ Backed enum → specified integer type
- ☐ Discriminant value emission
- ☐ `match` on enum → `switch` or icmp chain

### Union Code Generation — NOT IMPLEMENTED
- ☐ Tagged union → `{ i32 tag, [N x i8] payload }` or explicit union
- ☐ Tag read for match dispatch
- ☐ Payload extraction based on tag
- ☐ Union construction expression

### Error Handling Code Generation — NOT IMPLEMENTED
- ☐ Error union type → success flag + payload
- ☐ `try` → check flag, branch to handler on error
- ☐ `catch` → handler block with error binding
- ☐ Error integer codes
- ☐ Error propagation through call stack

### Behaviour / Trait Code Generation — NOT IMPLEMENTED
- ☐ Static dispatch (monomorphization)
- ☐ Dynamic dispatch vtable (`@Dyn`)
- ☐ Vtable struct definition
- ☐ Trait object creation
- ☐ Indirect call via vtable pointer

### Generator / Async Code Generation — NOT IMPLEMENTED
- ☐ State machine transformation for `async func`
- ☐ `Future` type and poll mechanism
- ☐ `await` suspension points

---

## Stage 5: Standard Library

### Current Std Architecture
- ◐ LLVM IR templates embedded in Zig const strings
- ◐ `src/std/std.zig` — wrapper (defines `all()` — **currently unused**)
- ✓ `src/std/fmt.zig` — `std_print` / `std_println` (printf-based)
- ✓ `src/std/os.zig` — `std_exit` / `std_clock_ms` / `std_clock_ns`
- ✓ `src/std/debug.zig` — `std_assert` / `std_panic`
- ✓ `stdFnName()` mapper in `llvm_flatten.zig`
- ✓ 7 function names mapped: print, println, exit, assert, panic, clock_ms, clock_ns

### Module Implementation Plan

#### `std.core` — Always In Scope (Compiler Builtins)
- ☐ `@SizeOf(T)` → comptime size query
- ☐ `@AlignOf(T)` → comptime alignment query
- ☐ `@TypeOf(expr)` → comptime type reflection
- ☐ `@Self` → self type in behaviours
- ☐ `@Generic(T)` → generic type parameter
- ☐ `@Dyn` → dynamic dispatch marker
- ☐ `@Type` → comptime type value
- ☐ `Option(T)` union (Some/None)
- ☐ `Result(T, E)` union (Ok/Err)
- ☐ `Ordering` enum (Less/Equal/Greater)
- ☐ `Eq` behaviour (eq, ne)
- ☐ `Ord` behaviour (cmp, lt, le, gt, ge)
- ☐ `Hash` behaviour (hash → u64)
- ☐ `Clone` behaviour (clone → Self)
- ☐ `Display` behaviour (display → str)
- ☐ `Debug` behaviour (debug → str)
- ☐ `Drop` behaviour (drop)

#### `std.mem` — Memory & Allocators
- ☐ `Allocator` behaviour (alloc, free, resize)
- ☐ `PageAllocator` (OS mmap/VirtualAlloc wrapper)
- ☐ `ArenaAllocator` (bump allocator, reset)
- ☐ `FixedAllocator` (fixed buffer, no heap)
- ☐ `StackAllocator(N)` (stack buffer with fallback)
- ☐ `PoolAllocator(T, N)` (typed slab)
- ☐ `CAllocator` (libc malloc/free wrapper)
- ☐ `DebugAllocator` (leak detection wrapper)
- ☐ `LogAllocator` (stats logging wrapper)
- ☐ `FailingAllocator` (test helper)
- ☐ `Layout` struct (size, align, of, array)
- ☐ `AllocStats` struct
- ☐ Raw memory: mem_copy, mem_move, mem_set, mem_zero, mem_eq
- ☐ Alignment: align_up, align_down, is_aligned
- ☐ `MemError` error set

#### `std.str` — String Slice Utilities
- ☐ len, is_empty, as_bytes, byte_at
- ☐ eq, starts_with, ends_with, contains
- ☐ find, find_char, rfind, rfind_char
- ☐ slice, slice_from, slice_to
- ☐ trim, trim_start, trim_end
- ☐ count, is_ascii
- ☐ split_once, split, lines, chars
- ☐ SplitPair, SplitIter, LinesIter, CharIter
- ☐ `StrError` error set

#### `std.string` — Heap String & Builder
- ☐ `String` struct (heap-allocated UTF-8)
- ☐ new, from, with_capacity, as_str
- ☐ push, push_str, pop, insert, remove
- ☐ clear, truncate, len, cap, is_empty
- ☐ clone, deinit
- ☐ `StringBuilder` struct
- ☐ write, write_char, write_byte, finish
- ☐ `StringError` error set

#### `std.fmt` — Formatting & Output
- ✓ `print(str)` → stdout
- ✓ `println(str)` → stdout with newline
- ☐ `eprint(str)` → stderr
- ☐ `eprintln(str)` → stderr with newline
- ☐ `format(alloc, fmt, args)` → heap-allocated formatted string
- ☐ `format_buf(buf, len, fmt, args)` → fixed buffer format
- ☐ `sprint(sb, fmt, args)` → StringBuilder format
- ☐ Format specifiers: `{}`, `{d}`, `{x}`, `{X}`, `{b}`, `{o}`, `{f}`, `{.N}`, `{>N}`, `{<N}`, `{p}`, `{?}`, `{!}`
- ☐ Display / Debug behaviours

#### `std.io` — Reader / Writer
- ☐ `Reader` behaviour (read)
- ☐ `Writer` behaviour (write, flush)
- ☐ `Seeker` behaviour (seek, tell)
- ☐ `SeekPos` union (Start, End, Current)
- ☐ `BufReader(R)` — buffered reader
- ☐ `BufWriter(W)` — buffered writer
- ☐ stdin(), stdout(), stderr() stream accessors
- ☐ `IoError` error set

#### `std.fs` — Files & Paths
- ☐ `File` struct (open, create, read, write, seek, tell, flush, size, close)
- ☐ `read_all(path, alloc)` → String
- ☐ `write_all(path, data)`, `append_all(path, data)`
- ☐ `OpenFlags` enum (Read, Write, Create, Truncate, Append)
- ☐ `Path` struct (from, join, parent, file_name, extension, exists, is_file, is_dir, as_str)
- ☐ `DirEntry`, `EntryKind` (File, Dir, Symlink, Other)
- ☐ read_dir, mkdir, mkdir_all, remove_file, remove_dir, remove_dir_all, rename, copy_file, cwd
- ☐ `FsError` error set

#### `std.os` — Operating System
- ✓ `exit(code)` → terminates process
- ◐ `clock_ms()` → returns 0 (stub)
- ◐ `clock_ns()` → returns 0 (stub)
- ☐ `args(alloc)` → command line arguments
- ☐ `env(key)`, `set_env(key, val)`, `unset_env(key)`
- ☐ `abort()` → abnormal termination
- ☐ `getpid()` → process ID
- ☐ `hostname(alloc)` → system hostname
- ☐ `sleep_ms(ms)` → millisecond sleep
- ☐ `OsError` error set

#### `std.vec` — Growable Array
- ☐ `Vec(T)` struct
- ☐ new, with_capacity, from_slice
- ☐ push, pop, insert, remove, swap_remove
- ☐ get, get_ptr, first, last
- ☐ len, cap, is_empty, clear, truncate
- ☐ reserve, shrink
- ☐ as_ptr, iter, sort, sort_by, contains, find, clone, deinit
- ☐ `VecIter(T)` struct
- ☐ `VecError` error set

#### `std.map` — Hash Map
- ☐ `Map(K, V)` struct
- ☐ new, with_capacity
- ☐ insert, get, get_ptr, remove, contains, get_or_insert
- ☐ len, is_empty, clear
- ☐ keys, values, entries iterators
- ☐ clone, deinit
- ☐ `MapEntry(K, V)`, `KeyIter(K)`, `ValIter(V)`, `EntryIter(K, V)`
- ☐ `MapError` error set

#### `std.set` — Hash Set
- ☐ `Set(T)` struct
- ☐ new, with_capacity
- ☐ insert, remove, contains
- ☐ len, is_empty, clear
- ☐ iter, union_with, intersect, difference, is_subset, is_superset
- ☐ clone, deinit
- ☐ `SetIter(T)` struct
- ☐ `SetError` error set

#### `std.ring` — Fixed Ring Buffer
- ☐ `Ring(T, N)` struct (stack-allocated)
- ☐ push, pop, peek, peek_back
- ☐ len, cap, is_empty, is_full, clear
- ☐ `RingIter(T)` struct

#### `std.math` — Numeric & Float
- ☐ Integer: min, max, clamp, abs, pow_int, gcd, lcm
- ☐ Integer: log2_floor, log2_ceil, next_power_of_two, is_power_of_two
- ☐ Saturating: saturating_add/sub/mul
- ☐ Checked: checked_add/sub/mul → ?T
- ☐ Wrapping: wrapping_add/sub/mul
- ☐ Float: sqrt, cbrt, floor, ceil, round, trunc, fract, abs_f
- ☐ Float: pow, exp, exp2, ln, log, log2, log10
- ☐ Float: sin, cos, tan, asin, acos, atan, atan2, hypot
- ☐ Float: lerp, is_nan, is_inf, is_finite, copysign
- ☐ Constants: PI, TAU, E, SQRT2, LN2, LN10, INF, NEG_INF, NAN
- ☐ Limits: I*_MIN/MAX, U*_MAX, F*_MAX/MIN_POS/EPSILON

#### `std.bits` — Bit Manipulation
- ☐ count_ones, count_zeros, leading_zeros, trailing_zeros
- ☐ leading_ones, trailing_ones
- ☐ rotate_left, rotate_right
- ☐ reverse_bits, byte_swap
- ☐ bit_get, bit_set, bit_clear, bit_toggle, bit_range
- ☐ parity

#### `std.ascii` — ASCII Utilities
- ☐ is_alpha, is_digit, is_alnum, is_space
- ☐ is_upper, is_lower, is_print, is_control, is_punct, is_hex_digit
- ☐ to_upper, to_lower
- ☐ to_digit, from_digit, hex_val, from_hex_val

#### `std.unicode` — UTF-8 Utilities
- ☐ encode_utf8, decode_utf8, char_utf8_len
- ☐ byte_count, char_count, nth_char
- ☐ is_valid_utf8
- ☐ is_alphabetic, is_numeric, is_alphanumeric, is_whitespace
- ☐ is_uppercase, is_lowercase, to_uppercase, to_lowercase
- ☐ codepoint, from_codepoint
- ☐ `DecodeResult` struct

#### `std.parse` — String to Value
- ☐ parse_i8 through parse_i64, parse_u8 through parse_u64
- ☐ parse_f32, parse_f64, parse_bool, parse_char
- ☐ parse_hex_u64, parse_oct_u64, parse_bin_u64
- ☐ i64_to_buf, u64_to_buf, f64_to_buf
- ☐ u64_to_hex, u64_to_bin, u64_to_oct
- ☐ `ParseError` error set

#### `std.buf` — Byte Buffer
- ☐ `ByteBuf` struct (growable byte buffer with cursor)
- ☐ new, with_capacity, from_bytes
- ☐ write_u8/i8, write_u16/32/64_le/be
- ☐ read_u8/i8, read_u16/32/64_le/be
- ☐ as_ptr, len, pos, remaining, seek_to, reset, clear, deinit
- ☐ `BufError` error set

#### `std.hash` — Hashing
- ☐ `Hasher` behaviour (write, write_u8/16/32/64, finish)
- ☐ `FnvHasher` struct
- ☐ `SipHasher` struct
- ☐ Convenience: hash_bytes_fnv, hash_bytes_sip, hash_str_fnv, hash_str_sip

#### `std.sync` — Atomics
- ☐ `MemOrder` enum (Relaxed, Acquire, Release, AcqRel, SeqCst)
- ☐ `Atomic(T)` struct (load, store, swap, compare_exchange, fetch_add/sub/and/or/xor)
- ☐ fence, spin_hint

#### `std.time` — Duration & Instant
- ☐ `Duration` struct (nanos, from_secs/millis/micros/nanos, as_*, add, sub, zero, is_zero)
- ☐ `Instant` struct (raw, now, elapsed, since, add)

#### `std.testing` — Test Runner
- ☐ `Test` struct (eq, neq, ok, err, is_true, is_false, near, skip, fail)
- ☐ `#[test]` attribute support
- ☐ `run(filter)`, `run_all()` runner functions

#### `std.debug` — Debug Utilities
- ✓ `assert(cond)` — runtime assertion
- ✓ `panic(msg)` — abort with message
- ☐ `assert_msg(cond, msg)`
- ☐ `unreachable()` → noret
- ☐ `panic_fmt`, `todo`, `todo_fmt`
- ☐ `static_assert` (comptime)
- ☐ `trace`, `trace_val`

---

## Stage 6: Critical Missing Codegen Features

These are the top-priority items that block Razen from being useful beyond i32 arithmetic.

### P0 — Must Fix
- ◐ **String literals emit `"0"`** — StringLiteral flatten needs to emit global string constants and return a pointer. Blocks all user-facing output.
- ☐ **Member access returns `"0"`** — MemberAccess flatten needs GEP. Blocks struct field access, method calls on structs.
- ◐ **All operations hardcode i32** — resolveTypeNode falls back to "i32". Binary ops emit i32 regardless of actual type. Blocks all non-i32 types.

### P1 — High Priority
- ☐ **Struct codegen** — `%T = type { ... }`, GEP, field store/load. Blocks Option, Result, Vec, Map, String, allocators — virtually everything in std.
- ☐ **Enum codegen** — integer mapping and switch dispatch. Blocks Ordering, error codes, state machines.
- ☐ **Match statement codegen** — switch/icmp chain with payload extraction. Blocks exhaustive enum handling.
- ◐ **Float ops emit i32** — fadd/fsub/fmul/fdiv/fcmp needed. Blocks all float arithmetic.

### P2 — Medium Priority
- ☐ **Error union codegen** — success flag + payload. Blocks try/catch.
- ☐ **Try / Catch codegen** — error propagation and handling.
- ☐ **Builtin expression codegen** — @as, @SizeOf, @TypeOf, etc.
- ☐ **Union codegen** — tagged union representation and access.
- ☐ **Array literal codegen** — stack allocation + initialization.

### P3 — Lower Priority
- ☐ **Behaviour dispatch** (static + dynamic)
- ☐ **Async/await** state machine
- ☐ **Comptime evaluation** for const func
- ☐ **Module system** (multi-file compilation)
- ☐ **Generic monomorphization**
- ☐ **varidic function calls** (printf-style)

---

## Stage 7: Compiler Self-Hosting

### Bootstrap Path
- ☐ Razen compiler written in Razen source files
- ☐ Razen std library written in Razen (not LLVM IR templates)
- ☐ Self-hosting: Razen compiler can compile itself
- ☐ Dogfooding: all new compiler features implemented in Razen

---

## Priority Pipeline

### P0 — Blocking Everything Else (Codegen)
- ☐ **String literal support** — emit global `@.str.N` constants, return `i8*`, update `puts` calls
- ☐ **Type-correct operations** — use actual LLVM types for arithmetic/comparison/logical instead of hardcoded `i32`
- ☐ **Struct codegen** — `%T = type { ... }`, `getelementptr` (GEP), field access, construction

### P1 — Core Usability
- ☐ **Match statement codegen** — switch/icmp chain with payload extraction
- ☐ **Enum codegen** — integer mapping, discriminant, switch dispatch
- ☐ **Float arithmetic** — fadd/fsub/fmul/fdiv/fcmp for f32/f64

### P2 — Std Library Enablement
- ☐ **Try/Catch codegen** — success flag, error propagation, handler blocks
- ☐ **Error union codegen** — `{ i1 success, union { T, error } }` representation
- ☐ **Builtin expression codegen** — `@as`, `@SizeOf`, `@TypeOf`

### P3 — Language Completeness
- ☐ **Generics (monomorphization)** — `@Generic(T)` specialization
- ☐ **Behaviour dispatch** — static dispatch, `@Dyn` vtable dispatch
- ☐ **Module system** — multi-file compilation, `use` imports, symbol resolution
- ☐ **Comptime evaluation** — `const func` execution at compile time
- ☐ **Async/await** — state machine transformation, Future type
- ☐ **Self-hosting** — Razen compiler written in Razen

## Milestone Summary

| Milestone | Description | Key Deliverables |
|-----------|-------------|------------------|
| M0 | Working pipeline | ✓ Full 4-phase pipeline with complete semantic analysis |
| M1 | String support | String literals, print/println with messages, std.fmt basics |
| M2 | Struct codegen | Struct types, field access, methods — unblocks ~80% of std |
| M3 | Type correctness | All types generate correct LLVM IR (not just i32) |
| M4 | Enum + Match | Enumerations compile, match dispatches correctly |
| M5 | Error handling | Error unions, try/catch propagate correctly |
| M6 | Collections | Vec, Map, Set with generics |
| M7 | Std complete | All 24 std modules implemented |
| M8 | Self-hosting | Razen compiler compiles itself |

---

## Design Constraints

- ✓ **Zero hidden allocations** — all allocation takes explicit Allocator param
- ◐ **Predictable LLVM mapping** — clear path from source to IR (struct/union/match/TODO)
- ◐ **No implicit casts** — type conversions must be explicit
- ✓ **No hidden magic** — no GC, no implicit allocs, no hidden control flow
- ✓ **Zero-cost abstractions** — behaviours dispatch without overhead

---

**Progress:** 42% of Stage 1-4 compiler core complete.
**Std Library:** 5% complete (7 of ~140 functions).
**Next Target (P0):** String literal support, type-correct operations, struct codegen.
