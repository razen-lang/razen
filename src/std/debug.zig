pub const ir =
    \\@ASSERT_MSG = private unnamed_addr constant [16 x i8] c"Assertion failed\00"
    \\@PANIC_MSG = private unnamed_addr constant [7 x i8] c"Panic!\00"
    \\define i32 @std_assert(i32 %cond) {
    \\    %ok = icmp ne i32 %cond, 0
    \\    br i1 %ok, label %pass, label %fail
    \\fail:
    \\    call i32 @puts(i8* @ASSERT_MSG)
    \\    call void @abort()
    \\    ret i32 %cond
    \\pass:
    \\    ret i32 %cond
    \\}
    \\define i32 @std_panic(i8* %msg) {
    \\    %cmp = icmp ne i8* %msg, null
    \\    br i1 %cmp, label %has_msg, label %no_msg
    \\has_msg:
    \\    call i32 @puts(i8* %msg)
    \\    call void @abort()
    \\    ret i32 0
    \\no_msg:
    \\    call i32 @puts(i8* @PANIC_MSG)
    \\    call void @abort()
    \\    ret i32 0
    \\}
;
