// sample code strings used to test the parser and AST builder
// covers most of what Phase 2 can handle:
//   - const declarations
//   - mutable variables with explicit and inferred types
//   - function declarations with params and return types
//   - arithmetic, comparison, and logical expressions
//   - if / else blocks
//   - loops and break
//   - return statements
//   - assignment and compound assignment
//   - function calls
pub const FULL_PROGRAM =
    \\const MAX : i32 = 100
    \\
    \\func add(a: i32, b: i32) -> i32 {
    \\    ret a + b
    \\}
    \\
    \\func is_even(n: i32) -> bool {
    \\    ret n % 2 == 0
    \\}
    \\
    \\pub func main() -> void {
    \\    x : i32 = 10
    \\    y := 20
    \\    mut result : i32 = add(x, y)
    \\    if result == 30 {
    \\        result += 1
    \\    } else {
    \\        result = 0
    \\    }
    \\    mut counter : i32 = 0
    \\    loop {
    \\        if counter == MAX {
    \\            break
    \\        }
    \\        counter += 1
    \\    }
    \\}
;

// the simplest possible program — just returns zero
pub const RETURN_ZERO =
    \\func main() -> i32 {
    \\    ret 0
    \\}
;

// a couple of arithmetic expressions to make sure precedence is working right
pub const ARITH_EXPR =
    \\func compute() -> i32 {
    \\    a : i32 = 3 + 4 * 2
    \\    b := a - 1
    \\    ret a + b
    \\}
;

// basic if/else to test the branch parsing
pub const IF_ELSE =
    \\func check(n: i32) -> bool {
    \\    if n > 0 {
    \\        ret true
    \\    } else {
    \\        ret false
    \\    }
    \\}
;

pub const PHASE_2_EXHAUSTIVE =
    \\mod Network
    \\use std.io
    \\
    \\type Flags = u32
    \\
    \\behave SerDe {
    \\    needs tag: u8
    \\    func serialize(x: @Self) -> [u8]
    \\}
    \\
    \\struct Packet ~> SerDe {
    \\    tag: u8,
    \\    data: [u8],
    \\}
    \\
    \\enum State {
    \\    Open,
    \\    Closed,
    \\}
    \\
    \\union NetErr {
    \\    Code: i32,
    \\    Msg: str,
    \\}
    \\
    \\error SystemError { ConnReset, Timeout }
    \\
    \\ext func bind(port: int) -> int
    \\
    \\pub func handle_conn() -> void {
    \\    defer std.io.print("Closed!")
    \\    
    \\    s := State.Open
    \\    match s {
    \\        State.Open => std.io.print("open"),
    \\        State.Closed => std.io.print("closed")
    \\    }
    \\
    \\    items := [1, 2, 3]
    \\    loop items |i| {
    \\        std.io.print(i)
    \\    }
    \\
    \\    res := try bind(8080) catch |e| { ret }
    \\}
;
