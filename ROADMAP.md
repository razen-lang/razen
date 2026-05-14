# Razen Compiler Development Roadmap

This document details the specific implementation tasks required to build the Razen compiler and toolchain. It is a technical checklist, assuming prior knowledge of compiler design and LLVM IR.

## Stage 1: Frontend - Lexer, Parser, Semantic Analysis

### 1.1 Lexer Implementation Details
- **Tokenization**: Map every character of the input source code to a `TokenType`.
  - [ ] Implement `Identifier` tokenization: Sequence of letters, digits, and underscores, not starting with a digit.
  - [ ] Implement `IntegerValue` tokenization: Sequence of digits.
    - [ ] Support arbitrary bit-widths (e.g., `i32768`) based on token length and type prefix (e.g., `i1`, `u8`, `i32768`).
  - [ ] Implement `DecimalValue` tokenization: Support for floating-point literals (e.g., `3.14`, `1.0e-5`).
  - [ ] Implement `CharValue` tokenization: Single Unicode scalar enclosed in single quotes (`'a'`). Handle escape sequences (`\'`, `\\`).
  - [ ] Implement `StringValue` tokenization: Sequence of characters enclosed in double quotes (`"hello"`). Handle escape sequences (`\n`, `\t`, `\"`, `\\`).
  - [ ] Implement `Comment` and `EndComment` tokenization for single-line (`// ...`) and block (`/* ... */`) comments. Ensure `EndComment` token is generated for block comments that end at EOL.
  - [ ] Implement Operator tokenization: Single characters (`+`, `-`, `.`, `,`) and multi-character operators (`==`, `+=`, `->`, `=>`, `..`, `...`, `..=`). Distinguish operators based on character sequences.
  - [ ] Implement Separator tokenization: Whitespace (spaces, tabs, newlines, carriage returns), and structural characters (`(`, `)`, `{`, `}`, `[`, `]`, `;`, `:`). Ensure newlines increment line counts and reset character counts.
  - [ ] Implement `EOF` token for end of input.
  - [ ] Handle unrecognized characters as `NA` tokens, potentially with error reporting.
- **Line/Column Tracking**: Maintain accurate line and character counts for all tokens generated. This is critical for error reporting.
- **State Management**: Manage the lexer's internal state: current position, line number, character count, and tracking of previous tokens (e.g., for comment detection).

### 1.2 Parser Implementation Details
- **AST Node Definitions**: Define a comprehensive AST node structure covering all language constructs. Each node must include: `node_type`, `token` (source token), `left`/`middle`/`right` child pointers, and potentially `children` slice for lists (e.g., function parameters, block statements).
- **Primary Parsing Functions**:
  - [ ] `parseToTokens()`: Orchestrates the lexing process and returns a token list.
  - [ ] `processCharacter()`: Manages the tokenization loop, dispatching to specific token readers.
- **Token Reading Functions**: Implement specific parsers for different token types.
  - [ ] `readString()`: Parse `StringValue`, handle escapes, track character index.
  - [ ] `readChar()`: Parse `CharValue`, handle escapes, validate single character.
  - [ ] `readSeparator()`: Parse single-character separators and map to `TokenType`.
  - [ ] `readDotOperator()`: Parse `.`, `..`, `...`, `..=` and map to correct `TokenType`.
  - [ ] `readOperator()`: Parse single and compound operators, peeking ahead for multi-character sequences.
  - [ ] `ReadWord()`: Parse identifiers, keywords, and numeric literals. Map keywords to `TokenType`.
- **Expression Parsing**: Implement recursive descent parsing for expressions.
  - [ ] Parse literal values (integers, floats, strings, chars, bools, void).
  - [ ] Parse identifiers (variables, functions, types).
  - [ ] Parse binary expressions: Implement operator precedence and associativity rules (e.g., `*` before `+`).
  - [ ] Parse unary expressions (`-x`, `!x`, `*ptr`).
  - [ ] Parse pointer dereference (`ptr.*`).
  - [ ] Parse member access chains (`a.b.c`).
  - [ ] Parse function calls (`func(args)`), including argument list parsing.
  - [ ] Parse range expressions (`a..b`, `a..=b`).
