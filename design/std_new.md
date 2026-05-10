# Razen Standard Library

**Rules applied from your files:**
- Value semantics — no borrow system, no `&self` ownership, pass by value or `*T` pointer
- `@Self` for self-type in behaviours/structs
- `@Generic(T)` / `@Generic(T, E)` for generics
- `mut` prefix on variable or parameter to mark mutable
- `*T` is pointer, `&x` takes address, `ptr.*` dereferences
- `?T` optional, `!T` can fail, `Error!T` typed error result
- `func` inside struct/enum body — methods are just functions with explicit self param
- `~>` for behaviour implementation
- `try` / `catch` for error propagation
- `ret` to return
- No borrow checker, no lifetime annotations

---

## Module Tree

```
std
├── core          ← always in scope, never imported
├── mem           ← allocators, raw memory, layout
├── str           ← str slice utilities (UTF-8, stack)
├── string        ← heap string + builder
├── fmt           ← format, print, Display/Debug behaviours
├── io            ← reader/writer behaviours, buffered I/O
├── fs            ← files, paths, directory
├── os            ← args, env, exit, clock, process
├── vec           ← growable array
├── map           ← hash map
├── set           ← hash set
├── ring          ← fixed ring buffer
├── math          ← numeric, float, constants
├── bits          ← bitwise manipulation
├── ascii         ← ASCII char utilities
├── unicode       ← UTF-8 / char utilities
├── parse         ← str → numbers / bool
├── buf           ← byte buffer, LE/BE read-write
├── hash          ← FNV, SipHash
├── sync          ← atomics, fence
├── time          ← duration, instant, clock
├── testing       ← test assertions, runner
└── debug         ← assert, panic, unreachable, trace
```

---

## `std.core` — Always In Scope

Never `use`d. Compiler injects this automatically.

### Built-in Types
```
i8, i16, i32, i64, i128, isize
int                            // alias i32
u8, u16, u32, u64, u128, usize
uint                           // alias u32
f32, f64, f128
float                          // alias f32
bool
char
void
noret
any
str                            // UTF-8 slice, stack
string                         // heap string
```

### Memory / Modifier Types
```
*T        // pointer to T
&x        // take address of x  (expression, not a type on its own)
ptr.*     // dereference ptr
?T        // optional — Some(T) or None
!T        // can fail — value or anonymous error
Error!T   // typed error result — T or Error
```

### Built-in Collections
```
[T]       // slice
[T; N]    // fixed array, N is comptime
vec[T]    // growable array (heap)
map{K, V} // hash map (heap)
set{T}    // hash set (heap)
```

### Tuple
```
.{T1, T2, ...}   // tuple literal / type
```

### Core Unions — always in scope
```
@Generic(T) union Option {
    Some(T),
    None,
}

@Generic(T, E) union Result {
    Ok(T),
    Err(E),
}
```

### Core Enum — always in scope
```
enum Ordering {
    Less,
    Equal,
    Greater,
}
```

### Core Behaviours — always in scope
```
behave Eq {
    func eq(a: @Self, b: @Self) -> bool
    func ne(a: @Self, b: @Self) -> bool
}

behave Ord ~> Eq {
    func cmp(a: @Self, b: @Self) -> Ordering
    func lt(a: @Self, b: @Self) -> bool
    func le(a: @Self, b: @Self) -> bool
    func gt(a: @Self, b: @Self) -> bool
    func ge(a: @Self, b: @Self) -> bool
}

behave Hash {
    func hash(a: @Self) -> u64
}

behave Clone {
    func clone(a: @Self) -> @Self
}

behave Display {
    func display(a: @Self) -> str
}

behave Debug {
    func debug(a: @Self) -> str
}

behave Drop {
    func drop(mut a: @Self) -> void
}
```

### Compiler Builtins — always available
```
@SizeOf(T)           // comptime: size in bytes of T        -> usize
@AlignOf(T)          // comptime: alignment of T            -> usize
@TypeOf(expr)        // comptime: type of expression        -> type
@Self                // current type inside struct/behave
@Generic(T)          // mark func or struct as generic on T
@Generic(T, E)       // mark as generic on T and E
@Dyn                 // mark behave as dynamic-dispatchable
@Type                // comptime type value
```

---

## `std.mem` — Memory & Allocators

```
use std.mem
```

### Allocator Struct

All allocators share this interface via `behave Allocator`.

```
behave Allocator {
    func alloc(a: @Self, size: usize, align: usize) -> !*u8
    func free(a: @Self, ptr: *u8, size: usize, align: usize) -> void
    func resize(a: @Self, ptr: *u8, old_size: usize, new_size: usize, align: usize) -> !*u8
}
```

### Allocator Types

All come from builtins, wrapped with this interface:

