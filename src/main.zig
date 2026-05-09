const std = @import("std");
const code_samples = @import("samples/sample1.zig");
const parser = @import("parser/parser.zig");
const lexer = @import("lexer/lexer.zig");
const token = @import("lexer/token.zig");
const debugging = @import("debug/debug.zig");
const print = std.debug.print;
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const Token = lexer.Token;

fn convertCode(source: []const u8) void {
    print("Code: \n{s}\n", .{source});

    const page_allocator = std.heap.page_allocator;
    var arena = ArenaAllocator.init(page_allocator);
    defer arena.deinit();

    var arena_allocator: Allocator = arena.allocator();

    //parse code
    const token_list: *std.ArrayList(Token) = parser.parseToTokens(&arena_allocator, source) catch |err| {
        print("Error {}\n", .{err});
        return;
    };
    debugging.printTokens(token_list);
}

pub fn main() void {
    print("Klar Lang Phase 1!\n", .{});
    convertCode(code_samples.RETURN_ZERO);
}
