pub const ir =
    \\@STD_PRINT_FMT = private unnamed_addr constant [3 x i8] c"%d\00"
    \\define i32 @std_print(i32 %val) {
    \\    %t0 = call i32 (i8*, ...) @printf(i8* @STD_PRINT_FMT, i32 %val)
    \\    ret i32 %val
    \\}
    \\@STD_PRINTLN_FMT = private unnamed_addr constant [4 x i8] c"%d\\n\\00"
    \\define i32 @std_println(i32 %val) {
    \\    %t0 = call i32 (i8*, ...) @printf(i8* @STD_PRINTLN_FMT, i32 %val)
    \\    ret i32 %val
    \\}
;