```
// @page  — OS page allocator (mmap / VirtualAlloc)
struct PageAllocator ~> Allocator {
    func alloc(a: @Self, size: usize, align: usize) -> !*u8
    func free(a: @Self, ptr: *u8, size: usize, align: usize) -> void
    func resize(a: @Self, ptr: *u8, old: usize, new: usize, align: usize) -> !*u8
}
func page_allocator() -> PageAllocator

// @arena  — bump pointer, reset all at once
struct ArenaAllocator ~> Allocator {
    func init(backing: *PageAllocator) -> ArenaAllocator
    alloc(a: @Self, size: usize, align: usize) -> !*u8
    free(a: @Self, ptr: *u8, size: usize, align: usize) -> void
    resize(a: @Self, ptr: *u8, old: usize, new: usize, align: usize) -> !*u8
    func reset(mut a: @Self) -> void
    func state(a: @Self) -> usize
    func restore(mut a: @Self, s: usize) -> void
    func deinit(mut a: @Self) -> void
}

// @fixed  — fixed buffer, no heap
struct FixedAllocator ~> Allocator {
    func init(buf: *u8, len: usize) -> FixedAllocator
    alloc(a: @Self, size: usize, align: usize) -> !*u8
    free(a: @Self, ptr: *u8, size: usize, align: usize) -> void
    resize(a: @Self, ptr: *u8, old: usize, new: usize, align: usize) -> !*u8
    func used(a: @Self) -> usize
    func available(a: @Self) -> usize
    func reset(mut a: @Self) -> void
}

// @stack(N)  — stack buffer, spills to fallback allocator
@Generic(N) struct StackAllocator ~> Allocator {
    func init(fallback: *PageAllocator) -> StackAllocator[N]
    alloc(a: @Self, size: usize, align: usize) -> !*u8
    free(a: @Self, ptr: *u8, size: usize, align: usize) -> void
    resize(a: @Self, ptr: *u8, old: usize, new: usize, align: usize) -> !*u8
    func used_fallback(a: @Self) -> usize
}

// @pool(T, N)  — typed slab allocator
@Generic(T, N) struct PoolAllocator ~> Allocator {
    func init() -> PoolAllocator[T, N]
    alloc(a: @Self, size: usize, align: usize) -> !*u8
    free(a: @Self, ptr: *u8, size: usize, align: usize) -> void
    resize(a: @Self, ptr: *u8, old: usize, new: usize, align: usize) -> !*u8
    func create(mut a: @Self) -> !*T
    func destroy(mut a: @Self, ptr: *T) -> void
    func capacity(a: @Self) -> usize
    func used(a: @Self) -> usize
    func clear(mut a: @Self) -> void
}

// @c  — libc malloc/free
struct CAllocator ~> Allocator {
    alloc(a: @Self, size: usize, align: usize) -> !*u8
    free(a: @Self, ptr: *u8, size: usize, align: usize) -> void
    resize(a: @Self, ptr: *u8, old: usize, new: usize, align: usize) -> !*u8
}
func c_allocator() -> CAllocator

// @debug(parent)  — wraps any allocator, detects leaks
struct DebugAllocator ~> Allocator {
    func init(parent: *PageAllocator) -> DebugAllocator
    alloc(a: @Self, size: usize, align: usize) -> !*u8
    free(a: @Self, ptr: *u8, size: usize, align: usize) -> void
    resize(a: @Self, ptr: *u8, old: usize, new: usize, align: usize) -> !*u8
    func check_leaks(a: @Self) -> bool
    func query_ptr(a: @Self, ptr: *u8) -> ?usize
    func deinit(mut a: @Self) -> void
}

// @log(parent)  — wraps any allocator, logs stats
struct LogAllocator ~> Allocator {
    func init(parent: *PageAllocator) -> LogAllocator
    alloc(a: @Self, size: usize, align: usize) -> !*u8
    free(a: @Self, ptr: *u8, size: usize, align: usize) -> void
    resize(a: @Self, ptr: *u8, old: usize, new: usize, align: usize) -> !*u8
    func stats(a: @Self) -> AllocStats
    func reset_stats(mut a: @Self) -> void
    func print_stats(a: @Self) -> void
    func deinit(mut a: @Self) -> void
}

// @failing(rate, parent)  — for testing, fails at given rate
struct FailingAllocator ~> Allocator {
    func init(rate: u32, parent: *PageAllocator) -> FailingAllocator
    alloc(a: @Self, size: usize, align: usize) -> !*u8
    free(a: @Self, ptr: *u8, size: usize, align: usize) -> void
    resize(a: @Self, ptr: *u8, old: usize, new: usize, align: usize) -> !*u8
    func reset_count(mut a: @Self) -> void
}
```

### Layout Struct

```
struct Layout {
    size:  usize,
    align: usize,

    func of(T: @Type) -> Layout
    func array(T: @Type, n: usize) -> Layout
    func pad_to_align(l: Layout) -> Layout
}
```

### AllocStats Struct

```
struct AllocStats {
    total_allocs:   usize,
    total_frees:    usize,
    total_bytes:    usize,
    peak_bytes:     usize,
    active_allocs:  usize,
}
```

### Raw Memory Functions

```
func mem_copy(dst: *u8, src: *u8, n: usize) -> void
func mem_move(dst: *u8, src: *u8, n: usize) -> void
func mem_set(dst: *u8, val: u8, n: usize) -> void
func mem_zero(dst: *u8, n: usize) -> void
func mem_eq(a: *u8, b: *u8, n: usize) -> bool
func align_up(addr: usize, align: usize) -> usize
func align_down(addr: usize, align: usize) -> usize
func is_aligned(addr: usize, align: usize) -> bool
```

### Errors

```
error MemError {
    OutOfMemory,
    InvalidLayout,
    InvalidAlign,
    NullPointer,
}
```

---

## `std.str` — String Slice Utilities

`str` is a UTF-8 byte slice, always stack-based. No heap allocation here.

```
use std.str
```

### Functions

