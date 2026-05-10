// sample3.zig — Critical-bug coverage samples
// Tests the 5 critical fixes:
//   C1 — defer runs AFTER the function body (LIFO)
//   C2 — try/catch expands to ErrorUnion temp-var pattern
//   C3 — union emits a tagged-union struct (not a bare C union)
//   C4 — @Self resolves to the struct's own C type name
//   C5 — `use std.io` emits #include "std_io.h" (dots → underscores)

/// C1: defer ordering — two defers must appear in reverse order at end of function
pub const DEFER_ORDER =
    \\func setup() -> void {
    \\    defer std.io.print("last")
    \\    defer std.io.print("first")
    \\    std.io.print("body")
    \\}
;

/// C1: defer before return — defers must fire before every ret
pub const DEFER_BEFORE_RETURN =
    \\func open_file(ok: bool) -> void {
    \\    defer std.io.print("cleanup")
    \\    if ok {
    \\        ret
    \\    }
    \\    std.io.print("done")
    \\}
;

/// C2: try/catch expansion — must emit ErrorUnion temp var, error check, then value extract
pub const TRY_CATCH_BASIC =
    \\use std.io
    \\ext func bind(port: int) -> int
    \\func run() -> void {
    \\    res := try bind(8080) catch |e| { ret }
    \\    std.io.print(res)
    \\}
;

/// C3: tagged union — must emit struct { enum tag; union data; } not a bare union
pub const TAGGED_UNION =
    \\union Value {
    \\    Int: i32,
    \\    Float: f32,
    \\    Text: str,
    \\}
;

/// C3: tagged union with struct variant
pub const TAGGED_UNION_STRUCT_VARIANT =
    \\union Expr {
    \\    Num: i32,
    \\    Binary { left: i32, right: i32, op: str },
    \\}
;

/// C4: @Self in struct method emits the struct's own type, not void*
pub const SELF_IN_BEHAVE =
    \\behave Printable {
    \\    func print_self(self: @Self) -> void
    \\}
;

/// C5: use path dots become underscores in the #include
pub const USE_PATH =
    \\use std.io
    \\use std.net.tcp
    \\func main() -> void {
    \\    std.io.print("hello")
    \\}
;

/// Combined: struct + match + defer + const
pub const STRUCT_MATCH_DEFER =
    \\struct Counter {
    \\    value: i32,
    \\}
    \\
    \\enum Dir { Up, Down }
    \\
    \\func step(mut c: Counter, d: Dir) -> void {
    \\    defer std.io.print("step done")
    \\    match d {
    \\        Dir.Up   => c.value += 1,
    \\        Dir.Down => c.value -= 1
    \\    }
    \\}
;
