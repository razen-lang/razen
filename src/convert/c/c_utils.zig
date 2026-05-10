const std = @import("std");
const lexer = @import("../../lexer/lexer.zig");
const token = @import("../../lexer/token.zig");
const node_mod = @import("../../ast/node.zig");
const TokenType = token.TokenType;
const ASTNode = node_mod.ASTNode;
const ASTNodeType = node_mod.ASTNodeType;
const Allocator = std.mem.Allocator;

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
        TokenType.Str => return "const char*",
        TokenType.Char => return "char",
        TokenType.Bool => return "bool",
        TokenType.Void => return "void",
        else => return null,
    }
}

// Converts a complex AST type node to a C string (allocates on the arena)
pub fn nodeToCType(allocator: *Allocator, node: *ASTNode) ![]const u8 {
    if (node.node_type == ASTNodeType.ArrayType) {
        // [T] -> T*
        const inner = try nodeToCType(allocator, node.left.?);
        return try std.fmt.allocPrint(allocator.*, "{s}*", .{inner});
    }
    
    if (node.node_type == ASTNodeType.VarType) {
        const tok = node.token orelse return "void";
        
        // primitive type
        if (convertToCType(tok.token_type)) |prim| {
            // handle pointers *T -> prim*
            if (node.left != null) {
                 const inner = try nodeToCType(allocator, node.left.?);
                 if (tok.token_type == TokenType.Star) {
                     return try std.fmt.allocPrint(allocator.*, "{s}*", .{inner});
                 }
                 // for now handle !T or ?T as just T
                 return inner;
            }
            return prim;
        }
        
        // identifier type like State, NetErr
        if (tok.token_type == TokenType.Identifier) {
            return tok.value;
        }

        // @Self etc.
        if (tok.token_type == TokenType.At) {
            // Self* in C would just be `void*` for now or the struct type if we know it.
            // We'll output `void*` or the value for simplicity.
            return "void*";
        }
        
        // user-defined struct/enum pointer: *State
        if (tok.token_type == TokenType.Star and node.left != null) {
             const inner = try nodeToCType(allocator, node.left.?);
             return try std.fmt.allocPrint(allocator.*, "{s}*", .{inner});
        }
        
        return tok.value;
    }
    
    return "void";
}