```
func len(s: str) -> usize
func is_empty(s: str) -> bool
func as_bytes(s: str) -> *u8
func byte_at(s: str, i: usize) -> u8
func eq(a: str, b: str) -> bool
func starts_with(s: str, prefix: str) -> bool
func ends_with(s: str, suffix: str) -> bool
func contains(s: str, sub: str) -> bool
func find(s: str, sub: str) -> ?usize
func find_char(s: str, c: char) -> ?usize
func rfind(s: str, sub: str) -> ?usize
func rfind_char(s: str, c: char) -> ?usize
func slice(s: str, from: usize, to: usize) -> str
func slice_from(s: str, from: usize) -> str
func slice_to(s: str, to: usize) -> str
func trim(s: str) -> str
func trim_start(s: str) -> str
func trim_end(s: str) -> str
func count(s: str, sub: str) -> usize
func is_ascii(s: str) -> bool
func split_once(s: str, delim: str) -> ?SplitPair
func split(s: str, delim: str) -> SplitIter
func lines(s: str) -> LinesIter
func chars(s: str) -> CharIter
```

### Structs

```
struct SplitPair {
    left:  str,
    right: str,
}

struct SplitIter {
    func next(mut it: *SplitIter) -> ?str
    func has_next(it: @Self) -> bool
}

struct LinesIter {
    func next(mut it: @Self) -> ?str
    func has_next(it: @Self) -> bool
}

struct CharIter {
    func next(mut it: @Self) -> ?char
    func has_next(it: @Self) -> bool
}
```

### Errors

```
error StrError {
    InvalidUtf8,
    OutOfBounds,
    NotFound,
}
```

---

## `std.string` — Heap String & Builder

`string` is heap-allocated, mutable, owned.

```
use std.string
```

### String Struct

```
struct String {
    func new(alloc: *PageAllocator) -> String
    func from(s: str, alloc: *PageAllocator) -> MemError!String
    func with_capacity(cap: usize, alloc: *PageAllocator) -> MemError!String
    func push(mut s: @Self, c: char) -> MemError!void
    func push_str(mut s: @Self, other: str) -> MemError!void
    func pop(mut s: @Self) -> ?char
    func insert(mut s: @Self, idx: usize, other: str) -> MemError!void
    func remove(mut s: @Self, idx: usize) -> StrError!char
    func clear(mut s: @Self) -> void
    func truncate(mut s: @Self, new_len: usize) -> void
    func as_str(s: @Self) -> str
    func len(s: @Self) -> usize
    func cap(s: @Self) -> usize
    func is_empty(s: @Self) -> bool
    func clone(s: @Self, alloc: *PageAllocator) -> MemError!String
    func deinit(mut s: @Self) -> void
}
```

### StringBuilder Struct

```
struct StringBuilder {
    func new(alloc: *PageAllocator) -> StringBuilder
    func write(mut sb: @Self, s: str) -> MemError!void
    func write_char(mut sb: @Self, c: char) -> MemError!void
    func write_byte(mut sb: @Self, b: u8) -> MemError!void
    func finish(mut sb: @Self) -> MemError!String
    func as_str(sb: @Self) -> str
    func len(sb: @Self) -> usize
    func clear(mut sb: @Self) -> void
    func deinit(mut sb: @Self) -> void
}
```

### Errors

```
error StringError {
    OutOfMemory,
    InvalidUtf8,
    OutOfBounds,
}
```

---

## `std.fmt` — Formatting & Output

```
use std.fmt
```

### Functions

```
func print(s: str) -> void
func println(s: str) -> void
func eprint(s: str) -> void
func eprintln(s: str) -> void
func format(alloc: *PageAllocator, comptime fmt: str, args: .{...}) -> MemError!String
func format_buf(buf: *u8, buf_len: usize, comptime fmt: str, args: .{...}) -> usize
func sprint(mut sb: *StringBuilder, comptime fmt: str, args: .{...}) -> MemError!void
```

### Format Specifiers (`{}` syntax)

```
{}        display default
{d}       decimal integer
{x}       hex lowercase
{X}       hex uppercase
{b}       binary
{o}       octal
{f}       float default
{.N}      float N decimal places  e.g. {.2}
{>N}      right-align, pad N      e.g. {>10}
{<N}      left-align, pad N       e.g. {<10}
{p}       pointer address
{?}       optional — prints Some(...) or None
{!}       result  — prints Ok(...) or Err(...)
```

### Behaviours

```
behave Display {
    func display(a: @Self) -> str
}

behave Debug {
    func debug(a: @Self) -> str
}
```

---

## `std.io` — Reader / Writer

```
use std.io
```

### Behaviours

```
behave Reader {
    func read(mut r: @Self, buf: *u8, len: usize) -> IoError!usize
}

behave Writer {
    func write(mut w: @Self, buf: *u8, len: usize) -> IoError!usize
    func flush(mut w: @Self) -> IoError!void
}

behave Seeker {
    func seek(mut s: @Self, pos: SeekPos) -> IoError!usize
    func tell(mut s: @Self) -> IoError!usize
}
```

### SeekPos Union

```
union SeekPos {
    Start(u64),
    End(i64),
    Current(i64),
}
```

### BufReader Struct

```
@Generic(R) struct BufReader ~> Reader {
    func init(inner: R, buf_size: usize, alloc: *PageAllocator) -> MemError!BufReader[R]
    func read(mut r: @Self, buf: *u8, len: usize) -> IoError!usize
    func read_line(mut r: @Self, out: *StringBuilder) -> IoError!usize
    func read_until(mut r: @Self, delim: u8, out: *StringBuilder) -> IoError!usize
    func read_exact(mut r: @Self, buf: *u8, len: usize) -> IoError!void
    func deinit(mut r: @Self) -> void
}
```

### BufWriter Struct

