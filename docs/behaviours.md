# Behaviours

Behaviours (also known as traits) define a contract that a type must satisfy. They enable polymorphism and code reuse without the overhead of class-based inheritance.

## Defining a Behaviour
A behaviour is declared with the `behave` keyword. In the declaration, all methods must use the `func` keyword.

```razen
behave Printable {
    func print_info(p: @Self) -> void
}
```

## Behaviour Requirements (`needs`)
One of Razen's unique features is the `needs` keyword. Behaviours can require that any implementing type possess specific fields. This allows the behaviour to define methods that operate on those fields safely.

```razen
behave Identifiable {
    needs id: usize // Requirement: type must have an 'id' field of type usize

    func get_id(p: @Self) -> usize {
        ret p.id // Guaranteed to exist by the 'needs' clause
    }
}
```

## Implementing Behaviours

A type implements a behaviour using the `~>` operator.

### The `func` Keyword Rules
Razen reduces boilerplate by changing how the `func` keyword is used during implementation:

| Context | Use `func`? | Example |
| :--- | :--- | :--- |
| **Behaviour Declaration** | **Yes** | `behave T { func do_work() }` |
| **Direct Method** (in Struct/Enum) | **Yes** | `struct S { func helper() { ... } }` |
| **Behaviour Implementation** | **No** | `struct S ~> T { do_work() { ... } }` |
| **Renaming Behaviour Method** | **Yes** | `struct S ~> T { func custom_name ~> T.do_work() }` |

#### Standard Implementation
When implementing a behaviour, you do **not** use the `func` keyword. You simply use the method name defined in the behaviour.

```razen
struct User ~> Printable {
    name: str,

    // No 'func' keyword needed here because it implements Printable.print_info
    print_info(p: *User) -> void { 
        fmt.println("User: {}", .{p.name})
    }
}
```

#### Renaming Implementation
If you wish to implement a behaviour method under a different name, you **must** use the `func` keyword and the `~>` mapping operator.

```razen
struct Animal ~> Dog {
    // Use 'func' to rename Dog.speak to bark_loudly
    func bark_loudly ~> Dog.speak(a: *Animal) {
        fmt.println("Woof!")
    }
}
```

## Extending Types (`ext`)
You can implement a behaviour for a type from outside its original definition using `ext`. This is useful for adding functionality to built-in types or types from other modules.

```razen
ext struct int ~> Printable {
    func print_info(p: @Self) -> void {
        fmt.println("Value: {}", .{p})
    }
}
```

## Dynamic Dispatch (`@Dyn`)
The `@Dyn` attribute allows for dynamic dispatch. It creates a trait object that can hold any type implementing the behaviour, resolving the method call at runtime.

```razen
func print_all(items: []@Dyn Printable) {
    for item in items {
        item.print_info()
    }
}
```
