# Razen Standard Library

**Design Principle:** Every module exists for one reason. No overlap. No magic. No runtime surprises. Enough to write the Razen compiler in Razen.

---

## Module Tree

```
std
├── core          ← language primitives, never imported explicitly (always in scope)
├── mem           ← memory, allocators, layout
├── str           ← string slices (stack)
├── string        ← heap strings, builder
├── fmt           ← formatting and printing
├── io            ← read/write abstraction
├── fs            ← files, paths
├── os            ← process, env, args, exit
├── collections
│   ├── vec       ← growable array
│   ├── map       ← hash map
│   ├── set       ← hash set
│   └── ring      ← ring buffer
├── math          ← numeric operations
├── bits          ← bitwise / bit manipulation
├── ascii         ← ascii char utilities
├── unicode       ← unicode / utf-8 utilities
├── parse         ← number / bool parsing from str
├── buf           ← byte buffers (reader/writer)
├── sync          ← atomics, mutex (future: threads)
├── time          ← clock, duration, timestamps
├── hash          ← hashing (fnv, siphash)
├── testing       ← test runner, assertions
└── debug         ← assert, panic, trace, unreachable
```

---

## `std.core` — Always in scope

These are never `use`d, they are always available.

**Types (built-in, compiler provides):**
```
i8, i16, i32, i64, i128, isize, int
u8, u16, u32, u64, u128, usize, uint
f32, f64, f128, float
bool, char, void, noret, any
str, string
?T, !T, Error!T
*T, &T
[T], [T; N]
vec[T], map{K,V}, set{T}
tuple .{...}
```

**Built-in functions (compiler intrinsics):**
```
@SizeOf(T)           → usize
@AlignOf(T)          → usize
@TypeOf(expr)        → type
@Self                → current type in impl/behave context
@Generic(T)          → generic marker
@Dyn                 → dynamic dispatch marker
@Type                → comptime type value
```

**Behaviours always in scope:**
```
behave Eq       { func eq(a: @Self, b: @Self) -> bool }
behave Ord      { func cmp(a: @Self, b: @Self) -> Ordering }
behave Hash     { func hash(a: @Self) -> u64 }
behave Clone    { func clone(a: @Self) -> Self }
behave Display  { func display(a: @Self) -> str }
behave Drop     { func drop(a: @Self) -> void }
```

**Core enums always in scope:**
```
@Generic(T) union Option  { Some(T), None }
@Generic(T, E) union Result { Ok(T), Err(E) }

enum Ordering { Less, Equal, Greater }
```

---

## `std.mem` — Memory & Allocators

**Structs:**
```
struct Allocator {
    func alloc(a: *Allocator, size: usize, align: usize) -> !*u8
    func free(a: *Allocator, ptr: *u8, size: usize, align: usize) -> void
    func resize(a: *Allocator, ptr: *u8, old_size: usize, new_size: usize, align: usize) -> !*u8
}

struct Layout {
    size:  usize,
    align: usize,

    func of(T: @Type) -> Layout
    func array(T: @Type, n: usize) -> Layout
    func pad_to_align(l: *Layout) -> Layout
}
```

**Allocator Handles (from builtins, wrapped):**
```
@page          → PageAllocator     (mmap / VirtualAlloc)
@arena         → ArenaAllocator    (bump pointer)
@fixed         → FixedAllocator    (fixed buffer)
@stack(N)      → StackAllocator    (stack buffer, fallback)
@pool(T, N)    → PoolAllocator     (typed slab)
@c             → CAllocator        (malloc/free)
@debug(A)      → DebugAllocator    (wraps any, leak detection)
@log(A)        → LogAllocator      (wraps any, logs allocs)
@failing(r, A) → FailingAllocator  (test allocator, fails at rate r)
```

**Functions:**
```
func copy(dst: *u8, src: *u8, n: usize) -> void
func move(dst: *u8, src: *u8, n: usize) -> void     // handles overlap
func set(dst: *u8, val: u8, n: usize) -> void
func zero(dst: *u8, n: usize) -> void
func eq(a: *u8, b: *u8, n: usize) -> bool
func swap[T](a: *T, b: *T) -> void
func align_up(addr: usize, align: usize) -> usize
func align_down(addr: usize, align: usize) -> usize
func is_aligned(addr: usize, align: usize) -> bool
```