```
@Generic(W) struct BufWriter ~> Writer {
    func init(inner: W, buf_size: usize, alloc: *PageAllocator) -> MemError!BufWriter[W]
    func write(mut w: @Self, buf: *u8, len: usize) -> IoError!usize
    func flush(mut w: @Self) -> IoError!void
    func deinit(mut w: @Self) -> void
}
```

### Standard Streams

```
func stdin() -> StdinReader     // ~> Reader
func stdout() -> StdoutWriter   // ~> Writer
func stderr() -> StderrWriter   // ~> Writer
```

### Errors

```
error IoError {
    UnexpectedEof,
    BrokenPipe,
    PermissionDenied,
    WouldBlock,
    Interrupted,
    InvalidInput,
    NotConnected,
    Other,
}
```

---

## `std.fs` — Files & Paths

```
use std.fs
```

### File Struct

```
struct File ~> Reader, Writer, Seeker {
    func open(path: str, flags: OpenFlags) -> FsError!File
    func create(path: str) -> FsError!File
    func read(mut f: @Self, buf: *u8, len: usize) -> IoError!usize
    func write(mut f: @Self, buf: *u8, len: usize) -> IoError!usize
    func seek(mut f: @Self, pos: SeekPos) -> IoError!usize
    func tell(mut f: @Self) -> IoError!usize
    func flush(mut f: @Self) -> IoError!void
    func size(f: @Self) -> FsError!u64
    func close(mut f: @Self) -> void
}
```

### Convenience Functions

```
func read_all(path: str, alloc: *PageAllocator) -> FsError!String
func write_all(path: str, data: str) -> FsError!void
func append_all(path: str, data: str) -> FsError!void
```

### OpenFlags Enum

```
enum OpenFlags: u8 {
    Read     = 1 << 0,
    Write    = 1 << 1,
    Create   = 1 << 2,
    Truncate = 1 << 3,
    Append   = 1 << 4,
}
```

### Path Struct

```
struct Path {
    raw: str,

    func from(s: str) -> Path
    func join(p: @Self, part: str, alloc: *PageAllocator) -> MemError!String
    func parent(p: @Self) -> ?str
    func file_name(p: @Self) -> ?str
    func extension(p: @Self) -> ?str
    func exists(p: @Self) -> bool
    func is_file(p: @Self) -> bool
    func is_dir(p: @Self) -> bool
    func as_str(p: @Self) -> str
}
```

### DirEntry & EntryKind

```
struct DirEntry {
    name: str,
    kind: EntryKind,
}

enum EntryKind {
    File,
    Dir,
    Symlink,
    Other,
}
```

### Directory Functions

```
func read_dir(path: str, alloc: *PageAllocator) -> FsError!vec[DirEntry]
func mkdir(path: str) -> FsError!void
func mkdir_all(path: str) -> FsError!void
func remove_file(path: str) -> FsError!void
func remove_dir(path: str) -> FsError!void
func remove_dir_all(path: str) -> FsError!void
func rename(from: str, to: str) -> FsError!void
func copy_file(from: str, to: str) -> FsError!u64
func cwd(alloc: *PageAllocator) -> FsError!String
```

### Errors

```
error FsError {
    NotFound,
    AlreadyExists,
    PermissionDenied,
    IsDirectory,
    NotDirectory,
    DirectoryNotEmpty,
    InvalidPath,
    TooManyHandles,
    Io,
}
```

---

## `std.os` — Process, Env, Args

```
use std.os
```

### Functions

```
func args(alloc: *PageAllocator) -> MemError!vec[String]
func env(key: str, alloc: *PageAllocator) -> ?String
func set_env(key: str, val: str) -> OsError!void
func unset_env(key: str) -> void
func exit(code: i32) -> noret
func abort() -> noret
func getpid() -> u32
func hostname(alloc: *PageAllocator) -> OsError!String
func sleep_ms(ms: u64) -> void
func clock_ms() -> u64
func clock_ns() -> u64
```

### Errors

```
error OsError {
    PermissionDenied,
    NotFound,
    InvalidArg,
    Other,
}
```

---

## `std.vec` — Growable Array

```
use std.vec
```

### Struct

```
@Generic(T) struct Vec {
    func new(alloc: *PageAllocator) -> Vec[T]
    func with_capacity(n: usize, alloc: *PageAllocator) -> MemError!Vec[T]
    func from_slice(s: *T, len: usize, alloc: *PageAllocator) -> MemError!Vec[T]

    func push(mut v: @Self, val: T) -> MemError!void
    func pop(mut v: @Self) -> ?T
    func insert(mut v: @Self, idx: usize, val: T) -> MemError!void
    func remove(mut v: @Self, idx: usize) -> VecError!T
    func swap_remove(mut v: @Self, idx: usize) -> VecError!T

    func get(v: @Self, idx: usize) -> ?T
    func get_ptr(mut v: @Self, idx: usize) -> ?*T
    func first(v: @Self) -> ?T
    func last(v: @Self) -> ?T

    func len(v: @Self) -> usize
    func cap(v: @Self) -> usize
    func is_empty(v: @Self) -> bool
    func clear(mut v: @Self) -> void
    func truncate(mut v: @Self, n: usize) -> void
    func reserve(mut v: @Self, n: usize) -> MemError!void
    func shrink(mut v: @Self) -> MemError!void

    func as_ptr(v: @Self) -> *T
    func iter(v: @Self) -> VecIter[T]
    func sort(mut v: @Self) -> void                                      // T ~> Ord
    func sort_by(mut v: @Self, f: func(T, T) -> Ordering) -> void
    func contains(v: @Self, val: T) -> bool                              // T ~> Eq
    func find(v: @Self, f: func(T) -> bool) -> ?usize
    func clone(v: @Self, alloc: *PageAllocator) -> MemError!Vec[T]      // T ~> Clone
    func deinit(mut v: @Self) -> void
}

struct VecIter[T] {
    func next(mut it: @Self) -> ?T
    func has_next(it: @Self) -> bool
    func peek(it: @Self) -> ?T
}
```

