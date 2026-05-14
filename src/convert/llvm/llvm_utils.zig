const lexer = @import("../../lexer/lexer.zig");
const token_mod = @import("../../lexer/token.zig");
const node_mod = @import("../../ast/node.zig");
const Token = lexer.Token;
const TokenType = token_mod.TokenType;
const ASTNode = node_mod.ASTNode;

/// Resolve a type node chain to its LLVM IR type string.
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

pub fn convertToLLVMType(tok: Token) ?[]const u8 {
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

/// Returns the LLVM instruction name for a Razen operator.
/// Does NOT include the type suffix — caller formats with the type.
pub fn convertToLLVMOperator(op: []const u8, llvm_type: []const u8) ?[]const u8 {
    if (isFloatType(llvm_type)) {
        if (eql(op, "+")) return "fadd";
        if (eql(op, "-")) return "fsub";
        if (eql(op, "*")) return "fmul";
        if (eql(op, "/")) return "fdiv";
        return null;
    }
    if (eql(op, "+")) return "add";
    if (eql(op, "-")) return "sub";
    if (eql(op, "*")) return "mul";
    if (eql(op, "/")) return "sdiv";
    if (eql(op, "%")) return "srem";
    if (eql(op, "&")) return "and";
    if (eql(op, "|")) return "or";
    if (eql(op, "^")) return "xor";
    if (eql(op, "<<")) return "shl";
    if (eql(op, ">>")) return "ashr";
    return null;
}

/// Returns the full LLVM IR comparison predicate and type for a Razen comparison op.
pub fn convertToLLVMCmp(op: []const u8, llvm_type: []const u8) ?[]const u8 {
    if (isFloatType(llvm_type)) {
        if (eql(op, "==")) return "fcmp oeq";
        if (eql(op, "!=")) return "fcmp one";
        if (eql(op, "<")) return "fcmp olt";
        if (eql(op, "<=")) return "fcmp ole";
        if (eql(op, ">")) return "fcmp ogt";
        if (eql(op, ">=")) return "fcmp oge";
        return null;
    }
    if (eql(op, "==")) return "icmp eq";
    if (eql(op, "!=")) return "icmp ne";
    if (eql(op, "<")) return "icmp slt";
    if (eql(op, "<=")) return "icmp sle";
    if (eql(op, ">")) return "icmp sgt";
    if (eql(op, ">=")) return "icmp sge";
    return null;
}

pub fn isFloatType(t: []const u8) bool {
    return eql(t, "half") or eql(t, "float") or eql(t, "double") or eql(t, "fp128");
}

fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (ca != cb) return false;
    }
    return true;
}