**Errors:**
```
error MemError {
    OutOfMemory,
    InvalidLayout,
    AllocFailed,
}
```

---

## `std.str` — String Slices (borrowed, UTF-8)

`str` is a borrowed UTF-8 byte slice — lives on stack or points into memory.

**Functions:**
```
func len(s: str) -> usize
func is_empty(s: str) -> bool
func bytes(s: str) -> &[u8]
func chars(s: str) -> CharIter
func eq(a: str, b: str) -> bool
func starts_with(s: str, prefix: str) -> bool
func ends_with(s: str, suffix: str) -> bool
func contains(s: str, sub: str) -> bool
func find(s: str, sub: str) -> ?usize
func find_char(s: str, c: char) -> ?usize
func slice(s: str, from: usize, to: usize) -> str
func split(s: str, delim: str) -> SplitIter
func split_once(s: str, delim: str) -> ?(str, str)
func trim(s: str) -> str
func trim_start(s: str) -> str
func trim_end(s: str) -> str
func to_upper(s: str, alloc: &Allocator) -> !string
func to_lower(s: str, alloc: &Allocator) -> !string
func repeat(s: str, n: usize, alloc: &Allocator) -> !string
func replace(s: str, from: str, to: str, alloc: &Allocator) -> !string
func count(s: str, sub: str) -> usize
func is_ascii(s: str) -> bool
func as_ptr(s: str) -> *u8
```

**Structs:**
```
struct SplitIter { ... }       // implements Iterator[str]
struct CharIter  { ... }       // implements Iterator[char]
```

**Errors:**
```
error StrError {
    InvalidUtf8,
    OutOfBounds,
    NotFound,
}
```

---

## `std.string` — Heap String & Builder

`string` is a heap-allocated, mutable, owned UTF-8 string.

**Struct:**
```
struct string {
    func new(alloc: &Allocator) -> string
    func from(s: str, alloc: &Allocator) -> !string
    func with_capacity(cap: usize, alloc: &Allocator) -> !string

    func push(self: mut &string, c: char) -> !void
    func push_str(self: mut &string, s: str) -> !void
    func pop(self: mut &string) -> ?char
    func insert(self: mut &string, idx: usize, s: str) -> !void
    func remove(self: mut &string, idx: usize) -> !char
    func clear(self: mut &string) -> void
    func truncate(self: mut &string, new_len: usize) -> void

    func as_str(self: &string) -> str
    func len(self: &string) -> usize
    func cap(self: &string) -> usize
    func is_empty(self: &string) -> bool

    func clone(self: &string, alloc: &Allocator) -> !string
    func deinit(self: mut &string) -> void
}

struct StringBuilder {
    func new(alloc: &Allocator) -> StringBuilder
    func write(self: mut &StringBuilder, s: str) -> !void
    func write_char(self: mut &StringBuilder, c: char) -> !void
    func write_fmt(self: mut &StringBuilder, ...) -> !void
    func finish(self: mut &StringBuilder) -> !string
    func as_str(self: &StringBuilder) -> str
    func len(self: &StringBuilder) -> usize
    func clear(self: mut &StringBuilder) -> void
    func deinit(self: mut &StringBuilder) -> void
}
```

**Errors:**
```
error StringError {
    OutOfMemory,
    InvalidUtf8,
    OutOfBounds,
}
```

---

## `std.fmt` — Formatting & Output

**Functions:**
```
func print(s: str) -> void
func println(s: str) -> void
func eprint(s: str) -> void
func eprintln(s: str) -> void

func format(alloc: &Allocator, comptime fmt: str, args: .{...}) -> !string
func format_buf(buf: mut &[u8], comptime fmt: str, args: .{...}) -> !usize
func sprint(buf: mut &StringBuilder, comptime fmt: str, args: .{...}) -> !void
```

