# Razen Memory Model

> One owner. Explicit allocation. Scope-bounded references. No magic. No GC.
> If you can see it in the code, it happens. If you cannot see it, it does not happen.

---

## Philosophy

Every byte you allocate, you can see.
Every cleanup happens at a known point.
The compiler catches ownership mistakes.
You handle the rest.

When the rules are not enough — kernels, hardware, FFI —
you step into `unsafe` and take full control.
Nothing is hidden. Nothing is automatic. Nothing is magic.

Complexity target: 3.5 / 10

---

## The 8 Core Rules

---

### Rule 1 — Every value has exactly one owner

A value is owned by exactly one binding.
When the owner goes out of scope, the value is gone.
No GC. No reference counting. Deterministic.

```kl
func main() {
    const p = Person { name: "Ayaan", age: 22 }
    // p is alive here
}
// scope exits. p is gone. cleaned up immediately.
```

---

### Rule 2 — Ownership moves on assignment

No implicit copying. When you assign, the old binding is dead.
If you want a copy, you say so explicitly with `.copy()`.

```kl
const a = Person { name: "Ayaan" }
const b = a             // b owns it now. a is DEAD.
// a.name               // compiler error: a was moved

const c = b.copy()      // explicit copy. b still alive.
```

Prevents double-free. You always know who owns what.

---

### Rule 3 — References are scope-bound

`&T` is a borrowed view into a value.
A reference cannot outlive the scope it was created in.
No lifetime annotations. The compiler checks scope depth only.

```kl
func greet(p: &Person) {
    fmt.println("Hello, {}", .{p.name})
    // p lives here and dies here. cannot escape.
}

func main() {
    const p = Person { name: "Ayaan" }
    greet(&p)
    // p still alive. greet is done.
}
```

**The scope rule:**
A reference's scope depth must always be less than or equal
to the owner's scope depth. One rule. No annotations needed.

```kl
mut bad: &Person        // compiler error: reference escaping scope
func leak(p: &Person) {
    bad = p             // compiler error: p cannot outlive this scope
}
```

---

### Rule 4 — Mutation is always explicit

Default is immutable. `mut` makes it mutable.
No surprises. You always know if something can change.

```kl
const x = 10
x = 20                  // compiler error

mut y = 10
y = 20                  // fine

func rename(p: mut &Person, name: str) {
    p.name = name
}

mut p = Person { name: "Ayaan" }
rename(mut &p, "Ali")
```

---

### Rule 5 — Heap allocation is always explicit

Nothing allocates on the heap without you knowing.
Every function that needs heap memory takes an `Allocator` parameter.
No hidden global allocator. Ever.

```kl
func make_person(name: str, alloc: Allocator) -> !Person {
    const n = try alloc.copy(name)
    ret Person { name: n, age: 0 }
}
```

If a function has no `Allocator` parameter, it does not heap allocate.
That is a guarantee, not a convention.

---

### Rule 6 — defer handles cleanup

Stack values clean themselves when scope exits.
Heap values need explicit free.
Use `defer` right after allocation so cleanup is always next to the allocation.

```kl
func run(alloc: Allocator) -> !() {
    const p = try make_person("Ayaan", alloc)
    defer alloc.free(p)
    // use p freely
    // defer runs when scope exits, even on error
}
```

Multiple defers run in reverse order:

```kl
defer alloc.free(a)   // runs second
defer alloc.free(b)   // runs first
```

---

### Rule 7 — No null. Use ?T

There is no null in Razen.
If a value might not exist, the type says so.
You must handle the absence before using the value.

```kl
func find(name: str, list: &vec[Person]) -> ?Person {
    loop p in list {
        if p.name == name { ret p }
    }
    ret null
}

func main() {
    const result = find("Ayaan", &people)

    match result {
        null   => fmt.println("not found"),
        person => person.greet(),
    }
}
```

---

### Rule 8 — Errors are values. Use !T

No exceptions. No hidden panics.
A function that can fail says so with `!` in its return type.
You must handle it. The compiler enforces this.

```kl
func load(path: str, alloc: Allocator) -> !Person {
    const data = try fs.read(path)
    ret parse_person(data, alloc)
}

func main() {
    const p = load("data.kl", alloc) catch |err| {
        fmt.println("failed: {}", .{err})
        ret
    }
    p.greet()
}
```

`try` propagates up. `catch` handles inline. No hidden control flow.

---

## Shared Ownership

