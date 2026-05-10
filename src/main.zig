const std = @import("std");
const code_samples = @import("samples/sample2.zig");
const parser = @import("parser/parser.zig");
const lexer = @import("lexer/lexer.zig");
const token = @import("lexer/token.zig");
const debugging = @import("debug/debug.zig");
const ast_builder = @import("ast/ast_builder.zig");
const c_convert = @import("convert/c/c_convert.zig");
const print = std.debug.print;
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const Token = lexer.Token;

// runs a source string through the full pipeline:
//   Phase 1 — lex it into tokens
//   Phase 2 — build an AST from those tokens
// prints the results of each phase so we can see what's happening
fn convertCode(source: []const u8) void {
    print("\n{s}Source:{s}\n{s}\n\n", .{ lexer.GREY, lexer.RESET, source });

    const page_allocator = std.heap.page_allocator;
    var arena = ArenaAllocator.init(page_allocator);
    defer arena.deinit();

    var arena_allocator: Allocator = arena.allocator();

    // ── Phase 1: lex the source into tokens ──────────────────────────────
    print("{s}Phase 1{s}  ", .{ lexer.CREAM, lexer.RESET });
    const token_list = parser.parseToTokens(&arena_allocator, source) catch |err| {
        print("{s}Lexer error: {}{s}\n", .{ lexer.RED, err, lexer.RESET });
        return;
    };

    debugging.printTokens(token_list);

    // ── Phase 2: build the AST from the token list ────────────────────────
    print("{s}Phase 2{s}  ", .{ lexer.CREAM, lexer.RESET });
    const ast_nodes = ast_builder.buildAST(&arena_allocator, token_list, source) catch |err| {
        print("{s}AST error: {}{s}\n", .{ lexer.RED, err, lexer.RESET });
        return;
    };
    debugging.printAST(ast_nodes);

    // ── Phase 3: convert AST to C code ────────────────────────
    print("{s}Phase 3{s}  ", .{ lexer.CREAM, lexer.RESET });
    const c_code = c_convert.convert(&arena_allocator, ast_nodes, source) catch |err| {
        print("{s}Convert error: {}{s}\n", .{ lexer.RED, err, lexer.RESET });
        return;
    };

    print("\n{s}Generated C Code:{s}\n{s}\n", .{ lexer.CYAN, lexer.RESET, c_code });
}

pub fn main() void {
    print("{s}Razen Lang — Phase 3{s}\n", .{ lexer.LIGHT_GREEN, lexer.RESET });

    print("\n{s}▶ Sample: RETURN_ZERO{s}\n", .{ lexer.CYAN, lexer.RESET });
    convertCode(code_samples.RETURN_ZERO);

    print("\n{s}▶ Sample: ARITH_EXPR{s}\n", .{ lexer.CYAN, lexer.RESET });
    convertCode(code_samples.ARITH_EXPR);

    print("\n{s}▶ Sample: IF_ELSE{s}\n", .{ lexer.CYAN, lexer.RESET });
    convertCode(code_samples.IF_ELSE);

    print("\n{s}▶ Sample: FULL_PROGRAM{s}\n", .{ lexer.CYAN, lexer.RESET });
    convertCode(code_samples.FULL_PROGRAM);
}