**Format Spec (`{}` syntax):**
```
{}       → Display default
{d}      → decimal integer
{x}      → hex lowercase
{X}      → hex uppercase
{b}      → binary
{o}      → octal
{f}      → float default
{.N}     → float N decimal places
{>N}     → right-pad N chars
{<N}     → left-pad N chars
{p}      → pointer address
```

**Behaviours:**
```
behave Display {
    func fmt(self: @Self, buf: mut &StringBuilder) -> !void
}

behave Debug {
    func dbg(self: @Self, buf: mut &StringBuilder) -> !void
}
```

---

## `std.io` — Read / Write Abstraction

**Behaviours:**
```
behave Reader {
    func read(self: mut @Self, buf: mut &[u8]) -> !usize
}

behave Writer {
    func write(self: mut @Self, buf: &[u8]) -> !usize
    func flush(self: mut @Self) -> !void
}

behave Seeker {
    func seek(self: mut @Self, pos: SeekPos) -> !usize
    func tell(self: mut @Self) -> !usize
}
```

**Enums:**
```
union SeekPos {
    Start(u64),
    End(i64),
    Current(i64),
}
```

**Structs:**
```
struct BufReader[R ~> Reader] {
    func new(inner: R, buf_size: usize, alloc: &Allocator) -> !BufReader[R]
    func read_line(self: mut @Self, out: mut &StringBuilder) -> !usize
    func read_until(self: mut @Self, delim: u8, out: mut &[u8]) -> !usize
    func read_exact(self: mut @Self, buf: mut &[u8]) -> !void
    func deinit(self: mut @Self) -> void
}

struct BufWriter[W ~> Writer] {
    func new(inner: W, buf_size: usize, alloc: &Allocator) -> !BufWriter[W]
    func flush(self: mut @Self) -> !void
    func deinit(self: mut @Self) -> void
}
```

**Standard streams (global):**
```
std.io.stdin   → Reader handle
std.io.stdout  → Writer handle
std.io.stderr  → Writer handle
```

**Errors:**
```
error IoError {
    UnexpectedEof,
    BrokenPipe,
    PermissionDied,
    WouldBlock,
    Interrupted,
    InvalidInput,
    NotConnected,
    Other,
}
```

---

## `std.fs` — Files & Paths

**Structs:**
```
struct File {
    func open(path: str, flags: OpenFlags) -> !File
    func create(path: str) -> !File
    func read(self: mut &File, buf: mut &[u8]) -> !usize
    func write(self: mut &File, buf: &[u8]) -> !usize
    func seek(self: mut &File, pos: SeekPos) -> !usize
    func tell(self: mut &File) -> !usize
    func flush(self: mut &File) -> !void
    func size(self: &File) -> !u64
    func close(self: mut &File) -> void     // or defer
    func read_all(path: str, alloc: &Allocator) -> !string
    func write_all(path: str, data: str) -> !void
}

struct Path {
    func from(s: str) -> Path
    func join(self: &Path, part: str, alloc: &Allocator) -> !string
    func parent(self: &Path) -> ?str
    func file_name(self: &Path) -> ?str
    func extension(self: &Path) -> ?str
    func exists(self: &Path) -> bool
    func is_file(self: &Path) -> bool
    func is_dir(self: &Path) -> bool
    func as_str(self: &Path) -> str
}

struct DirEntry {
    name: str,
    kind: EntryKind,
}

union EntryKind { File, Dir, Symlink, Other }

enum OpenFlags: u8 {
    Read     = 1 << 0,
    Write    = 1 << 1,
    Create   = 1 << 2,
    Truncate = 1 << 3,
    Append   = 1 << 4,
}
```

**Functions:**
```
func read_dir(path: str, alloc: &Allocator) -> !vec[DirEntry]
func mkdir(path: str) -> !void
func mkdir_all(path: str) -> !void
func remove_file(path: str) -> !void
func remove_dir(path: str) -> !void
func rename(from: str, to: str) -> !void
func copy(from: str, to: str) -> !u64
func cwd(alloc: &Allocator) -> !string
```

