# Razen

Razen is a systems language. No magic, no hidden costs, and no implicit behavior. It's built for people who want total control over the hardware.

## What is Razen for?

Razen is designed for modern, performance-critical software:
- **AI/ML**: High-speed tensor ops and model infra.
- **Servers**: Low-latency, high-concurrency backends.
- **Apps**: Core logic that needs to be lean and fast.

**The goal: Meaningful, Accurate, Simple, Maximum Performance.**

## Quick Start

```razen
func main() -> void {
    fmt.println("Hello, Razen!")
}
```

## Build and Run

### Requirements
- **Zig**: Required to build the compiler. Get it at [ziglang.org](https://ziglang.org/).

### Build
```bash
git clone https://github.com/razen-lang/razen.git
cd razen
zig build run
```

### Update
```bash
git pull
zig build run
```

## Docs & Progress

Everything is documented in the `/docs` folder. If you want to see what's left to build, check `ROADMAP.md`.

- [Introduction](./docs/introduction.md)
- [Basics](./docs/basics.md)
- [Types](./docs/types.md)
- [Roadmap](./ROADMAP.md)

## License
Apache 2.0

**Creator**: [Prathmesh Barot](https://github.com/prathmesh-barot)
