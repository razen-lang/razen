const std = @import("std");
const lexer = @import("../lexer/lexer.zig");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const Token = lexer.Token;
//const ASTData = lexer.ASTData;
//const ASTNode = lexer.ASTNode;
const Allocator = std.mem.Allocator;

pub fn printTokens(token_list: *ArrayList(Token)) void {
    print("\nPrinting Tokens:\n", .{});

    const LENGTH: usize = token_list.items.len;
    if (LENGTH == 0) {
        print("\tzero length: {}\n", .{LENGTH});
        print("\nNo tokens to print.\n", .{});
        return;
    }

    for (0..LENGTH) |i| {
        const token = token_list.items[i];
        print("\t{s}Token Type:{s} {}, {s}Value:{s} {s}'{s}'{s}, {s}Line:{s} {d}, {s}Character:{s} {d}\n", .{
            lexer.GREY,
            lexer.RESET,
            token.token_type,
            lexer.GREY,
            lexer.RESET,
            lexer.ORANGE,
            token.value,
            lexer.RESET,
            lexer.GREY,
            lexer.RESET,
            token.line,
            lexer.GREY,
            lexer.RESET,
            token.character,
        });
    }
}