**Errors:**
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

**Functions:**
```
func args(alloc: &Allocator) -> !vec[string]
func env(key: str, alloc: &Allocator) -> ?string
func set_env(key: str, val: str) -> !void
func exit(code: i32) -> noret
func abort() -> noret
func getpid() -> u32
func hostname(alloc: &Allocator) -> !string
func sleep_ms(ms: u64) -> void
func clock_ms() -> u64
func clock_ns() -> u64
```

---

## `std.collections.vec` — Growable Array

```
struct vec[T] {
    func new(alloc: &Allocator) -> vec[T]
    func with_capacity(n: usize, alloc: &Allocator) -> !vec[T]
    func from_slice(s: &[T], alloc: &Allocator) -> !vec[T]

    func push(self: mut &vec[T], val: T) -> !void
    func pop(self: mut &vec[T]) -> ?T
    func insert(self: mut &vec[T], idx: usize, val: T) -> !void
    func remove(self: mut &vec[T], idx: usize) -> !T
    func swap_remove(self: mut &vec[T], idx: usize) -> !T

    func get(self: &vec[T], idx: usize) -> ?&T
    func get_mut(self: mut &vec[T], idx: usize) -> ?mut &T
    func first(self: &vec[T]) -> ?&T
    func last(self: &vec[T]) -> ?&T

    func len(self: &vec[T]) -> usize
    func cap(self: &vec[T]) -> usize
    func is_empty(self: &vec[T]) -> bool
    func clear(self: mut &vec[T]) -> void
    func truncate(self: mut &vec[T], n: usize) -> void
    func reserve(self: mut &vec[T], n: usize) -> !void
    func shrink(self: mut &vec[T]) -> !void

    func as_slice(self: &vec[T]) -> &[T]
    func iter(self: &vec[T]) -> SliceIter[T]
    func sort(self: mut &vec[T]) -> void         // requires T ~> Ord
    func sort_by(self: mut &vec[T], f: func(&T, &T) -> Ordering) -> void
    func contains(self: &vec[T], val: &T) -> bool  // requires T ~> Eq
    func find(self: &vec[T], f: func(&T) -> bool) -> ?usize
    func clone(self: &vec[T], alloc: &Allocator) -> !vec[T]  // requires T ~> Clone
    func deinit(self: mut &vec[T]) -> void
}
```

---

## `std.collections.map` — Hash Map

```
struct map{K, V} {
    func new(alloc: &Allocator) -> map{K, V}
    func with_capacity(n: usize, alloc: &Allocator) -> !map{K, V}

    func insert(self: mut &map{K,V}, key: K, val: V) -> !?V
    func get(self: &map{K,V}, key: &K) -> ?&V
    func get_mut(self: mut &map{K,V}, key: &K) -> ?mut &V
    func remove(self: mut &map{K,V}, key: &K) -> ?V
    func contains(self: &map{K,V}, key: &K) -> bool
    func get_or_insert(self: mut &map{K,V}, key: K, default: V) -> !mut &V

    func len(self: &map{K,V}) -> usize
    func is_empty(self: &map{K,V}) -> bool
    func clear(self: mut &map{K,V}) -> void

    func keys(self: &map{K,V}) -> KeyIter[K]
    func values(self: &map{K,V}) -> ValIter[V]
    func entries(self: &map{K,V}) -> EntryIter[K,V]

    func clone(self: &map{K,V}, alloc: &Allocator) -> !map{K,V}
    func deinit(self: mut &map{K,V}) -> void
}
```

Requires `K ~> Eq + Hash`.

---

## `std.collections.set` — Hash Set

```
struct set{T} {
    func new(alloc: &Allocator) -> set{T}
    func insert(self: mut &set{T}, val: T) -> !bool   // true = was new
    func remove(self: mut &set{T}, val: &T) -> bool
    func contains(self: &set{T}, val: &T) -> bool
    func len(self: &set{T}) -> usize
    func is_empty(self: &set{T}) -> bool
    func clear(self: mut &set{T}) -> void
    func iter(self: &set{T}) -> SetIter[T]
    func union_with(self: &set{T}, other: &set{T}, alloc: &Allocator) -> !set{T}
    func intersect(self: &set{T}, other: &set{T}, alloc: &Allocator) -> !set{T}
    func difference(self: &set{T}, other: &set{T}, alloc: &Allocator) -> !set{T}
    func deinit(self: mut &set{T}) -> void
}
```

