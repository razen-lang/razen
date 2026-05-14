# Functions

Functions are the core unit of logic in Razen. They are designed to be lean, predictable, and highly optimizable.

## Basic Syntax
A function is defined using the `func` keyword.

```razen
func add(a: int, b: int) -> int {
    ret a + b
}
```

## Function Variants

### Void Functions
Functions that do not return a value use the `void` type.
```razen
func log(msg: str) -> void {
    fmt.println(msg)
}
```

### Const Functions
`const func` is evaluated at compile time. This is used for generating look-up tables, calculating constants, or performing static checks.
```razen
const func get_version() -> int {
    ret 1
}
```

### Async Functions
`async func` denotes a function that can be suspended and resumed, typically used for I/O or concurrency. They return a `Future`.
```razen
async func fetch_api(url: str) -> !str {
    // Suspension point here
}
```

### External Functions (FFI)
`ext func` allows Razen to call functions implemented in other languages (usually C).
```razen
ext func printf(fmt: str, ...) -> int
```

## Generics

### The `@Generic` Attribute
Razen uses `@Generic(T)` to define a type parameter. The compiler generates specialized versions of the function for each type used.
```razen
@Generic(T) func identity(val: T) -> T {
    ret val
}
```

### Type Parameters
You can also pass types as explicit arguments to a function.
```razen
func wrap(const T: @Type, val: T) -> T {
    ret val
}
```

## Visibility and Modules

### Public Visibility
The `pub` keyword makes a function accessible to other modules.
```razen
pub func calculate_sum(a: int, b: int) -> int {
    ret a + b
}
```

### Module System
Modules organize code into logical namespaces.
```razen
mod Network {
    pub func connect() -> void { ... }
}

// Usage
Network.connect()
```

### Imports
Use the `use` keyword to bring symbols or modules into the current scope.
```razen
use std.fmt
fmt.println("Hello")
```
