pub const ir =
    \\@STD_PRINT_FMT = private unnamed_addr constant [4 x i8] c"%s\00"
    \\define i32 @std_print(i8* %val) {
    \\    %t0 = call i32 (i8*, ...) @printf(i8* @STD_PRINT_FMT, i8* %val)
    \\    ret i32 0
    \\}
    \\@STD_PRINTLN_FMT = private unnamed_addr constant [5 x i8] c"%s\0A\00"
    \\define i32 @std_println(i8* %val) {
    \\    %t0 = call i32 (i8*, ...) @printf(i8* @STD_PRINTLN_FMT, i8* %val)
    \\    ret i32 0
    \\}
;