---

## `std.collections.ring` — Ring Buffer

```
struct ring[T; N] {
    func new() -> ring[T; N]
    func push(self: mut &ring[T; N], val: T) -> bool    // false = full
    func pop(self: mut &ring[T; N]) -> ?T
    func peek(self: &ring[T; N]) -> ?&T
    func len(self: &ring[T; N]) -> usize
    func cap(self: &ring[T; N]) -> usize
    func is_empty(self: &ring[T; N]) -> bool
    func is_full(self: &ring[T; N]) -> bool
    func clear(self: mut &ring[T; N]) -> void
    func iter(self: &ring[T; N]) -> RingIter[T]
}
```

Stack-allocated when N is comptime. No alloc needed.

---

## `std.math` — Numeric Operations

**Integer functions:**
```
func min[T](a: T, b: T) -> T
func max[T](a: T, b: T) -> T
func clamp[T](v: T, lo: T, hi: T) -> T
func abs[T](v: T) -> T
func pow_int(base: i64, exp: u32) -> i64
func gcd(a: u64, b: u64) -> u64
func lcm(a: u64, b: u64) -> u64
func log2_floor(v: u64) -> u32
func log2_ceil(v: u64) -> u32
func next_power_of_two(v: u64) -> u64
func is_power_of_two(v: u64) -> bool
func saturating_add(a: T, b: T) -> T
func saturating_sub(a: T, b: T) -> T
func checked_add(a: T, b: T) -> ?T
func checked_sub(a: T, b: T) -> ?T
func checked_mul(a: T, b: T) -> ?T
func wrapping_add(a: T, b: T) -> T
func wrapping_sub(a: T, b: T) -> T
```

**Float functions:**
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
func is_nan(x: f64) -> bool
func is_inf(x: f64) -> bool
func is_finite(x: f64) -> bool
```

**Constants:**
```
const PI    : f64
const E     : f64
const TAU   : f64
const SQRT2 : f64
const LN2   : f64
const LN10  : f64
const INF   : f64
const NEG_INF : f64
const NAN   : f64
```

---

## `std.bits` — Bit Manipulation

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
func reverse_bytes(v: u64) -> u64       // bswap
func bit_get(v: u64, pos: u32) -> bool
func bit_set(v: u64, pos: u32) -> u64
func bit_clear(v: u64, pos: u32) -> u64
func bit_toggle(v: u64, pos: u32) -> u64
func bit_range(v: u64, lo: u32, hi: u32) -> u64
```

---

## `std.ascii` — ASCII Character Utilities

```
func is_alpha(c: u8) -> bool
func is_digit(c: u8) -> bool
func is_alnum(c: u8) -> bool
func is_space(c: u8) -> bool
func is_upper(c: u8) -> bool
func is_lower(c: u8) -> bool
func is_print(c: u8) -> bool
func is_punct(c: u8) -> bool
func to_upper(c: u8) -> u8
func to_lower(c: u8) -> u8
func to_digit(c: u8) -> ?u8        // '7' → 7
func from_digit(d: u8) -> ?u8      // 7 → '7'
func is_hex_digit(c: u8) -> bool
func hex_val(c: u8) -> ?u8         // 'f' → 15
```

---

## `std.unicode` — UTF-8 / Unicode

```
func encode_utf8(c: char, buf: mut &[u8; 4]) -> usize
func decode_utf8(buf: &[u8]) -> ?(char, usize)   // (char, bytes consumed)
func char_len_utf8(c: char) -> usize
func byte_len(s: str) -> usize
func char_count(s: str) -> usize
func nth_char(s: str, n: usize) -> ?char
func is_valid_utf8(buf: &[u8]) -> bool
func is_alphanumeric(c: char) -> bool
func is_whitespace(c: char) -> bool
func is_alphabetic(c: char) -> bool
func is_numeric(c: char) -> bool
func to_uppercase(c: char) -> char
func to_lowercase(c: char) -> char
func codepoint(c: char) -> u32
func from_codepoint(v: u32) -> ?char
```