### Errors

```
error VecError {
    OutOfBounds,
    OutOfMemory,
    Empty,
}
```

---

## `std.map` — Hash Map

```
use std.map
```

Requires `K ~> Eq + Hash`.

### Struct

```
@Generic(K, V) struct Map {
    func new(alloc: *PageAllocator) -> Map[K, V]
    func with_capacity(n: usize, alloc: *PageAllocator) -> MemError!Map[K, V]

    func insert(mut m: @Self, key: K, val: V) -> MemError!?V
    func get(m: @Self, key: K) -> ?V
    func get_ptr(mut m: @Self, key: K) -> ?*V
    func remove(mut m: @Self, key: K) -> ?V
    func contains(m: @Self, key: K) -> bool
    func get_or_insert(mut m: @Self, key: K, default: V) -> MemError!*V

    func len(m: @Self) -> usize
    func is_empty(m: @Self) -> bool
    func clear(mut m: @Self) -> void

    func keys(m: @Self) -> KeyIter[K]
    func values(m: @Self) -> ValIter[V]
    func entries(m: @Self) -> EntryIter[K, V]

    func clone(m: @Self, alloc: *PageAllocator) -> MemError!Map[K, V]   // K ~> Clone, V ~> Clone
    func deinit(mut m: @Self) -> void
}

struct MapEntry[K, V] {
    key: K,
    val: V,
}

struct KeyIter[K] {
    func next(mut it: @Self) -> ?K
    func has_next(it: @Self) -> bool
}

struct ValIter[V] {
    func next(mut it: @Self) -> ?V
    func has_next(it: @Self) -> bool
}

struct EntryIter[K, V] {
    func next(mut it: @Self) -> ?MapEntry[K, V]
    func has_next(it: @Self) -> bool
}
```

### Errors

```
error MapError {
    OutOfMemory,
    KeyNotFound,
}
```

---

## `std.set` — Hash Set

```
use std.set
```

Requires `T ~> Eq + Hash`.

### Struct

```
@Generic(T) struct Set {
    func new(alloc: *PageAllocator) -> Set[T]
    func with_capacity(n: usize, alloc: *PageAllocator) -> MemError!Set[T]

    func insert(mut s: @Self, val: T) -> MemError!bool      // true = was new
    func remove(mut s: @Self, val: T) -> bool
    func contains(s: @Self, val: T) -> bool

    func len(s: @Self) -> usize
    func is_empty(s: @Self) -> bool
    func clear(mut s: @Self) -> void

    func iter(s: @Self) -> SetIter[T]

    func union_with(s: @Self, other: @Self, alloc: *PageAllocator) -> MemError!Set[T]
    func intersect(s: @Self, other: @Self, alloc: *PageAllocator) -> MemError!Set[T]
    func difference(s: @Self, other: @Self, alloc: *PageAllocator) -> MemError!Set[T]
    func is_subset(s: @Self, other: @Self) -> bool
    func is_superset(s: @Self, other: @Self) -> bool

    func clone(s: @Self, alloc: *PageAllocator) -> MemError!Set[T]     // T ~> Clone
    func deinit(mut s: @Self) -> void
}

struct SetIter[T] {
    func next(mut it: @Self) -> ?T
    func has_next(it: @Self) -> bool
}
```

### Errors

```
error SetError {
    OutOfMemory,
}
```

---

## `std.ring` — Fixed Ring Buffer

Stack-allocated when N is comptime. No allocator needed.

```
use std.ring
```

### Struct

```
@Generic(T, N) struct Ring {
    func new() -> Ring[T, N]
    func push(mut r: @Self, val: T) -> bool      // false = full, val dropped
    func pop(mut r: @Self) -> ?T
    func peek(r: @Self) -> ?T
    func peek_back(r: @Self) -> ?T
    func len(r: @Self) -> usize
    func cap(r: @Self) -> usize
    func is_empty(r: @Self) -> bool
    func is_full(r: @Self) -> bool
    func clear(mut r: @Self) -> void
    func iter(r: @Self) -> RingIter[T]
}

struct RingIter[T] {
    func next(mut it: @Self) -> ?T
    func has_next(it: @Self) -> bool
}
```

---

## `std.math` — Numeric & Float

```
use std.math
```

### Integer Functions

```
@Generic(T) func min(a: T, b: T) -> T
@Generic(T) func max(a: T, b: T) -> T
@Generic(T) func clamp(v: T, lo: T, hi: T) -> T
@Generic(T) func abs(v: T) -> T
func pow_int(base: i64, exp: u32) -> i64
func gcd(a: u64, b: u64) -> u64
func lcm(a: u64, b: u64) -> u64
func log2_floor(v: u64) -> u32
func log2_ceil(v: u64) -> u32
func next_power_of_two(v: u64) -> u64
func is_power_of_two(v: u64) -> bool
@Generic(T) func saturating_add(a: T, b: T) -> T
@Generic(T) func saturating_sub(a: T, b: T) -> T
@Generic(T) func saturating_mul(a: T, b: T) -> T
@Generic(T) func checked_add(a: T, b: T) -> ?T
@Generic(T) func checked_sub(a: T, b: T) -> ?T
@Generic(T) func checked_mul(a: T, b: T) -> ?T
@Generic(T) func wrapping_add(a: T, b: T) -> T
@Generic(T) func wrapping_sub(a: T, b: T) -> T
@Generic(T) func wrapping_mul(a: T, b: T) -> T
```

