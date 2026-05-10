const std = @import("std");
const lexer = @import("../../lexer/lexer.zig");
const token = @import("../../lexer/token.zig");
const TokenType = token.TokenType;

pub fn convertToCType(tt: TokenType) ?[]const u8 {
    switch (tt) {
        TokenType.I8 => return "int8_t",
        TokenType.U8 => return "uint8_t",
        TokenType.I16 => return "int16_t",
        TokenType.U16 => return "uint16_t",
        TokenType.Int, TokenType.I32 => return "int32_t",
        TokenType.Uint, TokenType.U32 => return "uint32_t",
        TokenType.I64 => return "int64_t",
        TokenType.U64 => return "uint64_t",
        TokenType.Usize => return "size_t",
        TokenType.Float, TokenType.F32 => return "float",
        TokenType.F64 => return "double",
        TokenType.String => return "const char*",
        TokenType.Char => return "char",
        TokenType.Bool => return "bool",
        TokenType.Void => return "void",
        else => return null,
    }
}