---

## `std.parse` — Parsing from `str`

```
func parse_i64(s: str) -> !i64
func parse_u64(s: str) -> !u64
func parse_i32(s: str) -> !i32
func parse_u32(s: str) -> !u32
func parse_f64(s: str) -> !f64
func parse_f32(s: str) -> !f32
func parse_bool(s: str) -> !bool
func parse_char(s: str) -> !char
func parse_hex_u64(s: str) -> !u64
func parse_oct_u64(s: str) -> !u64
func parse_bin_u64(s: str) -> !u64
func int_to_str(v: i64, buf: mut &[u8; 32]) -> str
func uint_to_str(v: u64, buf: mut &[u8; 32]) -> str
func float_to_str(v: f64, decimals: u8, buf: mut &[u8; 64]) -> str
```

**Errors:**
```
error ParseError {
    Empty,
    InvalidDigit,
    Overflow,
    InvalidFormat,
}
```

---

## `std.buf` — Byte Buffer / Cursor

```
struct ByteBuf {
    func new(alloc: &Allocator) -> ByteBuf
    func with_capacity(n: usize, alloc: &Allocator) -> !ByteBuf
    func from_slice(s: &[u8], alloc: &Allocator) -> !ByteBuf

    func write_u8(self: mut @Self, v: u8) -> !void
    func write_u16_le(self: mut @Self, v: u16) -> !void
    func write_u32_le(self: mut @Self, v: u32) -> !void
    func write_u64_le(self: mut @Self, v: u64) -> !void
    func write_u16_be(self: mut @Self, v: u16) -> !void
    func write_u32_be(self: mut @Self, v: u32) -> !void
    func write_u64_be(self: mut @Self, v: u64) -> !void
    func write_bytes(self: mut @Self, s: &[u8]) -> !void

    func read_u8(self: mut @Self) -> !u8
    func read_u16_le(self: mut @Self) -> !u16
    func read_u32_le(self: mut @Self) -> !u32
    func read_u64_le(self: mut @Self) -> !u64
    func read_bytes(self: mut @Self, n: usize) -> !&[u8]

    func as_slice(self: @Self) -> &[u8]
    func len(self: @Self) -> usize
    func pos(self: @Self) -> usize
    func remaining(self: @Self) -> usize
    func reset(self: mut @Self) -> void
    func clear(self: mut @Self) -> void
    func deinit(self: mut @Self) -> void
}
```

---

## `std.hash` — Hashing

```
behave Hasher {
    func write(self: mut @Self, data: &[u8]) -> void
    func finish(self: @Self) -> u64
}

struct FnvHasher {
    func new() -> FnvHasher
    func write(self: mut @Self, data: &[u8]) -> void
    func finish(self: @Self) -> u64
}

struct SipHasher {
    func new(k0: u64, k1: u64) -> SipHasher
    func write(self: mut @Self, data: &[u8]) -> void
    func finish(self: @Self) -> u64
}

func hash_bytes_fnv(data: &[u8]) -> u64
func hash_bytes_sip(data: &[u8], k0: u64, k1: u64) -> u64
func hash_str(s: str) -> u64
```

---

## `std.sync` — Atomics & Primitives

```
enum MemOrder { Relaxed, Acquire, Release, AcqRel, SeqCst }

struct Atomic[T] {
    func new(val: T) -> Atomic[T]
    func load(self: @Self, order: MemOrder) -> T
    func store(self: mut @Self, val: T, order: MemOrder) -> void
    func swap(self: mut @Self, val: T, order: MemOrder) -> T
    func compare_exchange(self: mut @Self, expected: T, desired: T, order: MemOrder) -> Result[T, T]
    func fetch_add(self: mut @Self, val: T, order: MemOrder) -> T
    func fetch_sub(self: mut @Self, val: T, order: MemOrder) -> T
    func fetch_and(self: mut @Self, val: T, order: MemOrder) -> T
    func fetch_or(self: mut @Self, val: T, order: MemOrder) -> T
    func fetch_xor(self: mut @Self, val: T, order: MemOrder) -> T
}

func fence(order: MemOrder) -> void
func spin_hint() -> void     // CPU pause hint for spin loops
```

