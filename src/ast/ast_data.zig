const std = @import("std");
const lexer = @import("../lexer/lexer.zig");
const node = @import("node.zig");
const errors = @import("errors.zig");
const ArrayList = std.ArrayList;
const Token = lexer.Token;
const ASTNode = node.ASTNode;
const AstError = errors.AstError;

// ASTData is basically the "cursor" we thread through all the
// AST-building functions. It keeps track of where we are in the
// token list and holds diagnostic info if something goes wrong.
pub const ASTData = struct {
    ast_nodes: *ArrayList(*ASTNode),
    token_index: usize = 0,
    token_list: *const ArrayList(Token),

    // filled in right before returning an error so we know what went wrong
    error_detail: ?[]const u8 = null,
    error_token: ?Token = null,
    error_function: ?[]const u8 = null,

    // ── token access helpers ───────────────────────────────────────────────

    // grab the current token without moving forward
    pub fn getToken(self: *ASTData) AstError!Token {
        if (self.token_index >= self.token_list.items.len) {
            return AstError.Index_Out_Of_Range;
        }
        const tok: Token = self.token_list.items[self.token_index];
        self.error_token = tok;
        return tok;
    }

    // step forward and then return the token we landed on
    pub fn getNextToken(self: *ASTData) AstError!Token {
        self.token_index += 1;
        if (self.token_index >= self.token_list.items.len) {
            return AstError.Index_Out_Of_Range;
        }
        const tok: Token = self.token_list.items[self.token_index];
        self.error_token = tok;
        return tok;
    }

    // look ahead without changing position — handy for lookahead decisions
    pub fn peekToken(self: *const ASTData, offset: usize) ?Token {
        const idx = self.token_index + offset;
        if (idx >= self.token_list.items.len) return null;
        return self.token_list.items[idx];
    }

    // move forward one step, returns an error if we're already at the end
    pub fn incrementIndex(self: *ASTData) AstError!void {
        self.token_index += 1;
        if (self.token_index >= self.token_list.items.len) {
            return AstError.Index_Out_Of_Range;
        }
    }

    // same as incrementIndex but doesn't break if we hit EOF — that's fine
    pub fn advance(self: *ASTData) void {
        if (self.token_index < self.token_list.items.len) {
            self.token_index += 1;
        }
    }

    // store error info together so we have context when something blows up
    pub fn setError(self: *ASTData, detail: []const u8, tok: Token) void {
        self.error_detail = detail;
        self.error_token = tok;
    }

    // returns true as long as there are still tokens left to consume
    pub fn hasMore(self: *const ASTData) bool {
        return self.token_index < self.token_list.items.len;
    }
};