Single ownership covers most cases.
But graphs, caches, and shared resources genuinely need multiple owners.
Razen gives you two explicit types for this. You pick the right one.

### rc[T] — reference counted, single thread

```kl
const a = rc[Person].new(Person { name: "Ayaan" }, alloc)
const b = a.clone()     // both own it now. count = 2.
// a goes out of scope. count = 1.
// b goes out of scope. count = 0. freed.
```

Cost: one integer increment on clone, one decrement on drop.
Visible. Explicit. No surprise.

### arc[T] — atomic reference counted, multi thread

Same as `rc[T]` but count uses atomic operations.
Safe to share across threads. Slightly more expensive than `rc[T]`.

```kl
const shared = arc[Config].new(Config { host: "localhost" }, alloc)
const copy   = shared.clone()   // safe to send to another thread
```

**Rule: use `rc[T]` unless you need threads. Then use `arc[T]`.**
Never use `arc[T]` just in case. The cost is real and visible.

### Cycles — weak[T]

`rc[T]` and `arc[T]` do not break cycles automatically.
If A points to B and B points to A, they never free.
Use `weak[T]` to break the cycle — a non-owning pointer
that returns `?T` when you read it.

```kl
struct Node {
    value: int,
    next:  ?rc[Node],
    prev:  ?weak[Node],   // does not keep Node alive
}
```

---

## Thread Safety

By default, values stay on the thread that created them.
Crossing a thread boundary is explicit. The compiler checks it.

### Moving a value to another thread

A value can be moved to another thread if it owns all its data cleanly —
no dangling references, no `rc[T]` (use `arc[T]` for that).

```kl
const p = Person { name: "Ayaan" }
thread.spawn(p)     // p MOVES into new thread. gone from here.
```

### Sharing state across threads

Use `arc[T]` for shared ownership.
Use `Mutex[T]` to mutate shared state safely.

```kl
const state = arc[Mutex[Counter]].new(Counter { val: 0 }, alloc)
const copy  = state.clone()

thread.spawn(copy, func(s: arc[Mutex[Counter]]) {
    mut lock = s.lock()
    lock.val += 1
})
```

**Hard rule: `&T` never crosses a thread boundary. Ever.**
References are scope-bound. Thread boundaries break scope.
The compiler blocks this. No exception.

---

## Unsafe

The 8 rules keep you safe for most code.
Kernels need hardware access. FFI needs raw pointers.
SIMD needs operations the compiler cannot verify.

For these Razen has `unsafe {}`.

Inside an `unsafe` block you can:
- Use raw pointers `*T` for arithmetic and hardware addresses
- Read and write volatile memory with `vol[T]`
- Call external C functions
- Cast between pointer types
- Bypass scope-bound reference rules

```kl
// safe because: this is the UART base register on this platform
unsafe {
    const reg: *vol[u32] = 0xFFFF0000 as *vol[u32]
    reg.write(0x1)
}
```

**Rules for unsafe:**
- `*T` raw pointer is only usable inside `unsafe {}`
- Keep `unsafe {}` blocks as small as possible
- Every `unsafe {}` block should have a comment explaining why it is safe

`unsafe` is not a bug. It is an explicit contract.
You are telling the compiler: I checked this, trust me here.

---

## Volatile Memory

For kernel and embedded work, some addresses are hardware registers.
Reads and writes must happen exactly as written.
The compiler must not reorder, cache, or optimize them away.

`vol[T]` is the volatile wrapper. Only usable inside `unsafe {}`.

```kl
unsafe {
    const status: *vol[u32] = 0x4000_0000 as *vol[u32]

    status.write(0x1)           // always written. never optimized away.
    const val = status.read()   // always fresh. never cached.
}
```

**Rule: `vol[T]` is only for hardware registers and memory-mapped IO.**
Never use it for shared state between threads. Use `Mutex[T]` for that.

---

## Allocators

Different jobs need different allocators.
You pick the right one. Nothing is chosen for you.

| Allocator    | What it does                           | Best for                           |
| ------------ | -------------------------------------- | ---------------------------------- |
| `HeapAlloc`  | general purpose heap                   | most things                        |
| `ArenaAlloc` | allocate many, free all at once        | request lifetime, parsers, frames  |
| `PoolAlloc`  | fixed size chunks, very fast           | many same-size objects             |
| `StackAlloc` | stack memory, zero overhead            | small short-lived data             |

### Aligned allocation

