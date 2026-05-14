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
const type_parser = @import("type_parser.zig");
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

        // ── try expression ───────────────────────────────────────────────
        TokenType.Try => {
            ast_data.advance();
            const operand = try parsePrimary(allocator, ast_data);
            if (operand == null) {
                ast_data.error_detail = "Expected expression after 'try'";
                return AstError.Unexpected_Type;
            }
            const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            n.node_type = ASTNodeType.TryExpression;
            n.token = tok;
            n.left = operand;
            return n;
        },

        // ── array literal [ 1, 2, 3 ] ───────────────────────────────────────────────
        TokenType.LeftBracket => {
            ast_data.advance(); // eat '['
            const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            n.node_type = ASTNodeType.ArrayLiteral;
            n.token = tok;
            n.children = try ast_utils.createChildList(allocator);

            while (ast_data.hasMore()) {
                const cur: Token = try ast_data.getToken();
                if (cur.token_type == TokenType.RightBracket) {
                    ast_data.advance();
                    break;
                }
                const elem = try parseBinaryExpr(allocator, ast_data, 0);
                if (elem) |e| {
                    n.children.?.append(allocator.*, e) catch return AstError.Out_Of_Memory;
                }
                if (ast_data.hasMore()) {
                    const comma: Token = try ast_data.getToken();
                    if (comma.token_type == TokenType.Comma) ast_data.advance();
                }
            }
            return n;
        },

        // ── annotation / builtin @name ──────────────────────────────────────────
        TokenType.At => {
            ast_data.advance();
            const name_tok = try ast_data.getToken();
            ast_data.advance();

            // Zig-style @as(Type, value)
            if (std.mem.eql(u8, name_tok.value, "as")) {
                const lp = try ast_data.getToken();
                if (lp.token_type == TokenType.LeftParen) {
                    ast_data.advance(); // eat '('
                    const target_type = try type_parser.parseTypeNode(allocator, ast_data);

                    const comma = try ast_data.getToken();
                    if (comma.token_type == TokenType.Comma) ast_data.advance();

                    const value_expr = try parseBinaryExpr(allocator, ast_data, 0);

                    const rp = try ast_data.getToken();
                    if (rp.token_type == TokenType.RightParen) ast_data.advance();

                    const as_n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
                    as_n.node_type = ASTNodeType.BuiltinExpression;
                    as_n.token = name_tok;
                    as_n.left = target_type;
                    as_n.right = value_expr orelse return AstError.Unexpected_Type;
                    return as_n;
                }
            }

            const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            n.node_type = ASTNodeType.Annotation;
            n.token = name_tok;

            // @Name(args) e.g. @Generic(T)
            const next = ast_data.peekToken(0);
            if (next != null and next.?.token_type == TokenType.LeftParen) {
                ast_data.advance(); // eat '('
                // skip the generic args — just collect them to move past
                var depth: usize = 1;
                var guard2: usize = 0;
                while (ast_data.hasMore() and depth > 0) {
                    guard2 += 1;
                    if (guard2 > 1000) break;
                    const t = try ast_data.getToken();
                    ast_data.advance();
                    if (t.token_type == TokenType.LeftParen) depth += 1;
                    if (t.token_type == TokenType.RightParen) depth -= 1;
                }
                // now: was this @Name() immediately followed by a func call?
                const after = ast_data.peekToken(0);
                if (after != null and after.?.token_type == TokenType.LeftParen) {
                    return try parseFunctionCallNode(allocator, ast_data, name_tok);
                }
            } else if (next != null and next.?.token_type == TokenType.LeftParen) {
                return try parseFunctionCallNode(allocator, ast_data, name_tok);
            }
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

        // ── Block / Closure syntax: |e| expr ─────────────────────────────
        TokenType.Or => {
            ast_data.advance(); // |
            const cap_tok = try ast_data.getToken();
            if (cap_tok.token_type != TokenType.Identifier) {
                ast_data.error_detail = "Expected identifier in capture block";
                return AstError.Unexpected_Type;
            }
            ast_data.advance();
            const end_or = try ast_data.getToken();
            if (end_or.token_type != TokenType.Or) {
                ast_data.error_detail = "Expected closing '|' for capture block";
                return AstError.Unexpected_Type;
            }
            ast_data.advance();

            var body_expr: ?*ASTNode = null;
            const maybe_brac = try ast_data.getToken();
            if (maybe_brac.token_type == TokenType.LeftBrace) {
                ast_data.advance(); // {

                const b_n = try ast_utils.createDefaultAstNode(allocator);
                b_n.node_type = ASTNodeType.Block;
                b_n.children = try ast_utils.createChildList(allocator);
                while (ast_data.hasMore()) {
                    const cur_t = try ast_data.getToken();
                    if (cur_t.token_type == TokenType.RightBrace) {
                        ast_data.advance(); // }
                        break;
                    }
                    if (cur_t.token_type == TokenType.Ret) {
                        ast_data.advance(); // ret
                        const ret_expr = try parseBinaryExpr(allocator, ast_data, 0);
                        const ret_n = try ast_utils.createDefaultAstNode(allocator);
                        ret_n.node_type = ASTNodeType.ReturnStatement;
                        ret_n.token = cur_t;
                        ret_n.right = ret_expr;
                        b_n.children.?.append(allocator.*, ret_n) catch return AstError.Out_Of_Memory;
                    } else {
                        const expr_n = try parseBinaryExpr(allocator, ast_data, 0);
                        if (expr_n) |en| b_n.children.?.append(allocator.*, en) catch return AstError.Out_Of_Memory;
                    }
                }
                body_expr = b_n;
            } else {
                body_expr = try parseBinaryExpr(allocator, ast_data, 0);
            }

            const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            n.node_type = ASTNodeType.MatchBody;
            n.token = cap_tok;
            n.left = body_expr;
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

        // ── .{expr, ...} tuple literal ──────────────────────────────────────
        // F13: used for format args: fmt.println("{}", .{name})
        TokenType.Dot => {
            ast_data.advance(); // eat '.'
            const next_tok = try ast_data.getToken();
            if (next_tok.token_type == TokenType.LeftBrace) {
                ast_data.advance(); // eat '{'
                const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
                n.node_type = ASTNodeType.ArrayLiteral; // reuse ArrayLiteral for tuples
                n.token = tok;
                n.children = try ast_utils.createChildList(allocator);
                var guard_t: usize = 0;
                while (ast_data.hasMore()) {
                    guard_t += 1;
                    if (guard_t > 200) break;
                    const cur: Token = try ast_data.getToken();
                    if (cur.token_type == TokenType.RightBrace) {
                        ast_data.advance();
                        break;
                    }
                    const elem = try parseBinaryExpr(allocator, ast_data, 0);
                    if (elem) |e| {
                        n.children.?.append(allocator.*, e) catch return AstError.Out_Of_Memory;
                    }
                    if (ast_data.hasMore()) {
                        const comma: Token = try ast_data.getToken();
                        if (comma.token_type == TokenType.Comma) ast_data.advance();
                    }
                }
                return n;
            }
            // plain dot without brace — not a tuple, back up
            ast_data.token_index -= 1;
            return null;
        },

        // ── &x address-of ────────────────────────────────────────────────────
        // F16: &x -> UnaryExpression(&, x)
        TokenType.And => {
            ast_data.advance(); // eat '&'
            const operand = try parsePrimary(allocator, ast_data);
            if (operand == null) return null;
            const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            n.node_type = ASTNodeType.UnaryExpression;
            n.token = tok;
            n.left = operand;
            return n;
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

        // F16 FIX: ptr.* dereference — Dot followed by Star means deref
        if (op_tok.token_type == TokenType.Dot) {
            const peek_star = ast_data.peekToken(0);
            if (peek_star != null and peek_star.?.token_type == TokenType.Star) {
                ast_data.advance(); // eat '*'
                // Wrap in UnaryExpression(".*", left) for c_expr to handle
                const deref: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
                deref.node_type = ASTNodeType.UnaryExpression;
                var star_tok = peek_star.?;
                star_tok.value = ".*"; // mark as deref
                deref.token = star_tok;
                deref.left = left;
                left = deref;
                continue;
            }
        }

        // recurse with prec+1 so left-associative operators work correctly
        const right: ?*ASTNode = try parseBinaryExpr(allocator, ast_data, prec + 1);

        if (right == null) {
            ast_data.error_detail = "Expected expression after operator";
            ast_data.error_token = op_tok;
            return AstError.Unexpected_Type;
        }

        const bin: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
        // Dot produces MemberAccess, everything else BinaryExpression
        if (op_tok.token_type == TokenType.Dot) {
            bin.node_type = ASTNodeType.MemberAccess;
        } else {
            bin.node_type = ASTNodeType.BinaryExpression;
        }
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