- **Declaration Parsing**: Implement parsers for all top-level declarations.
  - [ ] `parseTypeAlias()`: Parse `type Name = Type;`.
  - [ ] `parseStruct()`: Parse `struct Name { fields... }`, including methods and behaviour implementations (`~>`).
  - [ ] `parseEnum()`: Parse `enum Name { variants... }`, backing types (`: u16`), and discriminants (`= 200`).
  - [ ] `parseUnion()`: Parse `union Name { variants... }`, handling unit, tuple, struct, and recursive variants.
  - [ ] `parseErrorMap()`: Parse `error Name { variants... }`.
  - [ ] `parseConst()`: Parse `const Name: Type = Value;` and `const mut Name: Type = Value;`.
  - [ ] `parseVarDecl()`: Parse `name: Type = Value` and `name := Value`.
  - [ ] `parseFuncDecl()`: Parse function signatures, including `pub`, `ext`, `const`, `async`, generic parameters (`@Generic(T)`), parameters (`name: Type`), return types (`-> Type`), and function bodies (`{ ... }`).
  - [ ] `parseBehave()`: Parse behaviour declarations (`behave Name { func ... }`), including `needs` clauses.
  - [ ] `parseExt()`: Parse external function declarations (`ext func ...`).
  - [ ] `parseModule()`: Parse module definitions (`mod Name { ... }`).
  - [ ] `parseUse()`: Parse import statements (`use Path.To.Symbol`).
  - [ ] `parseDefer()`: Parse `defer { statement }` blocks.
- **Control Flow Parsing**: Implement parsers for all control flow constructs.
  - [ ] `parseIf()`: Parse `if (condition) { then_block } else { else_block }`.
  - [ ] `parseLoop()`: Parse `loop { body }`, handling `break` and `skip`.
  - [ ] `parseMatch()`: Parse `match value { pattern1 => expr1, pattern2 => expr2, ... }`.
    - [ ] Implement literal pattern parsing.
    - [ ] Implement enum/union variant pattern parsing.
    - [ ] Implement destructuring patterns for structs and unions.
    - [ ] Implement wildcard (`_`) pattern parsing.
  - [ ] `parseReturn()`: Parse `ret value`.
  - [ ] `parseTryStatement()`: Parse `try { expr } catch (err) { handler }`.

### 1.3 Semantic Analysis Details
- **Scope Management**:
  - [ ] Implement symbol tables for each scope (global, module, function, block, loop, match).
  - [ ] Resolve identifiers to declarations: variables, constants, functions, types, modules, behaviours.
  - [ ] Detect and report "undeclared identifier" errors.
  - [ ] Detect and report "redeclared identifier" errors within the same scope.
- **Type Checking**:
  - [ ] **Expression Type Inference**: Infer types for `:=` and intermediate expression results.
  - [ ] **Operator Type Compatibility**: Validate operands for all operators (`+`, `-`, `*`, `/`, `%`, bitwise, logical, comparison).
  - [ ] **Assignment Compatibility**: Check assignability: `value_type` $\rightarrow$ `target_type`.
  - [ ] **Function Call Type Checking**:
    - [ ] Validate argument count and type compatibility against parameter list.
    - [ ] Check return value compatibility if used in an assignment or expression.
  - [ ] **Pointer/Reference Checks**:
    - [ ] Validate operations on `*T` (dereference `load`/`store`).
    - [ ] Check `&x` usage (address-of).
  - [ ] **Error Union Handling**:
    - [ ] Ensure functions returning `!T` are handled correctly with `try` or `catch`.
    - [ ] Validate `try` usage within appropriate contexts.
  - [ ] **Array/Slice Type Checking**:
    - [ ] Validate index types for `[T][index]`.
    - [ ] Check array bounds if static size is known (compile-time check).
  - [ ] **`mut` Correctness**: Ensure mutable variables are only assigned via mutable references (`mut`).
- **Behaviour Validation**:
  - [ ] Verify `needs` clauses: Check for presence of required fields in implementing types.
  - [ ] Method Implementation Check: Ensure all required behaviour methods are defined in the implementing type.
  - [ ] Signature Matching: Verify method parameter and return types match behaviour definitions.
