# Types

Razen uses a precise type system to ensure memory safety and layout control without a garbage collector.

## Structs
Structs are the primary way to group related data into a single contiguous block of memory.

### Basic Definition
```razen
struct User {
    id: usize,
    username: str,
    active: bool,
}
```

### Methods in Structs
You can define functions directly inside a struct. These functions can take a pointer to the struct (`*Self`) or a mutable pointer (`mut *Self`).

```razen
struct Counter {
    value: int,

    func increment(mut self: *Counter) {
        self.value += 1
    }

    func get_val(self: *Counter) -> int {
        ret self.value
    }
}
```

## Enums
Enums represent a value that is one of several possible variants.

### Simple Enums
Unit variants used for state or category.
```razen
enum Status {
    Idle,
    Running,
    Stopped,
}
```

### Backed Enums
Enums can be backed by an integer type for efficient storage and FFI.
```razen
enum HttpCode : u16 {
    Ok = 200,
    NotFound = 404,
    InternalError = 500,
}
```

### Bit-Flags
By using a backing type, enums can be used as bit-masks.
```razen
enum Permission : u8 {
    Read = 1 << 0,
    Write = 1 << 1,
    Exec = 1 << 2,
}

// Combine flags using bitwise OR
perms := Permission.Read | Permission.Write
```

## Unions
Unions allow a single memory location to hold different types of data.

### Tagged Unions (Sum Types)
The most common form of union, where the variant is tracked.
```razen
union Value {
    Int(i64),
    Float(f64),
    Text(str),
}
```

### Struct Variants
Unions can carry complex data using struct-like syntax.
```razen
union Event {
    Click { x: i32, y: i32 },
    KeyPress(char),
    Quit,
}
```

### Recursive Unions
To create recursive data structures (like trees or linked lists), use pointers within the union variants.
```razen
union Node {
    Value(i64),
    Add {
        left: *Node,
        right: *Node,
    },
}
```

## Error Sets
Error sets are specialized enums used specifically for failure states.

```razen
error FileError {
    NotFound,
    AccessDenied,
    DiskFull,
}
```

### The Error Union (`!T`)
Razen uses the `!T` syntax to denote a return value that can either be an error from a specific set or a successful value of type `T`.

```razen
// Returns a string or a FileError
func read_config() -> FileError!str {
    if file_missing {
        ret FileError.NotFound
    }
    ret "config_data"
}
```

## Type Aliases
You can create descriptive names for existing types.
```razen
type UserId = usize
type Result = FileError!str
```
