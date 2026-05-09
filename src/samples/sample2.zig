/// Phase 2 sample — exercises the full Razen syntax understood in Phase 2:
///   • const declarations
///   • mutable variable declarations with explicit types and inferred types
///   • function declarations with parameters and return types
///   • binary expressions (arithmetic, comparison, logical)
///   • if / else blocks
///   • loop + break
///   • return statements
///   • assignment and compound-assignment
///   • function calls
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

/// Minimal sample — just a returning main.
pub const RETURN_ZERO =
    \\func main() -> i32 {
    \\    ret 0
    \\}
;

/// Arithmetic expressions only.
pub const ARITH_EXPR =
    \\func compute() -> i32 {
    \\    a : i32 = 3 + 4 * 2
    \\    b := a - 1
    \\    ret a + b
    \\}
;

/// if / else sample.
pub const IF_ELSE =
    \\func check(n: i32) -> bool {
    \\    if n > 0 {
    \\        ret true
    \\    } else {
    \\        ret false
    \\    }
    \\}
;