- **Comptime Validation**:
  - [ ] Validate `const` expressions are evaluable at compile time.
  - [ ] Check `const func` calls within `const` declarations.

---

## Stage 2: Type System and Memory Layout (LLVM IR Mapping)

### 2.1 Primitive Type Mapping to LLVM IR
- [ ] Map `i1`, `u1` to LLVM `i1`.
- [ ] Map `i2`, `u2` to LLVM `i2` (if supported by target, else use `i8`).
- [ ] Map `i4`, `u4` to LLVM `i4` (if supported by target, else use `i8`).
- [ ] Map `i8`, `u8`, `char` to LLVM `i8`.
- [ ] Map `i16`, `u16` to LLVM `i16`.
- [ ] Map `i32`, `u32`, `int`, `uint` to LLVM `i32`.
- [ ] Map `i64`, `u64`, `isize`, `usize` to LLVM `i64` (assuming 64-bit target pointer width).
- [ ] Map `i128`, `u128` to LLVM `i128`.
- [ ] Map `f16` to LLVM `half` (if target supports it).
- [ ] Map `f32`, `float` to LLVM `float`.
- [ ] Map `f64` to LLVM `double`.
- [ ] Map `f128` to LLVM `fp128` (if target supports it).
- [ ] Map `bool` to LLVM `i1`.
- [ ] Map `void` to LLVM `void` return type; no storage.
- [ ] Map `noret` to LLVM `nevertype`.
- [ ] Map `any` to LLVM `ptr` or `i8*` for generic contexts.

### 2.2 Composite Type Mapping to LLVM IR
- [ ] **Structs**:
    - [ ] Define LLVM `struct` types using `type { ... }`.
    - [ ] Calculate field offsets based on type sizes and alignment requirements.
    - [ ] Insert padding bytes where necessary for alignment.
    - [ ] Implement `getelementptr` (GEP) for accessing struct members.
    - [ ] Handle nested struct layouts recursively.
- [ ] **Enums**:
    - [ ] Map simple enums to LLVM integer types (e.g., `i32` for `Status`).
    - [ ] For backed enums (`enum Name: u16`), use the specified LLVM integer type.
    - [ ] Implement logic to retrieve the discriminant value for `match` statements.
    - [ ] For bit-flags, map to LLVM integer type and use bitwise operations for flag manipulation.
- [ ] **Unions**:
    - [ ] **Tagged Unions**: Represent as LLVM `struct { i32 tag, union_payload }`. `union_payload` itself can be a packed struct or union.
    - [ ] **Untagged Unions**: Represent as LLVM packed struct (`{ i32, double }`).
    - [ ] Implement IR for accessing union members based on the current tag (using conditional selects or unions).
- [ ] **Error Sets**:
    - [ ] Map `error` sets to LLVM integer types (e.g., `i32`). Assign unique integer codes to each error variant.
- [ ] **Error Unions (`!T`)**:
    - [ ] Represent as LLVM `struct { i1 success_flag, union_payload }`. `union_payload` stores either the success value or the error code.
    - [ ] Implement IR for checking the success flag (`icmp`) before accessing the value or error code.
- [ ] **Arrays (`[T]` / `[T; N]`)**:
    - [ ] Map fixed-size arrays `[N]T` to LLVM `[N x T]` types.
    - [ ] Map dynamic array/slice types `[T]` to `struct { *T data, usize len }`.
    - [ ] Implement IR for array indexing using `getelementptr`.
- [ ] **Pointers (`*T`, `&T`)**:
    - [ ] Map `*T` to LLVM `*T`.
    - [ ] Map `&T` to LLVM `*T` (address-of operator).
    - [ ] Implement IR for dereferencing (`ptr.*`) using `load` and `store` instructions.

---

## 3. IR Generation - Statements and Expressions

### 3.1 Basic Statements
- [ ] **`VarDeclaration` / `ConstDeclaration`**:
    - [ ] Emit `alloca` instruction for local mutable variables.
    - [ ] If an initializer exists, flatten the expression and emit a `store` instruction to the `alloca`.
    - [ ] For `const`, evaluate at compile time if possible; otherwise, emit as LLVM global constant (`@const`).
