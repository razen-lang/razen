pub const SEMANTIC_ERROR_PROGRAM =
    \\func main() -> void {
    \\    const_val := 10
    \\    const_val = 20
    \\    
    \\    mut x := 5
    \\    mut x := 10
    \\    
    \\    y := undeclared_var
    \\    
    \\    foo(1, 2, 3)
    \\}
    \\
    \\func foo(a: i32) -> void {
    \\    ret
    \\}
    \\
;
