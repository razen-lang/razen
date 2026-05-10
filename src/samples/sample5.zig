// sample5.zig — Important features F1-F16 coverage
// All using correct std API per std_new.md

// F1: ?T optional type -> Option_Person struct
pub const OPTIONAL_TYPE =
    \\struct Person { name: str, age: i32, }
    \\func find_person(id: i32) -> ?Person {
    \\    ret null
    \\}
;

// F2: Error!T error union return type
pub const ERROR_UNION_RETURN =
    \\error FileError { NotFound, PermissionDenied, }
    \\func read_file(path: str) -> FileError!str {
    \\    ret FileError.NotFound
    \\}
;

// F4: enum with backing type + explicit values
pub const ENUM_BACKING_TYPE =
    \\enum HttpStatus: u16 {
    \\    Ok = 200,
    \\    NotFound = 404,
    \\    ServerError = 500,
    \\}
    \\func check_status(code: HttpStatus) -> void {
    \\    s := code
    \\}
;

// F5: bit-flag enum
pub const ENUM_BIT_FLAGS =
    \\enum Permission: u8 {
    \\    Read  = 1 << 0,
    \\    Write = 1 << 1,
    \\    Exec  = 1 << 2,
    \\}
;

// F9: pub vs private function visibility
pub const PUB_VISIBILITY =
    \\use std.fmt
    \\func private_helper(x: i32) -> i32 {
    \\    ret x * 2
    \\}
    \\pub func public_api(x: i32) -> i32 {
    \\    ret private_helper(x)
    \\}
    \\pub func main() -> void {
    \\    x := public_api(5)
    \\    std.fmt.println("done")
    \\}
;

// F10: const func -> static inline
pub const CONST_FUNC =
    \\use std.fmt
    \\const func double(x: i32) -> i32 {
    \\    ret x * 2
    \\}
    \\pub func main() -> void {
    \\    x := double(5)
    \\    std.fmt.println("done")
    \\}
;

// F13: fmt.println("{}", .{name}) format string tuple args
pub const FORMAT_STRING =
    \\use std.fmt
    \\pub func main() -> void {
    \\    name : str = "Prathmesh"
    \\    age : i32 = 22
    \\    std.fmt.println("Hello {}", .{name})
    \\    std.fmt.println("Age: {}", .{age})
    \\    std.fmt.println("Name: {} Age: {}", .{name, age})
    \\}
;

// F16: &x address-of and ptr.* dereference
pub const REFERENCES =
    \\use std.fmt
    \\func get_val(ptr: *i32) -> i32 {
    \\    ret ptr.*
    \\}
    \\pub func main() -> void {
    \\    mut x : i32 = 10
    \\    y := get_val(&x)
    \\    std.fmt.println("done")
    \\}
;

// F8: needs fields in behave
pub const BEHAVE_NEEDS =
    \\use std.fmt
    \\behave Animal {
    \\    needs voice: str
    \\    needs name: str
    \\    func speak(a: @Self) -> void {
    \\        std.fmt.println("speak")
    \\    }
    \\}
;

// F12: allocator builtins
pub const ALLOCATOR_BUILTINS =
    \\use std.mem
    \\use std.fmt
    \\func main() -> void {
    \\    alloc := @arena
    \\    std.fmt.println("alloc ready")
    \\}
;

// Combined: F4 + F5 + F9 + F10 + F13
pub const COMBINED_FEATURES =
    \\use std.fmt
    \\
    \\enum Color: u8 { Red = 0, Green = 1, Blue = 2, }
    \\
    \\const func double(x: i32) -> i32 {
    \\    ret x * 2
    \\}
    \\
    \\func helper(x: i32) -> i32 {
    \\    ret x + 1
    \\}
    \\
    \\pub func main() -> void {
    \\    c := Color.Red
    \\    x := helper(10)
    \\    y := double(x)
    \\    std.fmt.println("Result: {}", .{y})
    \\}
;
