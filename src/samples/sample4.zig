// sample4.zig — C6, C7, C8 critical bug fix samples
// Uses correct std API per std_new.md

// C6: match with payload binding
// Value.Int(v) => ... should emit case Value_Int: + i32 v = value.data.Int;
pub const MATCH_PAYLOAD =
    \\use std.fmt
    \\union Value {
    \\    Int(i32),
    \\    Float(f32),
    \\    Text(str),
    \\}
    \\func describe(value: Value) -> void {
    \\    match value {
    \\        Value.Int(v)   => std.fmt.println("int"),
    \\        Value.Float(v) => std.fmt.println("float"),
    \\        Value.Text(v)  => std.fmt.println("text")
    \\    }
    \\}
;

// C7: union variant construction
// Value.Int(42) should emit (Value){ .tag = Value_Int, .data = { .Int = 42 } }
pub const UNION_CONSTRUCTOR =
    \\use std.fmt
    \\union Value {
    \\    Int(i32),
    \\    Float(f32),
    \\}
    \\func make_int() -> Value {
    \\    x := Value.Int(42)
    \\    ret x
    \\}
;

// C8: assignment inside match case
// c.value += 1 should emit c.value += 1; not c_value += 1;
pub const ASSIGNMENT_IN_MATCH =
    \\use std.fmt
    \\struct Counter { value: i32, }
    \\enum Dir { Up, Down }
    \\func step(mut c: Counter, d: Dir) -> void {
    \\    match d {
    \\        Dir.Up   => c.value += 1,
    \\        Dir.Down => c.value -= 1
    \\    }
    \\    std.fmt.println("done")
    \\}
;

// Combined: all three together
pub const COMBINED_C6_C7_C8 =
    \\use std.fmt
    \\
    \\union Expr {
    \\    Num(i32),
    \\    Neg(i32),
    \\}
    \\
    \\struct Calc { result: i32, }
    \\
    \\func eval(mut c: Calc, e: Expr) -> void {
    \\    match e {
    \\        Expr.Num(v) => c.result = v,
    \\        Expr.Neg(v) => c.result = 0 - v
    \\    }
    \\    std.fmt.println("done")
    \\}
    \\
    \\func main() -> void {
    \\    n := Expr.Num(10)
    \\    mut c := Calc { result: 0 }
    \\    eval(c, n)
    \\}
;