### Float Functions

```
func sqrt(x: f64) -> f64
func cbrt(x: f64) -> f64
func floor(x: f64) -> f64
func ceil(x: f64) -> f64
func round(x: f64) -> f64
func trunc(x: f64) -> f64
func fract(x: f64) -> f64
func abs_f(x: f64) -> f64
func pow(base: f64, exp: f64) -> f64
func exp(x: f64) -> f64
func exp2(x: f64) -> f64
func ln(x: f64) -> f64
func log(x: f64, base: f64) -> f64
func log2(x: f64) -> f64
func log10(x: f64) -> f64
func sin(x: f64) -> f64
func cos(x: f64) -> f64
func tan(x: f64) -> f64
func asin(x: f64) -> f64
func acos(x: f64) -> f64
func atan(x: f64) -> f64
func atan2(y: f64, x: f64) -> f64
func hypot(x: f64, y: f64) -> f64
func lerp(a: f64, b: f64, t: f64) -> f64
func is_nan(x: f64) -> bool
func is_inf(x: f64) -> bool
func is_finite(x: f64) -> bool
func copysign(mag: f64, sign: f64) -> f64
```

### Constants

```
const PI      : f64
const TAU     : f64
const E       : f64
const SQRT2   : f64
const LN2     : f64
const LN10    : f64
const INF     : f64
const NEG_INF : f64
const NAN     : f64
const I8_MIN  : i8
const I8_MAX  : i8
const I16_MIN : i16
const I16_MAX : i16
const I32_MIN : i32
const I32_MAX : i32
const I64_MIN : i64
const I64_MAX : i64
const U8_MAX  : u8
const U16_MAX : u16
const U32_MAX : u32
const U64_MAX : u64
const F32_MAX : f32
const F64_MAX : f64
const F32_MIN_POS : f32
const F64_MIN_POS : f64
const F32_EPSILON : f32
const F64_EPSILON : f64
```

---

## `std.bits` — Bit Manipulation

```
use std.bits
```

All operate on `u64`. Compiler may inline as intrinsics.

```
func count_ones(v: u64) -> u32
func count_zeros(v: u64) -> u32
func leading_zeros(v: u64) -> u32
func trailing_zeros(v: u64) -> u32
func leading_ones(v: u64) -> u32
func trailing_ones(v: u64) -> u32
func rotate_left(v: u64, n: u32) -> u64
func rotate_right(v: u64, n: u32) -> u64
func reverse_bits(v: u64) -> u64
func byte_swap(v: u64) -> u64
func bit_get(v: u64, pos: u32) -> bool
func bit_set(v: u64, pos: u32) -> u64
func bit_clear(v: u64, pos: u32) -> u64
func bit_toggle(v: u64, pos: u32) -> u64
func bit_range(v: u64, lo: u32, hi: u32) -> u64
func parity(v: u64) -> u32
```

---

## `std.ascii` — ASCII Char Utilities

```
use std.ascii
```

Operates on `u8` (raw byte).

```
func is_alpha(c: u8) -> bool
func is_digit(c: u8) -> bool
func is_alnum(c: u8) -> bool
func is_space(c: u8) -> bool
func is_upper(c: u8) -> bool
func is_lower(c: u8) -> bool
func is_print(c: u8) -> bool
func is_control(c: u8) -> bool
func is_punct(c: u8) -> bool
func is_hex_digit(c: u8) -> bool
func to_upper(c: u8) -> u8
func to_lower(c: u8) -> u8
func to_digit(c: u8) -> ?u8          // '7' → 7
func from_digit(d: u8) -> ?u8        // 7 → '7'
func hex_val(c: u8) -> ?u8           // 'f' or 'F' → 15
func from_hex_val(v: u8) -> ?u8      // 15 → 'f'
```

---

## `std.unicode` — UTF-8 / Char Utilities

```
use std.unicode
```

Operates on `char` (Unicode scalar) and `str`.

```
func encode_utf8(c: char, buf: *u8) -> usize          // writes up to 4 bytes, returns count
func decode_utf8(buf: *u8, len: usize) -> ?DecodeResult
func char_utf8_len(c: char) -> usize
func byte_count(s: str) -> usize
func char_count(s: str) -> usize
func nth_char(s: str, n: usize) -> ?char
func is_valid_utf8(buf: *u8, len: usize) -> bool
func is_alphabetic(c: char) -> bool
func is_numeric(c: char) -> bool
func is_alphanumeric(c: char) -> bool
func is_whitespace(c: char) -> bool
func is_uppercase(c: char) -> bool
func is_lowercase(c: char) -> bool
func to_uppercase(c: char) -> char
func to_lowercase(c: char) -> char
func codepoint(c: char) -> u32
func from_codepoint(v: u32) -> ?char
```

### Struct

```
struct DecodeResult {
    c:          char,
    bytes_used: usize,
}
```

---

## `std.parse` — Parse From `str`

```
use std.parse
```

### Functions

