const std = @import("std");
const lexer = @import("../lexer/lexer.zig");
const node = @import("node.zig");
const errors = @import("errors.zig");
const ArrayList = std.ArrayList;
const Token = lexer.Token;
const ASTNode = node.ASTNode;
const AstError = errors.AstError;

/// Shared state threaded through every AST-building function.
/// Mirrors the Video 2 tutorial's ASTData pattern.
pub const ASTData = struct {
    ast_nodes: *ArrayList(*ASTNode),
    token_index: usize = 0,
    token_list: *const ArrayList(Token),

    // Error diagnostics (set before returning an error)
    error_detail: ?[]const u8 = null,
    error_token: ?Token = null,
    error_function: ?[]const u8 = null,

    // ── Token access helpers ───────────────────────────────────────────────

    /// Return the current token (does NOT advance).
    pub fn getToken(self: *ASTData) AstError!Token {
        if (self.token_index >= self.token_list.items.len) {
            return AstError.Index_Out_Of_Range;
        }
        const tok: Token = self.token_list.items[self.token_index];
        self.error_token = tok;
        return tok;
    }

    /// Advance then return the next token.
    pub fn getNextToken(self: *ASTData) AstError!Token {
        self.token_index += 1;
        if (self.token_index >= self.token_list.items.len) {
            return AstError.Index_Out_Of_Range;
        }
        const tok: Token = self.token_list.items[self.token_index];
        self.error_token = tok;
        return tok;
    }

    /// Peek at the token at `offset` positions ahead (non-destructive).
    pub fn peekToken(self: *const ASTData, offset: usize) ?Token {
        const idx = self.token_index + offset;
        if (idx >= self.token_list.items.len) return null;
        return self.token_list.items[idx];
    }

    /// Advance the index by one, returning an error if already at end.
    pub fn incrementIndex(self: *ASTData) AstError!void {
        self.token_index += 1;
        if (self.token_index >= self.token_list.items.len) {
            return AstError.Index_Out_Of_Range;
        }
    }

    /// Advance the index – tolerates reaching the very end (EOF is OK).
    pub fn advance(self: *ASTData) void {
        if (self.token_index < self.token_list.items.len) {
            self.token_index += 1;
        }
    }

    /// Convenience: store error detail + token together.
    pub fn setError(self: *ASTData, detail: []const u8, tok: Token) void {
        self.error_detail = detail;
        self.error_token = tok;
    }

    /// True iff there are more tokens to consume.
    pub fn hasMore(self: *const ASTData) bool {
        return self.token_index < self.token_list.items.len;
    }
};
