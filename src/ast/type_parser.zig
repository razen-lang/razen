const std = @import("std");
const lexer = @import("../lexer/lexer.zig");
const token_mod = @import("../lexer/token.zig");
const node_mod = @import("node.zig");
const ast_data_mod = @import("ast_data.zig");
const ast_utils = @import("ast_utils.zig");
const tok_utils = @import("token_utils.zig");
const errors = @import("errors.zig");

const Allocator = std.mem.Allocator;
const Token = lexer.Token;
const TokenType = token_mod.TokenType;
const ASTNode = node_mod.ASTNode;
const ASTNodeType = node_mod.ASTNodeType;
const ASTData = ast_data_mod.ASTData;
const AstError = errors.AstError;

pub fn parseTypeNode(allocator: *Allocator, d: *ASTData) AstError!*ASTNode {
    const type_node: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    type_node.node_type = ASTNodeType.VarType;

    const tok = try d.getToken();
    d.advance(); // consume the first token of the type

    // ── modifiers that wrap another type ────────────────────────────────
    // * T   pointer
    // & T   reference (address-of in type position)
    // ! T   failable (anonymous error)
    // ? T   optional
    // mut   mutable modifier (in param lists like `mut a: @Self`)
    if (tok.token_type == TokenType.Star or
        tok.token_type == TokenType.And or
        tok.token_type == TokenType.ExclamationMark or
        tok.token_type == TokenType.QuestionMark)
    {
        const inner = try parseTypeNode(allocator, d);
        type_node.token = tok;
        type_node.left = inner;
        return type_node;
    }

    // mut in type position (param like `mut a: @Self` — mut already consumed by parseParams,
    // but handle if we ever hit it here)
    if (tok.token_type == TokenType.Mut) {
        const inner = try parseTypeNode(allocator, d);
        type_node.token = tok;
        type_node.is_mut = true;
        type_node.left = inner;
        return type_node;
    }

    // ── [ T ]  or  [ T ; N ]  ─────────────────────────────────────────
    if (tok.token_type == TokenType.LeftBracket) {
        const inner = try parseTypeNode(allocator, d);
        // optional size:  [T; N]
        if (d.hasMore()) {
            const nt = try d.getToken();
            if (nt.token_type == TokenType.Semicolon) {
                d.advance();
                const size_tok = try d.getToken();
                d.advance(); // consume the size literal
                const size_node: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
                size_node.node_type = ASTNodeType.IntegerLiteral;
                size_node.token = size_tok;
                type_node.middle = size_node;
            }
        }
        const rb = try d.getToken();
        if (rb.token_type == TokenType.RightBracket) d.advance();

        type_node.node_type = ASTNodeType.ArrayType;
        type_node.token = tok;
        type_node.left = inner;
        return type_node;
    }

    // ── vec[T]  map{K, V}  set{T} ─────────────────────────────────────
    if (tok.token_type == TokenType.Identifier and
        (std.mem.eql(u8, tok.value, "vec") or
            std.mem.eql(u8, tok.value, "map") or
            std.mem.eql(u8, tok.value, "set")))
    {
        const open = try d.getToken();
        if (open.token_type == TokenType.LeftBracket or open.token_type == TokenType.LeftBrace) d.advance();
        const inner = try parseTypeNode(allocator, d);
        type_node.left = inner;

        // map needs K and V
        const after = try d.getToken();
        if (after.token_type == TokenType.Comma) {
            d.advance(); // eat ','
            const inner2 = try parseTypeNode(allocator, d);
            type_node.middle = inner2;
        }

        const close = try d.getToken();
        if (close.token_type == TokenType.RightBracket or close.token_type == TokenType.RightBrace) d.advance();

        type_node.token = tok;
        return type_node;
    }

    // ── Error ! T  (named error union) ────────────────────────────────
    // e.g. FileError!str  — tok is an Identifier "FileError"
    if (tok.token_type == TokenType.Identifier) {
        // peek: is the next token '!'? then it's ErrorType!ValueType
        if (d.hasMore()) {
            const maybe_excl = try d.getToken();
            if (maybe_excl.token_type == TokenType.ExclamationMark) {
                d.advance(); // eat '!'
                const inner = try parseTypeNode(allocator, d);
                type_node.token = tok; // the error type name
                type_node.left = inner;
                return type_node;
            }
        }
        // plain identifier type name (user-defined type)
        type_node.token = tok;
        return type_node;
    }

    // ── error keyword without a name  ( !T bare anonymous error ) ─────
    if (tok.token_type == TokenType.Error) {
        const excl = try d.getToken();
        if (excl.token_type == TokenType.ExclamationMark) d.advance();
        const inner = try parseTypeNode(allocator, d);
        type_node.token = tok;
        type_node.left = inner;
        return type_node;
    }

    // ── @ builtins: @Self, @Type, @Generic(T) ─────────────────────────
    if (tok.token_type == TokenType.At) {
        const name_tok = try d.getToken();
        d.advance(); // eat the builtin name (Self, Type, Generic …)
        type_node.token = name_tok; // e.g. "Self"

        // @Generic(T) — consume the arg list
        if (d.hasMore()) {
            const lp = try d.getToken();
            if (lp.token_type == TokenType.LeftParen) {
                d.advance(); // eat '('
                var depth: usize = 1;
                var guard: usize = 0;
                while (d.hasMore() and depth > 0) {
                    guard += 1;
                    if (guard > 1000) break;
                    const t = try d.getToken();
                    d.advance();
                    if (t.token_type == TokenType.LeftParen) depth += 1;
                    if (t.token_type == TokenType.RightParen) depth -= 1;
                }
            }
        }
        return type_node;
    }

    // ── primitive/built-in type keywords ─────────────────────────────
    if (tok_utils.isVarType(tok.token_type)) {
        // peek for  !  to handle `void!T` style (unusual, but spec mentions it)
        if (d.hasMore()) {
            const maybe_excl = try d.getToken();
            if (maybe_excl.token_type == TokenType.ExclamationMark) {
                d.advance();
                const inner = try parseTypeNode(allocator, d);
                type_node.token = tok;
                type_node.left = inner;
                return type_node;
            }
        }
        type_node.token = tok;
        return type_node;
    }

    // ── DotDot / DotDotDot for variadic params ─────────────────────────
    if (tok.token_type == TokenType.DotDotDot) {
        type_node.token = tok;
        return type_node;
    }

    d.setError("Expected a type", tok);
    return AstError.Unexpected_Type;
}
