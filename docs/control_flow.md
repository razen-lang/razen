# Control Flow

Razen provides a set of lean, explicit control flow primitives designed for predictability and performance.

## Conditionals
The `if` statement handles branching.

```razen
if score > 90 {
    fmt.println("Grade A")
} else if score > 80 {
    fmt.println("Grade B")
} else {
    fmt.println("Grade C")
}
```

## Loops
Razen uses a universal `loop` construct. It is an infinite loop by default, and the developer explicitly defines the exit condition.

```razen
mut i := 0
loop {
    if i >= 10 {
        break // Exit the loop
    }
    fmt.println(i)
    i += 1
}
```

- `break`: Terminates the loop.
- `skip`: Skips the current iteration and proceeds to the next.

## Pattern Matching
The `match` statement is a powerful tool for exhaustive branching based on values, enums, and unions.

### Basic Matching
```razen
match state {
    State.Idle => fmt.println("Waiting..."),
    State.Running => fmt.println("Working..."),
    State.Stopped => fmt.println("Done."),
}
```

### Union Destructuring
Payload unions can be destructured directly in the match arm to access their inner data.

```razen
match value {
    Value.Int(n) => fmt.println("Integer: {}", .{n}),
    Value.Text(s) => fmt.println("String: {}", .{s}),
}
```

### Struct Destructuring
Matching can also be used to extract fields from structs.
```razen
match user {
    User { id, active } => fmt.println("User {} is active: {}", .{id, active}),
}
```

## Error Handling (`try` / `catch`)
Razen handles errors explicitly. The `try` keyword is used to attempt an operation that might return an error.

```razen
try {
    const data = read_file("config.txt")
    fmt.println(data)
} catch (err) {
    fmt.println("Error occurred: {}", .{err})
}
```

## Defer
The `defer` keyword schedules a block of code to run exactly when the current scope exits. This is essential for resource cleanup (e.g., closing files or releasing locks).

```razen
func process_file() -> void {
    const file = open_file("test.txt")
    defer file.close() // Executes when process_file returns

    // ... process file ...
}
```

Defers are executed in **Last-In, First-Out (LIFO)** order.