- [ ] **`Assignment`**:
    - [ ] Flatten the Right-Hand Side (RHS) expression.
    - [ ] Emit a `store` instruction to the target variable's memory location.
- [ ] **`ReturnStatement`**:
    - [ ] Flatten the return expression (if present).
    - [ ] Emit `ret` instruction with the correct return type.
- [ ] **`defer` Blocks**:
    - [ ] Implement a defer stack data structure for each function.
    - [ ] At function exit points (normal `ret`, `try` error propagation), emit IR to execute deferred statements in LIFO order.
    - [ ] Ensure proper cleanup of defer stack entries.

### 3.2 Control Flow IR
- [ ] **`IfStatement`**:
    - [ ] Flatten the condition expression to a boolean value (`i1`).
    - [ ] Emit `br i1 condition, label %then, label %else`.
    - [ ] Create distinct basic blocks for `then`, `else` (if present), and `merge`.
    - [ ] Emit `br label %merge` at the end of `then` and `else` blocks.
    - [ ] Continue IR generation at the `merge` block.
    - [ ] Handle the case where `else` is omitted.
- [ ] **`LoopStatement`**:
    - [ ] Create `loop` (header) and `exit` basic blocks.
    - [ ] Emit `br label %loop` to start the loop.
    - [ ] Emit `br label %loop` at the end of the loop body (back-edge).
    - [ ] Implement `break` via `br label %exit`.
    - [ ] Implement `skip` via `br label %loop` (jump to loop header).
    - [ ] Support named loops and directed `break`/`skip` to specific loops.
- [ ] **`MatchStatement`**:
    - [ ] Flatten the match expression.
    - [ ] For enum/union matches: Generate comparisons against variant tags.
    - [ ] Emit LLVM `switch` instruction for simple cases.
    - [ ] For complex patterns (struct destructuring, guards), generate a sequence of `icmp` and `br` instructions.
    - [ ] Implement payload extraction for matched variants (load from memory based on tag).
    - [ ] Handle nested `match` statements.
- [ ] **`TryStatement` / `CatchBlock`**:
    - [ ] Wrap potentially failing operations (function calls returning error unions) in LLVM `invoke` instruction.
    - [ ] Generate `landingpad` instruction to handle function call failures.
    - [ ] Map `catch` blocks to specific error-handling basic blocks.
    - [ ] Implement error propagation: If an error occurs, jump to the `catch` block; otherwise, continue after the `try`.

### 3.3 Expression IR Emission
- [ ] **Literals**: Emit LLVM constants for integer, float, char, string literals.
- [ ] **Identifiers**: Load values from memory (`alloca` or global) based on symbol table information.
- [ ] **Binary Operators**: Emit corresponding LLVM arithmetic (`add`, `sub`, `mul`, `sdiv`, `urem`, `fadd`, `fsub`, etc.), comparison (`icmp eq/ne/slt/sle/sgt/sge` for integers, `fcmp oeq/ogt/oge/olt/ole` for floats), bitwise (`and`, `or`, `xor`, `shl`, `ashr`, `lshr`), and logical (`and`, `or`) instructions. Ensure correct types are used.
- [ ] **Unary Operators**: Emit LLVM `neg` (integer negation), `fneg` (float negation), `xor` (bitwise NOT), `trunc`, `zext`, `sext` (integer conversions).
- [ ] **Member Access**:
    - [ ] Generate `getelementptr` instructions to access struct fields, array elements, or union members.
    - [ ] Handle nested member access chains correctly.
- [ ] **Function Calls**:
    - [ ] Emit `call` instruction for regular function calls.
    - [ ] Emit `invoke` instruction for functions returning error unions.
    - [ ] Handle argument passing (values on stack or registers based on calling convention).
    - [ ] Handle return values.
- [ ] **Pointer Dereference (`ptr.*`)**:
    - [ ] Emit `load` instruction to read from the memory address.
    - [ ] Emit `store` instruction to write to the memory address.

---

## 4. Advanced Language Features (IR Generation)

### 4.1 Behaviour Dispatch
- [ ] **Static Dispatch (Monomorphization)**:
    - [ ] Identify types implementing a specific behaviour.
    - [ ] For each type, generate a specialized version of behaviour methods.
    - [ ] Replace behaviour method calls with direct calls to the monomorphized function.