```
func parse_i8(s: str)   -> ParseError!i8
func parse_i16(s: str)  -> ParseError!i16
func parse_i32(s: str)  -> ParseError!i32
func parse_i64(s: str)  -> ParseError!i64
func parse_u8(s: str)   -> ParseError!u8
func parse_u16(s: str)  -> ParseError!u16
func parse_u32(s: str)  -> ParseError!u32
func parse_u64(s: str)  -> ParseError!u64
func parse_f32(s: str)  -> ParseError!f32
func parse_f64(s: str)  -> ParseError!f64
func parse_bool(s: str) -> ParseError!bool
func parse_char(s: str) -> ParseError!char
func parse_hex_u64(s: str) -> ParseError!u64
func parse_oct_u64(s: str) -> ParseError!u64
func parse_bin_u64(s: str) -> ParseError!u64
```

### Format To Buffer

```
func i64_to_buf(v: i64, buf: *u8) -> usize     // returns bytes written
func u64_to_buf(v: u64, buf: *u8) -> usize
func f64_to_buf(v: f64, decimals: u8, buf: *u8) -> usize
func u64_to_hex(v: u64, upper: bool, buf: *u8) -> usize
func u64_to_bin(v: u64, buf: *u8) -> usize
func u64_to_oct(v: u64, buf: *u8) -> usize
```

### Errors

```
error ParseError {
    Empty,
    InvalidDigit,
    Overflow,
    Underflow,
    InvalidFormat,
}
```

---

## `std.buf` — Byte Buffer / Cursor

```
use std.buf
```

### ByteBuf Struct

```
struct ByteBuf {
    func new(alloc: *PageAllocator) -> ByteBuf
    func with_capacity(n: usize, alloc: *PageAllocator) -> MemError!ByteBuf
    func from_bytes(src: *u8, len: usize, alloc: *PageAllocator) -> MemError!ByteBuf

    func write_u8(mut b: @Self, v: u8) -> MemError!void
    func write_u16_le(mut b: @Self, v: u16) -> MemError!void
    func write_u32_le(mut b: @Self, v: u32) -> MemError!void
    func write_u64_le(mut b: @Self, v: u64) -> MemError!void
    func write_u16_be(mut b: @Self, v: u16) -> MemError!void
    func write_u32_be(mut b: @Self, v: u32) -> MemError!void
    func write_u64_be(mut b: @Self, v: u64) -> MemError!void
    func write_i8(mut b: @Self, v: i8) -> MemError!void
    func write_i16_le(mut b: @Self, v: i16) -> MemError!void
    func write_i32_le(mut b: @Self, v: i32) -> MemError!void
    func write_i64_le(mut b: @Self, v: i64) -> MemError!void
    func write_bytes(mut b: @Self, src: *u8, len: usize) -> MemError!void

    func read_u8(mut b: @Self) -> BufError!u8
    func read_u16_le(mut b: @Self) -> BufError!u16
    func read_u32_le(mut b: @Self) -> BufError!u32
    func read_u64_le(mut b: @Self) -> BufError!u64
    func read_u16_be(mut b: @Self) -> BufError!u16
    func read_u32_be(mut b: @Self) -> BufError!u32
    func read_u64_be(mut b: @Self) -> BufError!u64
    func read_i8(mut b: @Self) -> BufError!i8
    func read_i16_le(mut b: @Self) -> BufError!i16
    func read_i32_le(mut b: @Self) -> BufError!i32
    func read_i64_le(mut b: @Self) -> BufError!i64
    func read_bytes(mut b: @Self, dst: *u8, len: usize) -> BufError!void

    func as_ptr(b: @Self) -> *u8
    func len(b: @Self) -> usize
    func pos(b: @Self) -> usize
    func remaining(b: @Self) -> usize
    func seek_to(mut b: @Self, pos: usize) -> void
    func reset(mut b: @Self) -> void
    func clear(mut b: @Self) -> void
    func deinit(mut b: @Self) -> void
}
```

### Errors

```
error BufError {
    UnexpectedEnd,
    OutOfMemory,
    InvalidPos,
}
```

---

## `std.hash` — Hashing

```
use std.hash
```

### Hasher Behaviour

```
behave Hasher {
    func write(mut h: @Self, data: *u8, len: usize) -> void
    func write_u8(mut h: @Self, v: u8) -> void
    func write_u16(mut h: @Self, v: u16) -> void
    func write_u32(mut h: @Self, v: u32) -> void
    func write_u64(mut h: @Self, v: u64) -> void
    func finish(h: @Self) -> u64
}
```

### FnvHasher Struct

```
struct FnvHasher ~> Hasher {
    func new() -> FnvHasher
    func write(mut h: @Self, data: *u8, len: usize) -> void
    func write_u8(mut h: @Self, v: u8) -> void
    func write_u16(mut h: @Self, v: u16) -> void
    func write_u32(mut h: @Self, v: u32) -> void
    func write_u64(mut h: @Self, v: u64) -> void
    func finish(h: @Self) -> u64
}
```

### SipHasher Struct

```
struct SipHasher ~> Hasher {
    func new(k0: u64, k1: u64) -> SipHasher
    func write(mut h: @Self, data: *u8, len: usize) -> void
    func write_u8(mut h: @Self, v: u8) -> void
    func write_u16(mut h: @Self, v: u16) -> void
    func write_u32(mut h: @Self, v: u32) -> void
    func write_u64(mut h: @Self, v: u64) -> void
    func finish(h: @Self) -> u64
}
```

### Convenience Functions

```
func hash_bytes_fnv(data: *u8, len: usize) -> u64
func hash_bytes_sip(data: *u8, len: usize, k0: u64, k1: u64) -> u64
func hash_str_fnv(s: str) -> u64
func hash_str_sip(s: str, k0: u64, k1: u64) -> u64
```

---

