// expression.zig
//
// Handles parsing expressions from the token stream.
// Uses a precedence-climbing approach (sometimes called Pratt-style)
// so that things like  a + b * c  come out to the right tree shape.
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

// safety cap just in case something loops forever
const MAX_LOOP = 10_000;

// ── primary (leaf) parser ─────────────────────────────────────────────────────

// Tries to parse the smallest unit of an expression — a literal, a name, a
// function call, or a parenthesized sub-expression.
// Returns null if the current token can't start an expression, which is fine —
// callers use that as a signal to stop rather than crash.
pub fn parsePrimary(allocator: *Allocator, ast_data: *ASTData) AstError!?*ASTNode {
    if (!ast_data.hasMore()) return null;

    const tok: Token = try ast_data.getToken();

    switch (tok.token_type) {
        // ── integer literal ──────────────────────────────────────────────
        TokenType.IntegerValue => {
            const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            n.node_type = ASTNodeType.IntegerLiteral;
            n.token = tok;
            ast_data.advance();
            return n;
        },

        // ── float / decimal literal ──────────────────────────────────────
        TokenType.DecimalValue => {
            const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            n.node_type = ASTNodeType.FloatLiteral;
            n.token = tok;
            ast_data.advance();
            return n;
        },

        // ── true / false ─────────────────────────────────────────────────
        TokenType.True, TokenType.False => {
            const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            n.node_type = ASTNodeType.BoolLiteral;
            n.token = tok;
            ast_data.advance();
            return n;
        },

        // ── char literal ─────────────────────────────────────────────────
        TokenType.CharValue => {
            const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            n.node_type = ASTNodeType.CharLiteral;
            n.token = tok;
            ast_data.advance();
            return n;
        },

        // ── string literal ───────────────────────────────────────────────
        TokenType.StringValue => {
            const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            n.node_type = ASTNodeType.StringLiteral;
            n.token = tok;
            ast_data.advance();
            return n;
        },

        // ── identifier or function call: name  /  name(args…) ────────────
        TokenType.Identifier => {
            ast_data.advance();
            // peek ahead — if there's a '(' right after, it's a function call
            const next = ast_data.peekToken(0);
            if (next != null and next.?.token_type == TokenType.LeftParen) {
                return try parseFunctionCallNode(allocator, ast_data, tok);
            }
            const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            n.node_type = ASTNodeType.Identifier;
            n.token = tok;
            return n;
        },

        // ── unary minus: -expr ───────────────────────────────────────────
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

        // ── logical not: !expr ───────────────────────────────────────────
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

        // ── grouped expression: ( expr ) ─────────────────────────────────
        TokenType.LeftParen => {
            ast_data.advance(); // eat the '('
            const inner = try parseBinaryExpr(allocator, ast_data, 0);
            // close it up if there's a matching ')'
            if (ast_data.hasMore()) {
                const close: Token = try ast_data.getToken();
                if (close.token_type == TokenType.RightParen) {
                    ast_data.advance();
                }
            }
            return inner;
        },

        // anything else isn't an expression — return null and let the caller decide
        else => return null,
    }
}

// ── precedence-climbing binary expression parser ──────────────────────────────

// The main expression parser. min_prec controls which operators we're
// willing to consume at this level — higher levels grab tighter-binding ops.
// This is the standard precedence-climbing algorithm, nothing fancy.
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

        // stop if this isn't an operator we care about
        if (!tok_utils.isBinaryOperator(op_tok.token_type)) break;

        const prec = tok_utils.getPrecedence(op_tok.token_type);
        if (prec < min_prec) break;

        ast_data.advance(); // eat the operator

        // recurse with prec+1 so left-associative operators work correctly
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

// ── function call argument parser ─────────────────────────────────────────────

// Parses a function call given the name token we already consumed.
// When we get here the current token should be '('.
fn parseFunctionCallNode(
    allocator: *Allocator,
    ast_data: *ASTData,
    name_tok: Token,
) AstError!*ASTNode {
    const call: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    call.node_type = ASTNodeType.FunctionCall;
    call.token = name_tok;
    call.children = try ast_utils.createChildList(allocator);

    ast_data.advance(); // eat '('

    var loop_guard: usize = 0;
    while (ast_data.hasMore()) {
        loop_guard += 1;
        if (loop_guard >= MAX_LOOP) return AstError.Infinite_While_Loop;

        const cur: Token = try ast_data.getToken();
        if (cur.token_type == TokenType.RightParen) {
            ast_data.advance(); // eat ')'
            break;
        }

        // parse the argument expression
        const arg_expr = try parseBinaryExpr(allocator, ast_data, 0);
        if (arg_expr == null) break;

        const arg_node: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
        arg_node.node_type = ASTNodeType.Argument;
        arg_node.left = arg_expr;

        call.children.?.*.append(allocator.*, arg_node) catch return AstError.Out_Of_Memory;

        // comma between arguments is optional
        if (ast_data.hasMore()) {
            const sep: Token = try ast_data.getToken();
            if (sep.token_type == TokenType.Comma) {
                ast_data.advance();
            }
        }
    }

    return call;
}