- [ ] **Dynamic Dispatch (`@Dyn`)**:
    - [ ] **VTable Generation**:
        - [ ] Define an LLVM `struct` for each behaviour\'s vtable. The vtable structure contains function pointers for all required methods.
        - [ ] Emit IR to populate vtables with pointers to the concrete implementations of behaviour methods for each type.
    - [ ] **Trait Object Representation**:
        - [ ] Represent `@Dyn T` as an LLVM `struct { i8* vtable_ptr, T.layout data }`. `T.layout` is the LLVM representation of `T`.
        - [ ] Emit IR to create trait objects by packing the appropriate vtable pointer and the type\'s data.
    - [ ] **Method Lookup and Call**:
        - [ ] Generate IR to load the vtable pointer from the trait object.
        - [ ] Use `getelementptr` to find the correct method pointer within the vtable.
        - [ ] Use LLVM `callindirect` instruction to invoke the method dynamically.
- [ ] **Method Renaming**:
    - [ ] Implement parsing and AST representation for `func custom_name ~> Trait.method()`.
    - [ ] In the IR generation for the implementing type:
        - [ ] If static dispatch: Generate a wrapper function `custom_name` that calls the monomorphized `Trait.method`.
        - [ ] If dynamic dispatch: Add an entry to the vtable mapping `custom_name` to the correct implementation.

### 4.2 Async/Await and Concurrency
- [ ] **State Machine Transformation**:
    - [ ] Convert `async func` definitions into a struct representing the function's state.
    - [ ] Generate a `poll()` method for the state machine struct.
- [ ] **Suspension Points**:
    - [ ] Identify `await` expressions.
    - [ ] Emit IR to save the current state of the async function (e.g., current instruction pointer, local variables).
    - [ ] Generate IR to return a `Future` object.
- [ ] **Future Object Implementation**:
    - [ ] Define the `Future` type structure (e.g., containing a pointer to the state machine).
    - [ ] Implement IR for polling futures and handling their results or propagated errors.
- [ ] **Concurrency Primitives**:
    - [ ] Map Razen\'s `sync.Atomic` operations (`fetchAdd`, `compareExchange`, etc.) directly to LLVM atomic intrinsics (e.g., `atomicrmw add`, `cmpxchg`).

### 4.3 Compile-Time Execution (Comptime)
- [ ] **Const Evaluator**:
    - [ ] Build an interpreter for a subset of Razen expressions and `const func` calls.
    - [ ] Implement evaluation of literals, basic arithmetic, simple function calls, and type queries (`@Type`).
- [ ] **Constant Folding**:
    - [ ] Integrate LLVM optimization passes that perform constant folding on expressions evaluated at compile time.
    - [ ] Ensure Comptime-evaluated results are emitted as LLVM constants (`@(type) value`).

### 4.4 FFI and External Integration (`ext func`)
- [ ] **External Function Declaration**: Map `ext func` declarations to LLVM `declare` instructions.
- [ ] **Calling Convention**: Ensure correct argument passing (registers, stack) and return value handling based on the C ABI for the target architecture.
- [ ] **Opaque Pointers**: Map opaque pointer types in external declarations to LLVM `ptr` type.

---

## 5. Toolchain and Ecosystem Development

### 5.1 The `razenc` CLI Tool
- [ ] **Argument Parsing**: Implement argument handling for source files, output paths, target triples, and optimization levels.
- [ ] **Build Modes**: Support compilation to IR (`--emit=ir`), object files (`--emit=obj`), and executables (`--emit=bin`).
- [ ] **Target Specification**: Implement `--target <triple>` to allow cross-compilation.
- [ ] **Optimization Flags**: Map `-O0`, `-O1`, `-O2`, `-O3` to LLVM optimization passes.
- [ ] **Debug Information**: Implement generation of DWARF symbols for debugging.