## `std.sync` — Atomics

```
use std.sync
```

Only atomics now. Mutex/channel deferred to after self-hosting (needs threads).

### Enum

```
enum MemOrder {
    Relaxed,
    Acquire,
    Release,
    AcqRel,
    SeqCst,
}
```

### Atomic Struct

```
@Generic(T) struct Atomic {
    func new(val: T) -> Atomic[T]
    func load(a: @Self, order: MemOrder) -> T
    func store(mut a: @Self, val: T, order: MemOrder) -> void
    func swap(mut a: @Self, val: T, order: MemOrder) -> T
    func compare_exchange(mut a: @Self, expected: T, desired: T, order: MemOrder) -> Result[T, T]
    func fetch_add(mut a: @Self, val: T, order: MemOrder) -> T
    func fetch_sub(mut a: @Self, val: T, order: MemOrder) -> T
    func fetch_and(mut a: @Self, val: T, order: MemOrder) -> T
    func fetch_or(mut a: @Self, val: T, order: MemOrder) -> T
    func fetch_xor(mut a: @Self, val: T, order: MemOrder) -> T
}
```

### Functions

```
func fence(order: MemOrder) -> void
func spin_hint() -> void
```

---

## `std.time` — Duration & Instant

```
use std.time
```

### Duration Struct

```
struct Duration {
    nanos: u64,

    func from_secs(s: u64) -> Duration
    func from_millis(ms: u64) -> Duration
    func from_micros(us: u64) -> Duration
    func from_nanos(ns: u64) -> Duration
    func as_secs(d: @Self) -> u64
    func as_millis(d: @Self) -> u64
    func as_micros(d: @Self) -> u64
    func as_nanos(d: @Self) -> u64
    func add(a: @Self, b: Duration) -> Duration
    func sub(a: @Self, b: Duration) -> Duration
    func zero() -> Duration
    func is_zero(d: @Self) -> bool
}
```

### Instant Struct

```
struct Instant {
    raw: u64,

    func now() -> Instant
    func elapsed(start: @Self) -> Duration
    func since(later: @Self, earlier: Instant) -> Duration
    func add(i: @Self, d: Duration) -> Instant
}
```

---

## `std.testing` — Test Runner & Assertions

```
use std.testing
```

### Test Struct

```
struct Test {
    @Generic(T, E) func eq(a: T, b: T) -> void             // T ~> Eq + Display
    @Generic(T, E) func neq(a: T, b: T) -> void
    @Generic(T)    func ok(r: !T) -> T
    @Generic(E)    func err(r: !void) -> void
    func is_true(v: bool) -> void
    func is_false(v: bool) -> void
    func near(a: f64, b: f64, eps: f64) -> void
    func skip(reason: str) -> noret
    func fail(msg: str) -> noret
}
```

### Test Attribute

```
// Mark a function as a test
// Compiler collects all #[test] functions and passes them to the runner
#[test]
func test_example() -> void {
    testing.eq(1 + 1, 2)
}
```

### Runner Function

```
func run(filter: ?str) -> void
func run_all() -> void
```

---

## `std.debug` — Assert, Panic, Trace

```
use std.debug
```

### Functions

```
func assert(cond: bool) -> void
func assert_msg(cond: bool, msg: str) -> void
func unreachable() -> noret
func panic(msg: str) -> noret
func panic_fmt(comptime fmt: str, args: .{...}) -> noret
func todo(msg: str) -> noret
func todo_fmt(comptime fmt: str, args: .{...}) -> noret
```

### Comptime Functions

```
const func static_assert(cond: bool) -> void
const func static_assert_msg(cond: bool, msg: str) -> void
```

### Trace — no-op in release

```
func trace(comptime fmt: str, args: .{...}) -> void
@Generic(T) func trace_val(label: str, val: T) -> T        // T ~> Debug — returns val unchanged
```

---

## Summary Table

| Module | What it gives you | Needed for |
|---|---|---|
| `std.core` | types, Option, Result, Ordering, core behaviours, builtins | always, implicit |
| `std.mem` | all allocators, Layout, raw mem ops | everything that allocates |
| `std.str` | str slice search, split, iter, trim | lexer, parser |
| `std.string` | heap String, StringBuilder | AST printing, error messages |
| `std.fmt` | print, format, Display/Debug | diagnostics, output |
| `std.io` | Reader/Writer behaviours, BufReader/BufWriter | file reading |
| `std.fs` | File, Path, dir ops | source file loading |
| `std.os` | args, env, exit, clock | CLI entrypoint |
| `std.vec` | Vec[T], VecIter | token list, AST node list |
| `std.map` | Map[K,V], iterators | symbol table, scope |
| `std.set` | Set[T], iterators | used-symbol tracking |
| `std.ring` | Ring[T,N] | compiler pipeline queues |
| `std.math` | int/float math, constants | constant folding, codegen |
| `std.bits` | bitwise ops | IR encoding, flags |
| `std.ascii` | ASCII byte classification | lexer |
| `std.unicode` | UTF-8 encode/decode, char ops | lexer, char literals |
| `std.parse` | str → numbers, format to buf | literal parsing |
| `std.buf` | ByteBuf, LE/BE read-write | binary output, object files |
| `std.hash` | FNV, SipHash, Hasher behave | symbol table hashing |
| `std.sync` | Atomic[T], MemOrder, fence | future parallel stages |
| `std.time` | Duration, Instant | compile-time diagnostics |
| `std.testing` | eq, ok, fail, runner | correctness |
| `std.debug` | assert, panic, trace, todo | every module |