*Mutex, RwLock, Channel — deferred to after self-hosting (needs threads).*

---

## `std.time` — Time & Duration

```
struct Duration {
    nanos: u64,

    func from_secs(s: u64) -> Duration
    func from_millis(ms: u64) -> Duration
    func from_micros(us: u64) -> Duration
    func from_nanos(ns: u64) -> Duration
    func as_secs(self: @Self) -> u64
    func as_millis(self: @Self) -> u64
    func as_micros(self: @Self) -> u64
    func as_nanos(self: @Self) -> u64
    func add(a: Duration, b: Duration) -> Duration
    func sub(a: Duration, b: Duration) -> Duration
    func zero() -> Duration
}

struct Instant {
    func now() -> Instant
    func elapsed(self: &Instant) -> Duration
    func since(self: &Instant, earlier: &Instant) -> Duration
    func add(self: &Instant, d: Duration) -> Instant
}
```

---

## `std.testing` — Test Runner

```
// Usage inside any module:
#[test]
func test_add() -> void {
    testing.eq(add(2, 3), 5)
    testing.neq(add(1, 1), 3)
}

struct TestCtx {
    func eq[T ~> Eq + Display](a: T, b: T) -> void
    func neq[T ~> Eq + Display](a: T, b: T) -> void
    func ok[T](r: !T) -> T
    func err[T](r: !T) -> void
    func is_true(v: bool) -> void
    func is_false(v: bool) -> void
    func panic_with(msg: str) -> void
    func skip(reason: str) -> void
}

func run_tests(filter: ?str) -> void
```

---

## `std.debug` — Assert, Panic, Trace

```
func assert(cond: bool) -> void
func assert_msg(cond: bool, msg: str) -> void
func unreachable() -> noret
func panic(msg: str) -> noret
func panic_fmt(comptime fmt: str, args: .{...}) -> noret
func todo(msg: str) -> noret

// Compile-time only
const func static_assert(cond: bool) -> void
const func static_assert_msg(cond: bool, msg: str) -> void

// Debug trace (no-op in release builds)
func trace(comptime fmt: str, args: .{...}) -> void
func trace_val[T ~> Debug](label: str, val: T) -> T   // returns val unchanged
```

---

## Summary Table

| Module | Purpose | Self-host need |
|---|---|---|
| `std.core` | types, Option, Result, Ordering, core behaviours | always |
| `std.mem` | allocators, layout, raw memory ops | always |
| `std.str` | string slices, split, search, iter | always |
| `std.string` | heap strings, builder | always |
| `std.fmt` | print, format, Display/Debug | always |
| `std.io` | reader/writer behaviour, buffered I/O | always |
| `std.fs` | files, paths, directory | always |
| `std.os` | args, env, exit, clock | always |
| `std.collections.vec` | growable list | always |
| `std.collections.map` | hash map | always |
| `std.collections.set` | hash set | lexer/semantic |
| `std.collections.ring` | ring buffer | parser/pipeline |
| `std.math` | numeric math | codegen |
| `std.bits` | bit manipulation | codegen/encoding |
| `std.ascii` | ascii char ops | lexer |
| `std.unicode` | UTF-8 / char ops | lexer |
| `std.parse` | str → number/bool | parser |
| `std.buf` | byte buffer, LE/BE read-write | binary/IR emit |
| `std.hash` | FNV, SipHash | symbol tables |
| `std.sync` | atomics | future threads |
| `std.time` | duration, instant | diagnostics |
| `std.testing` | test framework | correctness |
| `std.debug` | assert, panic, trace | always |

---