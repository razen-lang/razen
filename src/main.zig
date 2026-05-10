const std = @import("std");
const code_samples = @import("samples/sample2.zig");
const critical_samples = @import("samples/sample3.zig");
const phase3_samples = @import("samples/sample4.zig");
const semantic_samples = @import("samples/semantic_test.zig");
const parser = @import("parser/parser.zig");
const lexer = @import("lexer/lexer.zig");
const token = @import("lexer/token.zig");
const debugging = @import("debug/debug.zig");
const ast_builder = @import("ast/ast_builder.zig");
const semantic = @import("semantic/analyzer.zig");
const c_convert = @import("convert/c/c_convert.zig");
const print = std.debug.print;
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const Token = lexer.Token;

fn convertCode(label: []const u8, source: []const u8) void {
    print("\n{s}━━━ {s} ━━━{s}\n", .{ lexer.CYAN, label, lexer.RESET });
    print("{s}Source:{s}\n{s}\n\n", .{ lexer.GREY, lexer.RESET, source });

    const page_allocator = std.heap.page_allocator;
    var arena = ArenaAllocator.init(page_allocator);
    defer arena.deinit();
    var arena_allocator: Allocator = arena.allocator();

    // Phase 1 — lex
    print("{s}Phase 1{s}  ", .{ lexer.CREAM, lexer.RESET });
    const token_list = parser.parseToTokens(&arena_allocator, source) catch |err| {
        print("{s}Lexer error: {}{s}\n", .{ lexer.RED, err, lexer.RESET });
        return;
    };
    debugging.printTokens(token_list);

    // Phase 2 — AST
    print("{s}Phase 2{s}  ", .{ lexer.CREAM, lexer.RESET });
    const ast_nodes = ast_builder.buildAST(&arena_allocator, token_list, source) catch |err| {
        print("{s}AST error: {}{s}\n", .{ lexer.RED, err, lexer.RESET });
        return;
    };
    debugging.printAST(ast_nodes);

    // Phase 3 — Semantic
    print("{s}Phase 3{s}  ", .{ lexer.CREAM, lexer.RESET });
    var analyzer = semantic.Analyzer.init(&arena_allocator) catch |err| {
        print("{s}Analyzer Init error: {}{s}\n", .{ lexer.RED, err, lexer.RESET });
        return;
    };
    defer analyzer.deinit();
    analyzer.analyze(ast_nodes) catch |err| {
        print("{s}Semantic Analysis error: {}{s}\n", .{ lexer.RED, err, lexer.RESET });
        return;
    };
    if (analyzer.has_errors) {
        print("\n{s}Compilation failed due to semantic errors.{s}\n", .{ lexer.RED, lexer.RESET });
        return;
    }
    print("\t\tSemantic Analysis\t\t\tDone\n", .{});

    // Phase 4 — C codegen
    print("{s}Phase 4{s}  ", .{ lexer.CREAM, lexer.RESET });
    const c_code = c_convert.convert(&arena_allocator, ast_nodes, source) catch |err| {
        print("{s}Convert error: {}{s}\n", .{ lexer.RED, err, lexer.RESET });
        return;
    };
    print("\n{s}Generated C:{s}\n{s}\n", .{ lexer.LIGHT_GREEN, lexer.RESET, c_code });
}

pub fn main() void {
    print("{s}Razen Lang — Full Pipeline Test{s}\n", .{ lexer.LIGHT_GREEN, lexer.RESET });
    print("{s}std API: std.fmt.print/println | std.os.exit | std.debug.assert/panic{s}\n\n", .{ lexer.GREY, lexer.RESET });

    // ── Core samples ────────────────────────────────────────────────────
    convertCode("RETURN_ZERO",        code_samples.RETURN_ZERO);
    convertCode("ARITH_EXPR",         code_samples.ARITH_EXPR);
    convertCode("IF_ELSE",            code_samples.IF_ELSE);
    convertCode("FULL_PROGRAM",       code_samples.FULL_PROGRAM);
    convertCode("PHASE_2_EXHAUSTIVE", code_samples.PHASE_2_EXHAUSTIVE);

    // ── Critical-bug fix samples ─────────────────────────────────────────
    convertCode("C1: DEFER ORDER",                 critical_samples.DEFER_ORDER);
    convertCode("C1: DEFER BEFORE RETURN",         critical_samples.DEFER_BEFORE_RETURN);
    convertCode("C2: TRY/CATCH",                   critical_samples.TRY_CATCH_BASIC);
    convertCode("C3: TAGGED UNION",                critical_samples.TAGGED_UNION);
    convertCode("C3: TAGGED UNION STRUCT VARIANT", critical_samples.TAGGED_UNION_STRUCT_VARIANT);
    convertCode("C4: @SELF IN BEHAVE",             critical_samples.SELF_IN_BEHAVE);
    convertCode("C5: USE PATH DOTS",               critical_samples.USE_PATH);
    convertCode("STD.DEBUG ASSERT+PANIC",          critical_samples.DEBUG_ASSERT);
    convertCode("STD.OS EXIT+CLOCK",               critical_samples.OS_SAMPLE);
    convertCode("STRUCT+MATCH+DEFER",              critical_samples.STRUCT_MATCH_DEFER);

    // ── Phase 3: C6/C7/C8 critical fixes ────────────────────────────────
    convertCode("C6: MATCH PAYLOAD BINDING",        phase3_samples.MATCH_PAYLOAD);
    convertCode("C7: UNION CONSTRUCTOR",            phase3_samples.UNION_CONSTRUCTOR);
    convertCode("C8: ASSIGNMENT IN MATCH",          phase3_samples.ASSIGNMENT_IN_MATCH);
    convertCode("COMBINED C6+C7+C8",               phase3_samples.COMBINED_C6_C7_C8);
}
