// sample3.zig — Critical-bug coverage samples
// Uses correct std API per std_new.md:
//   std.fmt.print(s: str)     — print without newline
//   std.fmt.println(s: str)   — print with newline
//   std.fmt.eprint(s: str)    — stderr without newline
//   std.fmt.eprintln(s: str)  — stderr with newline
//   std.debug.assert(cond)    — assertion
//   std.debug.panic(msg)      — panic
//   std.os.exit(code)         — exit process
//   std.os.clock_ms()         — timestamp

// C1: defer ordering — two defers must fire in LIFO at end of function
pub const DEFER_ORDER =
    \\use std.fmt
    \\func setup() -> void {
    \\    defer std.fmt.println("last")
    \\    defer std.fmt.println("first")
    \\    std.fmt.println("body")
    \\}
;

// C1: defer before return — cleanup must fire before every early ret
pub const DEFER_BEFORE_RETURN =
    \\use std.fmt
    \\func open_file(ok: bool) -> void {
    \\    defer std.fmt.println("cleanup")
    \\    if ok {
    \\        ret
    \\    }
    \\    std.fmt.println("done")
    \\}
;

// C2: try/catch — must emit ErrorUnion temp-var pattern, not RAZEN_TRY macro
pub const TRY_CATCH_BASIC =
    \\use std.fmt
    \\ext func bind(port: int) -> int
    \\func run() -> void {
    \\    res := try bind(8080) catch |e| { ret }
    \\    std.fmt.println(res)
    \\}
;

// C3: tagged union — must emit struct { enum tag; union data; }
pub const TAGGED_UNION =
    \\union Value {
    \\    Int: i32,
    \\    Float: f32,
    \\    Text: str,
    \\}
;

// C3: tagged union with struct variant
pub const TAGGED_UNION_STRUCT_VARIANT =
    \\union Expr {
    \\    Num: i32,
    \\    Binary { left: i32, right: i32, op: str },
    \\}
;

// C4: @Self in behave method must emit the behave name, not void*
pub const SELF_IN_BEHAVE =
    \\behave Printable {
    \\    func print_self(self: @Self) -> void
    \\}
;

// C5: use path dots must become underscores in #include
pub const USE_PATH =
    \\use std.fmt
    \\use std.os
    \\use std.debug
    \\func main() -> void {
    \\    std.fmt.println("hello")
    \\    std.os.exit(0)
    \\}
;

// std.debug usage sample
pub const DEBUG_ASSERT =
    \\use std.debug
    \\use std.fmt
    \\func divide(a: i32, b: i32) -> i32 {
    \\    std.debug.assert(b != 0)
    \\    ret a / b
    \\}
    \\func main() -> void {
    \\    x := divide(10, 2)
    \\    std.fmt.println("done")
    \\}
;

// std.os sample
pub const OS_SAMPLE =
    \\use std.os
    \\use std.fmt
    \\func main() -> void {
    \\    t := std.os.clock_ms()
    \\    std.fmt.println("running")
    \\    std.os.exit(0)
    \\}
;

// Combined: struct + match + defer using correct std.fmt
pub const STRUCT_MATCH_DEFER =
    \\use std.fmt
    \\
    \\struct Counter {
    \\    value: i32,
    \\}
    \\
    \\enum Dir { Up, Down }
    \\
    \\func step(mut c: Counter, d: Dir) -> void {
    \\    defer std.fmt.println("step done")
    \\    match d {
    \\        Dir.Up   => c.value += 1,
    \\        Dir.Down => c.value -= 1
    \\    }
    \\}
;
