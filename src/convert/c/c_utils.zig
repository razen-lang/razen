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
        TokenType.I1, TokenType.I2, TokenType.I4, TokenType.I8 => return "i8",
        TokenType.U1, TokenType.U2, TokenType.U4, TokenType.U8 => return "u8",
        TokenType.I16 => return "i16",
        TokenType.U16 => return "u16",
        TokenType.Int, TokenType.I32 => return "i32",
        TokenType.Uint, TokenType.U32 => return "u32",
        TokenType.I64 => return "i64",
        TokenType.U64 => return "u64",
        TokenType.I128 => return "i128",
        TokenType.U128 => return "u128",
        TokenType.Isize => return "isize",
        TokenType.Usize => return "usize",
        TokenType.Float, TokenType.F32 => return "f32",
        TokenType.F64 => return "f64",
        TokenType.F128 => return "f128",
        TokenType.String => return "RazenString",
        TokenType.Str => return "RazenStr",
        TokenType.Char => return "razen_char",
        TokenType.Bool => return "bool",
        TokenType.Void => return "void",
        TokenType.Noret => return "noret",
        TokenType.Any => return "any",
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

