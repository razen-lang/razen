const std = @import("std");
const lexer = @import("../lexer/lexer.zig");
const token = @import("../lexer/token.zig");
const errors = @import("../lexer/errors.zig");
const helpers = @import("helpers.zig");
const Allocator = std.mem.Allocator;
const Token = lexer.Token;
const ArrayList = std.ArrayList;
const Lexer = lexer.Lexer;
const ParseError = errors.ParseError;
const TokenType = token.TokenType;
const print = std.debug.print;

pub fn parseToTokens(allocator: *Allocator, source: []const u8) !*ArrayList(Token) {
    print("\t{s}Parsing{s}\t\t\t\t", .{ lexer.GREY, lexer.RESET });

    const token_list = try allocator.*.create(ArrayList(Token));
    token_list.* = try ArrayList(Token).initCapacity(allocator.*, 0);

    var lex_data = Lexer{
        .token_list = token_list,
        .source = source,
    };

    if (lex_data.source.len == 0) {
        return ParseError.Code_Length_Is_Zero;
    }

    const STRING_LENGTH: usize = source.len;
    while (lex_data.character_index < STRING_LENGTH) {
        try processCharacter(allocator, &lex_data);
    }
    print("{s}Done{s}\n", .{ lexer.CYAN, lexer.RESET });
    return token_list;
}

fn shouldSkip(allocator: *Allocator, lex_data: *Lexer) !bool {
    lex_data.character_count += 1;
    if (lex_data.last_token != null) {
        if (lex_data.last_token.?.token_type == TokenType.Comment) {
            lex_data.was_comment = true;
        }
    }

    const currentChar: u8 = lex_data.source[lex_data.character_index];

    if (currentChar == '\n') {
        if (lex_data.was_comment == true) {
            try lex_data.token_list.append(
                allocator.*,
                Token{ .value = "", .token_type = TokenType.EndComment, .line = lex_data.line_count, .character = lex_data.character_count },
            );
            lex_data.was_comment = false;
        }
        lex_data.line_count += 1;
        lex_data.character_count = 0;
        lex_data.character_index += 1;
        return true;
    }
    const is_special_char: bool =
        currentChar == '\r' or
        currentChar == '\t' or
        currentChar == ' ' or
        currentChar == '\\';

    if (is_special_char == true) {
        lex_data.character_index += 1;
        return true;
    }
    return false;
}

fn processCharacter(allocator: *Allocator, lex_data: *Lexer) !void {
    if (try shouldSkip(allocator, lex_data) == true) {
        return;
    }

    const previous_character_index: usize = lex_data.character_index;
    const token_here: Token = try getToken(allocator, lex_data);

    if (previous_character_index == lex_data.character_index) {
        lex_data.character_index += 1;
    }

    try lex_data.token_list.append(allocator.*, token_here);
    lex_data.last_token = token_here;
}

fn getToken(allocator: *Allocator, lex_data: *Lexer) !Token {
    const current_char: u8 = lex_data.source[lex_data.character_index];

    if (current_char == '"') {
        return readString(allocator, lex_data);
    }
    if (current_char == '\'') {
        return readChar(allocator, lex_data);
    }
    if (helpers.isOperator(current_char)) {
        return readOperator(allocator, lex_data);
    }
    if (helpers.isSeparator(current_char)) {
        return readSeparator(allocator, lex_data);
    }

    return ReadWord(allocator, lex_data);
}

fn readString(allocator: *Allocator, lex_data: *Lexer) !Token {
    var text_builder: ArrayList(u8) = try ArrayList(u8).initCapacity(allocator.*, 0);

    //go past the '"'
    lex_data.*.character_index += 1;

    while (lex_data.character_index < lex_data.source.len) {
        const char: u8 = lex_data.source[lex_data.character_index];
        if (char == '"') {
            lex_data.character_index += 1;
            const value: []u8 = try text_builder.toOwnedSlice(allocator.*);

            return Token{
                .value = value,
                .token_type = TokenType.StringValue,
                .line = lex_data.line_count,
                .character = lex_data.character_count,
            };
        }
        try text_builder.append(allocator.*, char);
        lex_data.character_index += 1;
    }

    return ParseError.Unterminated_String;
}

fn readSeparator(allocator: *Allocator, lex_data: *Lexer) !Token {
    const char: []u8 = try allocator.alloc(u8, 1);
    char[0] = lex_data.source[lex_data.character_index];

    lex_data.character_index += 1;
    const tokenText: []const u8 = char[0..];
    return Token{ .value = tokenText, .token_type = helpers.getTokenType(tokenText), .line = lex_data.line_count, .character = lex_data.character_count };
}

fn readChar(allocator: *Allocator, lex_data: *Lexer) !Token {
    lex_data.character_index += 1;
    if (lex_data.character_index >= lex_data.source.len) {
        return ParseError.Unexpected_Value;
    }

    const char_value: []u8 = try allocator.alloc(u8, 1);
    char_value[0] = lex_data.source[lex_data.character_index];
    lex_data.character_index += 1;

    if (lex_data.character_index >= lex_data.source.len) {
        return ParseError.Unexpected_Value;
    }

    if (lex_data.source[lex_data.character_index] != '\'') {
        return ParseError.Unterminated_Char;
    }
    lex_data.character_index += 1;

    return Token{ .value = char_value, .token_type = TokenType.CharValue, .line = lex_data.line_count, .character = lex_data.character_count };
}

fn readOperator(allocator: *Allocator, lex_data: *Lexer) !Token {
    var text_builder: ArrayList(u8) = try ArrayList(u8).initCapacity(allocator.*, 0);

    const char: u8 = lex_data.source[lex_data.character_index];
    try text_builder.append(allocator.*, char);

    lex_data.character_index += 1;

    // Lookahead for compound operators like "==", "!="
    if (lex_data.character_index < lex_data.source.len) {
        const next: u8 = lex_data.source[lex_data.character_index];
        if (helpers.isOperator(next)) {
            try text_builder.append(allocator.*, next);
            lex_data.character_index += 1;
        }
    }

    const text: []u8 = try text_builder.toOwnedSlice(allocator.*);
    return Token{ .value = text, .token_type = helpers.getTokenType(text), .line = lex_data.line_count, .character = lex_data.character_count };
}

fn ReadWord(allocator: *Allocator, lex_data: *Lexer) !Token {
    var text_builder: ArrayList(u8) = try ArrayList(u8).initCapacity(allocator.*, 0);

    while (lex_data.character_index < lex_data.source.len) {
        const c: u8 = lex_data.source[lex_data.character_index];

        if (helpers.isLetterOrDigit(c) or c == '_') {
            try text_builder.append(allocator.*, c);
            lex_data.character_index += 1;
        } else {
            break;
        }
    }

    const value: []u8 = try text_builder.toOwnedSlice(allocator.*);
    return Token{ .value = value, .token_type = helpers.getTokenType(value), .line = lex_data.line_count, .character = lex_data.character_count };
}
