// llvm_utils.zig — type and operator mapping for Razen → LLVM IR.
// Mirrors the tutorial's llvm_utils.zig, adapted to Razen's token field names.

const lexer = @import("../../lexer/lexer.zig");
const token_mod = @import("../../lexer/token.zig");
const node_mod = @import("../../ast/node.zig");
const Token = lexer.Token;
const TokenType = token_mod.TokenType;
const ASTNode = node_mod.ASTNode;

/// Resolve a type node chain to its LLVM IR type string.
/// Handles pointer/reference types (token is `*` or `&`).
pub fn resolveTypeNode(type_node: *ASTNode) []const u8 {
    if (type_node.token) |tok| {
        if (tok.token_type == TokenType.Star or tok.token_type == TokenType.And)
            return "ptr";
    }
    var base = type_node;
    while (base.left != null) base = base.left.?;
    if (base.token) |tok| {
        if (convertToLLVMType(tok)) |t| return t;
    }
    return "i32";
}

/// Map a Razen Token to its LLVM IR type string.
/// Returns null when no direct mapping exists.
pub fn convertToLLVMType(tok: Token) ?[]const u8 {
    // Razen uses tok.token_type (not tok.Type as in the tutorial)
    return switch (tok.token_type) {
        .I1, .U1 => "i1",
        .I2, .U2 => "i2",
        .I4, .U4 => "i4",
        .I8, .U8, .Char => "i8",
        .I16, .U16 => "i16",
        .I32, .U32, .Int, .Uint => "i32",
        .I64, .U64, .Usize, .Isize => "i64",
        .I128, .U128 => "i128",
        .F16 => "half",
        .F32, .Float => "float",
        .F64 => "double",
        .F128 => "fp128",
        .Bool => "i1",
        .Void => "void",
        else => null,
    };
}

/// Map a Razen binary operator string to an LLVM integer instruction
/// (includes type suffix, e.g. "add i32" — matching the tutorial style).
pub fn convertToLLVMOperator(op: []const u8) ?[]const u8 {
    if (eql(op, "+")) return "add i32";
    if (eql(op, "-")) return "sub i32";
    if (eql(op, "*")) return "mul i32";
    if (eql(op, "/")) return "sdiv i32";
    if (eql(op, "%")) return "srem i32";
    if (eql(op, "&")) return "and i32";
    if (eql(op, "|")) return "or i32";
    if (eql(op, "^")) return "xor i32";
    if (eql(op, "<<")) return "shl i32";
    if (eql(op, ">>")) return "ashr i32";
    return null;
}

/// Map a comparison operator to an `icmp` predicate (signed).
pub fn convertToLLVMCmp(op: []const u8) ?[]const u8 {
    if (eql(op, "==")) return "icmp eq i32";
    if (eql(op, "!=")) return "icmp ne i32";
    if (eql(op, "<")) return "icmp slt i32";
    if (eql(op, "<=")) return "icmp sle i32";
    if (eql(op, ">")) return "icmp sgt i32";
    if (eql(op, ">=")) return "icmp sge i32";
    return null;
}

fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (ca != cb) return false;
    }
    return true;
}
