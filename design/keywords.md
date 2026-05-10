# Keywords

| Keyword  | Usage                                        | Category       |
| -------- | -------------------------------------------- | -------------- |
| `type`   | declare a type alias                         | Declaration    |
| `enum`   | declare an enum                              | Declaration    |
| `union`  | declare an union                             | Declaration    |
| `error`  | declare an error sets                        | Declaration    |
| `struct` | declare a structur                           | Declaration    |
| `behave` | declare a shared behaviour                   | Declaration    |
| `ext`    | implement a behave on a type from outside it | Declaration    |
| `func`   | define a function                            | Declaration    |
| `pub`    | mark something as publicly accessible        | Declaration    |
| `mod`    | declare a module                             | Declaration    |
| `use`    | bring a module or symbol into scope          | Declaration    |
| `const`  | declare a compile-time constant              | Declaration    |
| `mut`    | declare a mutable variable                   | Declaration    |
| `if`     | conditional branch                           | Control Flow   |
| `else`   | fallback branch for if                       | Control Flow   |
| `match`  | pattern match on a value                     | Control Flow   |
| `loop`   | repeat a block                               | Control Flow   |
| `ret`    | return a value from a function               | Control Flow   |
| `break`  | exit a loop early                            | Control Flow   |
| `skip`   | skip to the next loop iteration              | Control Flow   |
| `try`    | propagate an error up the call               | Error Handling |
| `catch`  | handle an error from a result                | Error Handling |
| `defer`  | run a statement when the current scope exits | Control Flow   |

# Symbols

| Symbol  | Usage                | Category         |
| ------- | -------------------- | ---------------- |
| `=`     | assignment           | Assignment       |
| `:=`    | inferred declaration | Assignment       |
| `+=`    | add assign           | Assignment       |
| `-=`    | sub assign           | Assignment       |
| `*=`    | mul assign           | Assignment       |
| `/=`    | div assign           | Assignment       |
| `%=`    | mod assign           | Assignment       |
| `+`     |                      | Arthemetic       |
| `-`     |                      | Arthemetic       |
| `*`     |                      | Arthemetic       |
| `/`     |                      | Arthemetic       |
| `%`     |                      | Arthemetic       |
| `==`    |                      | Comparison       |
| `!=`    |                      | Comparison       |
| `<`     |                      | Comparison       |
| `<=`    |                      | Comparison       |
| `>`     |                      | Comparison       |
| `>=`    |                      | Comparison       |
| `!`     |                      | Logical          |
| `&&`    |                      | Logical          |
| `&`     |                      | Bitwise          |
| `|`    |                      | Bitwise          |
| `^`     |                      | Bitwise          |
| `~`     |                      | Bitwise          |
| `<<`    |                      | Bitwise          |
| `>>`    |                      | Bitwise          |
| `*T`    |                      | Pointer / Memory |
| `&x`    |                      | Pointer / Memory |
| `ptr.*` |                      | Pointer / Memory |
| `.`     |                      | Access / Paths   |
| `->`    |                      |                  |
| `:`     |                      |                  |
| `,`     |                      |                  |
| `=>`    |                      |                  |
| `...`   |                      |                  |
| `..=`   |                      |                  |
| `..`    |                      |                  |
| `!T`    |                      |                  |
| `?T`    |                      |                  |
| `{}`    |                      |                  |
| `()`    |                      |                  |
| `[]`    |                      |                  |
| `@`     |                      |                  |

# Types


| Type                  | Usage | Category | Stack / Heap |
| --------------------- | ----- | -------- | ------------ |
| `i1`                  |       | Numeric  |              |
| `i2`                  |       |          |              |
| `i4`                  |       |          |              |
| `i8`                  |       |          |              |
| `i16`                 |       |          |              |
| `i32`                 |       |          |              |
| `i64`                 |       |          |              |
| `i128`                |       |          |              |
| `isize`               |       |          |              |
| `int = i32`           |       |          |              |
| `u1`                  |       | Numeric  |              |
| `u2`                  |       |          |              |
| `u4`                  |       |          |              |
| `u8`                  |       |          |              |
| `u16`                 |       |          |              |
| `u32`                 |       |          |              |
| `u64`                 |       |          |              |
| `u128`                |       |          |              |
| `usize`               |       |          |              |
| `uint = u32`          |       |          |              |
| `f32`                 |       | Numeric  |              |
| `f64`                 |       |          |              |
| `f128`                |       |          |              |
| `float = f32`         |       |          |              |
| `bool`                |       |          |              |
| `char`                |       |          |              |
| `void`                |       |          |              |
| `noret`               |       |          |              |
| `any`                 |       |          |              |
| `str`                 |       |          |              |
| `string`              |       |          |              |
| `[T]`                 |       |          |              |
| `[T; N]`              |       |          |              |
| `vec[T]`              |       |          |              |
| `map{K, V}`           |       |          |              |
| `set{T}`              |       |          |              |
| `tuple -> .{T, ... }` |       |          |              |
| `enum`                |       |          |              |
| `union`               |       |          |              |
| `error`               |       |          |              |
| `struct`              |       |          |              |
| `&T`                  |       |          |              |
| `*T`                  |       |          |              |
| `ptr.*`               |       |          |              |
| `!T`                  |       |          |              |
| `?T`                  |       |          |              |
| `Error!T`             |       |          |              |