### 5.2 Module System and Dependency Management
- [ ] **Module Resolution**: Implement logic to find imported modules based on `use` paths and configured search paths.
- [ ] **Symbol Export/Import**: Manage symbol visibility across module boundaries.
- [ ] **Dependency Graph**: Construct a graph of module dependencies for efficient compilation order.
- [ ] **Incremental Compilation**:
    - [ ] Hash source files, AST nodes, or relevant semantic information.
    - [ ] Cache compilation results to avoid recompiling unchanged units.

### 5.3 Standard Library (`std.*`) Implementation Task List
- [ ] **`std.core`**: Implement all basic types and compiler intrinsics not directly mapped by LLVM utilities.
- [ ] **`std.mem`**:
    - [ ] Implement `PageAllocator`: Basic bump allocator that returns memory pages.
    - [ ] Implement `ArenaAllocator`: Stack-based allocator for managing scope-local allocations.
    - [ ] Implement `PoolAllocator`: Allocator for fixed-size blocks.
    - [ ] Implement `AllocStats` for tracking allocations.
- [ ] **`std.fmt`**:
    - [ ] Implement `print` and `println` functions.
    - [ ] Map format specifiers (e.g., `{d}`, `{s}`, `{f}`) to LLVM IR or C `printf` calls.
- [ ] **`std.io`**:
    - [ ] Define `Reader` and `Writer` behaviours.
    - [ ] Implement basic byte buffer IO wrappers.
- [ ] **`std.fs`**:
    - [ ] Implement file operations (`open`, `read`, `write`, `close`, `seek`, `stat`) using OS syscalls.
    - [ ] Implement path manipulation utilities (joining, normalizing, getting components).
    - [ ] Implement directory listing (`ls`).
- [ ] **`std.os`**:
    - [ ] Implement process management (spawning, environment variables).
    - [ ] Implement time functions (`clock_now`, `sleep`).
- [ ] **`std.vec`/`map`/`set`**:
    - [ ] Implement dynamic arrays (`vec`) with growth strategies.
    - [ ] Implement hash maps (`map`) with collision resolution (e.g., separate chaining).
    - [ ] Implement hash sets (`set`) for unique element storage.
- [ ] **`std.debug`**:
    - [ ] Implement `assert` with runtime checks and optional debug builds.
    - [ ] Implement `panic` to terminate execution with a message and potentially unwind stack.

---

## 4. Verification, Benchmarking, and Optimization

### 4.1 Testing Infrastructure
- [ ] **Unit Tests**: Create comprehensive unit tests for every compiler component (lexer tokenization, parser rules, semantic checks, IR emission for each instruction).
- [ ] **Integration Tests**: Compile and run a large suite of `.rzn` sample files, verifying generated LLVM IR and final executable output against expected results.
- [ ] **Fuzz Testing**: Implement fuzzing for the parser and semantic analyzer to discover edge cases and crashes.

### 4.2 Performance Benchmarking
- [ ] **Baseline Measurement**: Establish performance benchmarks for core Razen operations (integer math, string manipulation, function calls, memory allocation) against C and Zig.
- [ ] **Compilation Speed**: Measure compiler throughput and identify bottlenecks.
- [ ] **Runtime Performance**: Benchmark generated LLVM IR performance across different optimization levels.

### 4.3 LLVM Integration and Optimization
- [ ] **LLVM Pass Pipeline**: Integrate standard LLVM optimization passes (`-O1`, `-O2`, `-O3`) into the `razenc` CLI.
- [ ] **IR Analysis**: Analyze generated IR for common inefficiencies and patterns that can be improved at the source level.
- [ ] **Target-Specific Optimizations**: Explore and apply LLVM passes tailored for specific architectures or workloads (e.g., AI/ML vectorization, server concurrency optimizations).

---

## Design Constraints Checklist
- [ ] **Zero Hidden Allocations**: Verify no implicit memory allocations occur. All allocations must be explicit via `Allocator`.
- [ ] **Predictable Mapping**: Ensure a clear, documented path from Razen source constructs to LLVM IR.
- [ ] **No Implicit Casts**: All type conversions must be explicit to prevent subtle bugs and ensure safety.
- [ ] **Simplicity**: Avoid unnecessary language complexity; focus on directness and performance.
- [ ] **Accuracy**: All language features must behave exactly as specified.
- [ ] **Performance**: Prioritize zero-cost abstractions and efficient LLVM IR generation.
