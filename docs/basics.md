# Basics

## Variables and Constants

Razen separates immutable and mutable bindings, and runtime variables from compile-time constants.

### Immutable Variables
Variables are immutable by default. They cannot be reassigned after initialization.

```razen
// Inferred type
x := 10 

// Explicit type
y : i32 = 20 
```

### Mutable Variables
To allow a variable to be changed, use the `mut` keyword.

```razen
mut count := 0
count += 1
```

### Compile-time Constants
Constants are evaluated at compile time and must have an explicit type. They are globally accessible if declared at the top level.

```razen
const MAX_BUFFER_SIZE : usize = 1024
```

Razen also supports mutable constants that exist only during the compilation phase (comptime variables):
```razen
const mut COMPILE_FLAG : bool = false
```

## Primitive Types

### Integers
Razen provides a flexible integer system. In addition to standard widths, it supports arbitrary bit-widths to precisely match hardware requirements.

- **Signed**: `i1`, `i2`, `i4`, `i8`, `i16`, `i32`, `i64`, `i128`, `isize`.
- **Unsigned**: `u1`, `u2`, `u4`, `u8`, `u16`, `u32`, `u64`, `u128`, `usize`.
- **Arbitrary Widths**: Razen allows widths from 1 up to 32,768 bits (e.g., `i32768`).
- **Shorthands**: `int` (defaults to `i32`), `uint` (defaults to `u32`).

### Floating Point
- `f32`, `f64`, `f128`.
- **Shorthand**: `float` (defaults to `f32`).

### Other Scalars
- `bool`: `true` or `false`.
- `char`: A single Unicode scalar value.
- `void`: Denotes the absence of a value (typically for function returns).
- `noret`: A diverging type for functions that never return (e.g., a panic or an infinite loop).
- `any`: A type that can hold any value.

## Strings
Razen differentiates between static and dynamic strings to avoid hidden heap allocations.

1.  **`str` (String Slice)**: An immutable slice of UTF-8 bytes. Usually points to the program's read-only data section.
    ```razen
    name : str = "Razen"
    ```
2.  **`string` (Heap String)**: A growable, heap-allocated string.
    ```razen
    mut s : string = "Hello"
    s.append(" World")
    ```

## Operators

### Arithmetic
- `+`, `-`, `*`, `/`, `%`
- Compound: `+=`, `-=`, `*=`, `/=`, `%=`

### Comparison
- `==`, `!=`, `<`, `>`, `<=`, `>=`

### Logical & Bitwise
- **Logical**: `&&` (AND), `||` (OR), `!` (NOT)
- **Bitwise**: `&` (AND), `|` (OR), `^` (XOR), `~` (NOT), `<<` (Left Shift), `>>` (Right Shift)

### Miscellaneous
- `:=` : Inferred declaration.
- `.` : Member access / Path navigation.
- `@` : Built-in attribute/intrinsic.
