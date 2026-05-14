const std = @import("std");
const code_samples = @import("samples/sample2.zig");
const critical_samples = @import("samples/sample3.zig");
const phase3_samples = @import("samples/sample4.zig");
const feature_samples = @import("samples/sample5.zig");
const semantic_samples = @import("samples/semantic_test.zig");
const error_samples = @import("samples/semantic_errors.zig");
const parser = @import("parser/parser.zig");
const lexer = @import("lexer/lexer.zig");
const token = @import("lexer/token.zig");
const debugging = @import("debug/debug.zig");
const ast_builder = @import("ast/ast_builder.zig");
const semantic = @import("semantic/analyzer.zig");
const llvm_convert = @import("convert/llvm/llvm_convert.zig");
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

    // Phase 4 — LLVM IR codegen
    print("{s}Phase 4{s}  ", .{ lexer.CREAM, lexer.RESET });
    const llvm_ir = llvm_convert.convert(&arena_allocator, ast_nodes, source) catch |err| {
        print("{s}LLVM Convert error: {}{s}\n", .{ lexer.RED, err, lexer.RESET });
        return;
    };
    print("\n{s}Generated LLVM IR:{s}\n", .{ lexer.LIGHT_GREEN, lexer.RESET });
    print("__LLVM_IR_START__\n{s}\n__LLVM_IR_END__\n", .{llvm_ir});
}

pub fn main() void {
    print("{s}Razen Lang — Full Pipeline Test{s}\n", .{ lexer.LIGHT_GREEN, lexer.RESET });
    print("{s}std API: std.fmt.print/println | std.os.exit | std.debug.assert/panic{s}\n\n", .{ lexer.GREY, lexer.RESET });

    // ── Test single sample with runtime ─────────────────────────────────
    convertCode("FULL_PROGRAM", code_samples.FULL_PROGRAM);

    // To test error detection, uncomment below:
    // convertCode("S01_IMMUTABLE_ASSIGN", error_samples.S01_IMMUTABLE_ASSIGN);
    // convertCode("S02_REDECLARED_VAR", error_samples.S02_REDECLARED_VAR);
    // convertCode("S03_UNDECLARED_IDENT", error_samples.S03_UNDECLARED_IDENT);
    // convertCode("S04_ARG_COUNT_MISMATCH", error_samples.S04_ARG_COUNT_MISMATCH);
    // convertCode("S05_RETURN_TYPE_MISMATCH", error_samples.S05_RETURN_TYPE_MISMATCH);
    // convertCode("S06_BREAK_OUTSIDE_LOOP", error_samples.S06_BREAK_OUTSIDE_LOOP);
    // convertCode("S07_IF_COND_NOT_BOOL", error_samples.S07_IF_COND_NOT_BOOL);
    // convertCode("S08_STRUCT_FIELD_NOT_FOUND", error_samples.S08_STRUCT_FIELD_NOT_FOUND);
    // convertCode("S09_UNDECLARED_FUNC", error_samples.S09_UNDECLARED_FUNC);
    // convertCode("S10_GLOBAL_DUPLICATE", error_samples.S10_GLOBAL_DUPLICATE);
}
