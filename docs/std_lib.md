# Standard Library

The Razen Standard Library (`std`) is a minimal set of primitives. It avoids heavy runtime dependencies, ensuring that only the code you actually use is compiled into your binary.

## Module Hierarchy

### `std.core`
Always available. Contains the most basic types and compiler intrinsics.

### `std.mem`
Handles memory allocation and layout.
- **Allocators**: Various allocation strategies (Page, Arena, etc.).
- **Layout**: Tools for calculating memory alignment and size.

### `std.fmt`
Text formatting and output.
- `fmt.print()`: Standard output.
- `fmt.println()`: Standard output with a trailing newline.

### `std.io`
Provides the `Reader` and `Writer` behaviours for abstracting input and output streams.

### `std.fs`
File system interaction.
- **File**: Open, read, write, and close files.
- **Path**: Cross-platform path manipulation.
- **Dir**: Directory traversal and entry listing.

### `std.os`
Operating system primitives.
- Process management.
- Environment variables.
- System clock and timers.

### `std.vec`, `std.map`, `std.set`
High-performance collections.
- `vec[T]`: Dynamic array.
- `map{K, V}`: Hash map for key-value storage.
- `set{T}`: Unique collection of elements.

### `std.debug`
Development tools.
- `debug.assert(condition)`: Panics if the condition is false.
- `debug.panic(message)`: Immediately terminates the program with a diagnostic message.

## Implementation Philosophy
Every part of the `std` library is written to be as transparent as possible. If a function performs a heap allocation, it is clearly indicated in the documentation or by the return type (e.g., returning a `string` instead of a `str`).