AI/ML and SIMD require aligned memory.
Every allocator supports explicit alignment.

```kl
// 32-byte aligned for AVX2 SIMD
const buf = try alloc.alloc_aligned([f32], 256, align: 32)
defer alloc.free(buf)
```

Alignment is always a parameter. Never hidden. Never assumed.

### Allocator failure

When memory runs out the allocator returns `!T`.
You handle it like any other error. No hidden panic. No crash.

```kl
const buf = alloc.alloc([u8], 1024 * 1024) catch |err| {
    fmt.println("out of memory: {}", .{err})
    ret
}
```

### Arena example — AI/ML inference

```kl
func inference(model: &Model, input: &Tensor, arena: ArenaAlloc) -> !Tensor {
    const h1  = try forward(model.layer1, input, arena)
    const h2  = try forward(model.layer2, &h1, arena)
    const out = try forward(model.layer3, &h2, arena)
    ret out
    // arena frees all intermediate tensors at once on scope exit.
    // zero fragmentation. one free call.
}
```

---

## What the Compiler Checks

| Check                           | Prevents                      |
| ------------------------------- | ----------------------------- |
| Ownership move tracking         | use after move                |
| Scope depth of references       | use after free, dangling ref  |
| `mut` on bindings and refs      | accidental mutation           |
| `?T` must be handled            | null dereference              |
| `!T` must be handled            | ignored errors                |
| No allocator = no heap          | hidden allocation             |
| `*T` only inside `unsafe {}`   | accidental raw pointer use    |
| `&T` never crosses thread       | data races                    |
| `vol[T]` only inside `unsafe {}`| accidental volatile use      |

## What the Compiler Does NOT Check

| Not checked            | Why                                                    |
| ---------------------- | ------------------------------------------------------ |
| Aliasing rules         | multiple `&T` to same value allowed if all immutable   |
| Lifetime annotations   | scope depth rule replaces them entirely                |
| Full borrow checker    | scope rule covers 95% of the same cases, simpler       |
| Inside `unsafe {}`    | you told it to trust you there                         |

---

## Real World Capability

| Domain          | Supported | What you use                               |
| --------------- | --------- | ------------------------------------------ |
| Applications    | full      | rules 1-8                                  |
| Systems / CLI   | full      | rules 1-8, arenas                          |
| OS kernel       | full      | unsafe, vol[T], raw pointers, alignment    |
| Embedded        | full      | unsafe, vol[T], StackAlloc, PoolAlloc      |
| AI / ML         | full      | aligned alloc, ArenaAlloc, arc[T]          |
| Game engines    | full      | PoolAlloc, ArenaAlloc, unsafe for SIMD     |
| Databases       | full      | ArenaAlloc, PoolAlloc, arc[T], Mutex[T]    |

---

## Full Example — Kernel UART Driver

```kl
const UART_BASE: int = 0x4000_0000

struct Uart {
    base: int,
}

func uart_new(base: int) -> Uart {
    ret Uart { base: base }
}

func uart_write(u: &Uart, byte: u8) {
    // safe: base is a valid UART register address on this platform
    unsafe {
        const reg: *vol[u8] = u.base as *vol[u8]
        reg.write(byte)
    }
}

func uart_read(u: &Uart) -> u8 {
    unsafe {
        const reg: *vol[u8] = u.base as *vol[u8]
        ret reg.read()
    }
}

func main() {
    const uart = uart_new(UART_BASE)
    uart_write(&uart, 0x41)
}
```

## Full Example — Multi-thread Work Queue

```kl
use thread
use sync

func main() {
    const alloc  = HeapAlloc.new()
    const queue  = arc[Mutex[vec[int]]].new(vec[int].new(alloc), alloc)
    const result = arc[Mutex[int]].new(0, alloc)

    loop i in 0..8 {
        const q = queue.clone()
        const r = result.clone()

        thread.spawn(func() {
            loop {
                mut lock = q.lock()
                const job = match lock.pop() {
                    null => break,
                    val  => val,
                }
                drop(lock)              // release before heavy work

                const computed = job * job

                mut out = r.lock()
                out.val += computed
            }
        })
    }

    {
        mut lock = queue.lock()
        loop i in 0..100 { lock.push(i) }
    }

    thread.join_all()
    fmt.println("result: {}", .{result.lock().val})
}
```

Every allocation visible. Every cleanup visible.
Every error handled. Every thread boundary explicit.
No magic anywhere.