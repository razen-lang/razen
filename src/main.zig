const std = @import("std");
const code_samples = @import("samples/sample2.zig");
const parser = @import("parser/parser.zig");
const lexer = @import("lexer/lexer.zig");
const token = @import("lexer/token.zig");
const debugging = @import("debug/debug.zig");
const ast_builder = @import("ast/ast_builder.zig");
const print = std.debug.print;
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const Token = lexer.Token;

fn convertCode(source: []const u8) void {
    print("\n{s}Source:{s}\n{s}\n\n", .{ lexer.GREY, lexer.RESET, source });

    const page_allocator = std.heap.page_allocator;
    var arena = ArenaAllocator.init(page_allocator);
    defer arena.deinit();

    var arena_allocator: Allocator = arena.allocator();

    // ── Phase 1 : Lex / Tokenise ─────────────────────────────────────────
    print("{s}Phase 1{s}  ", .{ lexer.CREAM, lexer.RESET });
    const token_list = parser.parseToTokens(&arena_allocator, source) catch |err| {
        print("{s}Lexer error: {}{s}\n", .{ lexer.RED, err, lexer.RESET });
        return;
    };

    debugging.printTokens(token_list);

    // ── Phase 2 : Build AST ───────────────────────────────────────────────
    print("{s}Phase 2{s}  ", .{ lexer.CREAM, lexer.RESET });
    const ast_nodes = ast_builder.buildAST(&arena_allocator, token_list, source) catch |err| {
        print("{s}AST error: {}{s}\n", .{ lexer.RED, err, lexer.RESET });
        return;
    };

    debugging.printAST(ast_nodes);
}

pub fn main() void {
    print("{s}Razen Lang — Phase 2{s}\n", .{ lexer.LIGHT_GREEN, lexer.RESET });

    print("\n{s}▶ Sample: RETURN_ZERO{s}\n", .{ lexer.CYAN, lexer.RESET });
    convertCode(code_samples.RETURN_ZERO);

    print("\n{s}▶ Sample: ARITH_EXPR{s}\n", .{ lexer.CYAN, lexer.RESET });
    convertCode(code_samples.ARITH_EXPR);

    print("\n{s}▶ Sample: IF_ELSE{s}\n", .{ lexer.CYAN, lexer.RESET });
    convertCode(code_samples.IF_ELSE);

    print("\n{s}▶ Sample: FULL_PROGRAM{s}\n", .{ lexer.CYAN, lexer.RESET });
    convertCode(code_samples.FULL_PROGRAM);
}
