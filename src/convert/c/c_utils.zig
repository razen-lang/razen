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

/// Converts an AST type node to a C type string.
/// current_struct: pass the enclosing struct name so @Self resolves correctly; null otherwise.
pub fn nodeToCTypeWithSelf(allocator: *Allocator, node: *ASTNode, current_struct: ?[]const u8) anyerror![]const u8 {
    if (node.node_type == ASTNodeType.ArrayType) {
        const inner = try nodeToCTypeWithSelf(allocator, node.left.?, current_struct);
        return try std.fmt.allocPrint(allocator.*, "{s}*", .{inner});
    }

    if (node.node_type == ASTNodeType.VarType) {
        const tok = node.token orelse return "void";

        // F1 FIX: ?T optional -> Option_<T> struct
        if (tok.token_type == TokenType.QuestionMark and node.left != null) {
            const inner = try nodeToCTypeWithSelf(allocator, node.left.?, current_struct);
            return std.fmt.allocPrint(allocator.*, "Option_{s}", .{inner}) catch "void*";
        }

        // F2 FIX: !T failable (anonymous) -> Result_<T>
        //         Error!T typed error -> <Error>_Result (with specific error type)
        if (tok.token_type == TokenType.ExclamationMark and node.left != null) {
            if (node.left.?.node_type == ASTNodeType.VarType and
                node.left.?.left != null)
            {
                // Error!T: tok=!, left=ErrorType, left.left=T
                const err_type = try nodeToCTypeWithSelf(allocator, node.left.?, current_struct);
                const val_type = try nodeToCTypeWithSelf(allocator, node.left.?.left.?, current_struct);
                return std.fmt.allocPrint(allocator.*, "{s}_Result_{s}", .{ err_type, val_type }) catch "void*";
            }
            // plain !T
            const inner = try nodeToCTypeWithSelf(allocator, node.left.?, current_struct);
            return std.fmt.allocPrint(allocator.*, "Result_{s}", .{inner}) catch "void*";
        }

        // primitive type
        if (convertToCType(tok.token_type)) |prim| {
            if (node.left != null) {
                const inner = try nodeToCTypeWithSelf(allocator, node.left.?, current_struct);
                if (tok.token_type == TokenType.Star) {
                    return try std.fmt.allocPrint(allocator.*, "{s}*", .{inner});
                }
                return inner;
            }
            return prim;
        }

        // C4 FIX: @Self → resolve to current struct/behave name.
        // The parser eats '@' and stores the name token directly as Identifier "Self".
        // MUST be checked before the generic Identifier fallback below.
        if (tok.token_type == TokenType.Identifier and std.mem.eql(u8, tok.value, "Self")) {
            if (current_struct) |name| return name;
            return "void*"; // @Self used outside struct context — safe fallback
        }

        if (tok.token_type == TokenType.At) {
            return "void*"; // bare @ without name
        }

        // identifier type like State, NetErr, user-defined names
        if (tok.token_type == TokenType.Identifier) {
            return tok.value;
        }

        // pointer to user type: *State
        if (tok.token_type == TokenType.Star and node.left != null) {
            const inner = try nodeToCTypeWithSelf(allocator, node.left.?, current_struct);
            return try std.fmt.allocPrint(allocator.*, "{s}*", .{inner});
        }

        return tok.value;
    }

    return "void";
}

/// Convenience wrapper with no struct context (most callers use this).
pub fn nodeToCType(allocator: *Allocator, node: *ASTNode) anyerror![]const u8 {
    return nodeToCTypeWithSelf(allocator, node, null);
}
