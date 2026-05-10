// sample2.zig — core pipeline samples
// Uses correct std API per std_new.md:
//   - std.fmt.print(s: str) -> void
//   - std.fmt.println(s: str) -> void
//   - std.fmt.eprint(s: str) -> void
//   - std.os.exit(code: i32) -> noret
//   - std.debug.assert(cond: bool) -> void
//   - std.debug.panic(msg: str) -> noret

// simplest possible program — just returns zero
pub const RETURN_ZERO =
    \\func main() -> i32 {
    \\    ret 0
    \\}
;

// arithmetic expressions
pub const ARITH_EXPR =
    \\func compute() -> i32 {
    \\    a : i32 = 3 + 4 * 2
    \\    b := a - 1
    \\    ret a + b
    \\}
;

// basic if/else
pub const IF_ELSE =
    \\func check(n: i32) -> bool {
    \\    if n > 0 {
    \\        ret true
    \\    } else {
    \\        ret false
    \\    }
    \\}
;

// full program using std.fmt (correct std module)
pub const FULL_PROGRAM =
    \\use std.fmt
    \\
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
    \\    std.fmt.println("done")
    \\}
;

// exhaustive Phase 2 test — updated to use correct std modules
pub const PHASE_2_EXHAUSTIVE =
    \\mod Network
    \\use std.fmt
    \\use std.os
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
    \\    defer std.fmt.println("Closed!")
    \\
    \\    s := State.Open
    \\    match s {
    \\        State.Open   => std.fmt.println("open"),
    \\        State.Closed => std.fmt.println("closed")
    \\    }
    \\
    \\    items := [1, 2, 3]
    \\    loop items |i| {
    \\        std.fmt.print(i)
    \\    }
    \\
    \\    res := try bind(8080) catch |e| { ret }
    \\}
    \\
    \\pub func main() -> void {
    \\    handle_conn()
    \\    std.os.exit(0)
    \\}
;
