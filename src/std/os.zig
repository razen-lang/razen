pub const ir =
    \\define i32 @std_exit(i32 %code) {
    \\    call void @exit(i32 %code)
    \\    ret i32 %code
    \\}
    \\define i32 @std_clock_ms() {
    \\    ret i32 0
    \\}
    \\define i32 @std_clock_ns() {
    \\    ret i32 0
    \\}
;
