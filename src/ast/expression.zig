/// expression.zig
///
/// Parses Razen expressions from a token stream.
/// Implements precedence-climbing (Pratt-style) binary expression parsing,
/// matching the Video 2 tutorial pattern adapted for Razen's token set.
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

const MAX_LOOP = 10_000;

// ─────────────────────────────────────────────────────────────────────────────
// Primary (leaf) parser
// ─────────────────────────────────────────────────────────────────────────────

/// Parse a single "primary" (leaf) expression node:
///   IntegerLiteral | FloatLiteral | BoolLiteral | CharLiteral |
///   StringLiteral | Identifier | FunctionCall | ( expr )
/// Returns null if the current token cannot start an expression
/// (so callers can decide to stop without error).
pub fn parsePrimary(allocator: *Allocator, ast_data: *ASTData) AstError!?*ASTNode {
    if (!ast_data.hasMore()) return null;

    const tok: Token = try ast_data.getToken();

    switch (tok.token_type) {
        // ── Integer literal ──────────────────────────────────────────────
        TokenType.IntegerValue => {
            const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            n.node_type = ASTNodeType.IntegerLiteral;
            n.token = tok;
            ast_data.advance();
            return n;
        },

        // ── Float / decimal literal ──────────────────────────────────────
        TokenType.DecimalValue => {
            const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            n.node_type = ASTNodeType.FloatLiteral;
            n.token = tok;
            ast_data.advance();
            return n;
        },

        // ── Boolean literals ─────────────────────────────────────────────
        TokenType.True, TokenType.False => {
            const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            n.node_type = ASTNodeType.BoolLiteral;
            n.token = tok;
            ast_data.advance();
            return n;
        },

        // ── Char literal ─────────────────────────────────────────────────
        TokenType.CharValue => {
            const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            n.node_type = ASTNodeType.CharLiteral;
            n.token = tok;
            ast_data.advance();
            return n;
        },

        // ── String literal ───────────────────────────────────────────────
        TokenType.StringValue => {
            const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            n.node_type = ASTNodeType.StringLiteral;
            n.token = tok;
            ast_data.advance();
            return n;
        },

        // ── Identifier or function call: name  /  name(args…) ────────────
        TokenType.Identifier => {
            ast_data.advance();
            // Peek: is the next token '(' ?  -> function call
            const next = ast_data.peekToken(0);
            if (next != null and next.?.token_type == TokenType.LeftParen) {
                return try parseFunctionCallNode(allocator, ast_data, tok);
            }
            const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            n.node_type = ASTNodeType.Identifier;
            n.token = tok;
            return n;
        },

        // ── Unary minus: -expr ───────────────────────────────────────────
        TokenType.Minus => {
            ast_data.advance();
            const operand = try parsePrimary(allocator, ast_data);
            if (operand == null) {
                ast_data.error_detail = "Expected expression after '-'";
                return AstError.Unexpected_Type;
            }
            const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            n.node_type = ASTNodeType.UnaryExpression;
            n.token = tok;
            n.left = operand;
            return n;
        },

        // ── Logical not: !expr ───────────────────────────────────────────
        TokenType.ExclamationMark => {
            ast_data.advance();
            const operand = try parsePrimary(allocator, ast_data);
            if (operand == null) {
                ast_data.error_detail = "Expected expression after '!'";
                return AstError.Unexpected_Type;
            }
            const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            n.node_type = ASTNodeType.UnaryExpression;
            n.token = tok;
            n.left = operand;
            return n;
        },

        // ── Grouped expression: ( expr ) ─────────────────────────────────
        TokenType.LeftParen => {
            ast_data.advance(); // consume '('
            const inner = try parseBinaryExpr(allocator, ast_data, 0);
            // expect ')'
            if (ast_data.hasMore()) {
                const close: Token = try ast_data.getToken();
                if (close.token_type == TokenType.RightParen) {
                    ast_data.advance();
                }
            }
            return inner;
        },

        else => return null,
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Precedence-climbing binary expression parser
// ─────────────────────────────────────────────────────────────────────────────

/// Parse a binary expression with minimum precedence `min_prec`.
/// Implements the precedence-climbing algorithm (same as Video 2 tutorial).
pub fn parseBinaryExpr(
    allocator: *Allocator,
    ast_data: *ASTData,
    min_prec: usize,
) AstError!?*ASTNode {
    var left: ?*ASTNode = try parsePrimary(allocator, ast_data);

    var loop_guard: usize = 0;
    while (ast_data.hasMore()) {
        loop_guard += 1;
        if (loop_guard >= MAX_LOOP) return AstError.Infinite_While_Loop;

        const op_tok: Token = ast_data.token_list.items[ast_data.token_index];

        if (!tok_utils.isBinaryOperator(op_tok.token_type)) break;

        const prec = tok_utils.getPrecedence(op_tok.token_type);
        if (prec < min_prec) break;

        ast_data.advance(); // consume operator

        // right-associative: parse with prec+1; for left-assoc: prec+1
        const right: ?*ASTNode = try parseBinaryExpr(allocator, ast_data, prec + 1);

        if (right == null) {
            ast_data.error_detail = "Expected expression after operator";
            ast_data.error_token = op_tok;
            return AstError.Unexpected_Type;
        }

        const bin: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
        bin.node_type = ASTNodeType.BinaryExpression;
        bin.token = op_tok;
        bin.left = left;
        bin.right = right;

        left = bin;
    }

    return left;
}

// ─────────────────────────────────────────────────────────────────────────────
// Function call argument parser
// ─────────────────────────────────────────────────────────────────────────────

/// Parse a function call node given the already-consumed name token.
/// Expects the current token to be '('.
fn parseFunctionCallNode(
    allocator: *Allocator,
    ast_data: *ASTData,
    name_tok: Token,
) AstError!*ASTNode {
    const call: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    call.node_type = ASTNodeType.FunctionCall;
    call.token = name_tok;
    call.children = try ast_utils.createChildList(allocator);

    ast_data.advance(); // consume '('

    var loop_guard: usize = 0;
    while (ast_data.hasMore()) {
        loop_guard += 1;
        if (loop_guard >= MAX_LOOP) return AstError.Infinite_While_Loop;

        const cur: Token = try ast_data.getToken();
        if (cur.token_type == TokenType.RightParen) {
            ast_data.advance(); // consume ')'
            break;
        }

        // Parse argument expression
        const arg_expr = try parseBinaryExpr(allocator, ast_data, 0);
        if (arg_expr == null) break;

        const arg_node: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
        arg_node.node_type = ASTNodeType.Argument;
        arg_node.left = arg_expr;

        call.children.?.*.append(allocator.*, arg_node) catch return AstError.Out_Of_Memory;

        // Optional comma between arguments
        if (ast_data.hasMore()) {
            const sep: Token = try ast_data.getToken();
            if (sep.token_type == TokenType.Comma) {
                ast_data.advance();
            }
        }
    }

    return call;
}
