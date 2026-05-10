const std = @import("std");
const node_mod = @import("../../ast/node.zig");
const convert_data = @import("../convert_data.zig");
const errors = @import("../errors.zig");
const lexer = @import("../../lexer/lexer.zig");

const c_expr = @import("c_expr.zig");
const c_utils = @import("c_utils.zig");

const ASTNode = node_mod.ASTNode;
const ASTNodeType = node_mod.ASTNodeType;
const ConvertData = convert_data.ConvertData;
const ConvertError = errors.ConvertError;
const Allocator = std.mem.Allocator;

// Emit a variable or constant declaration.
// Variables without `mut` emit `const` in C (immutable by default).
// When there is no explicit type annotation, the type is inferred from the RHS.
pub fn processDeclaration(allocator: *Allocator, data: *ConvertData, node: *ASTNode, add_new_line: bool, add_tabs: bool) ConvertError!void {
    data.error_function = "processDeclaration";
    if (node.token == null) return ConvertError.Node_Is_Null;

    if (add_tabs) try data.addTab(allocator);

    const var_name = node.token.?.value;
    const is_const_decl = node.node_type == ASTNodeType.ConstDeclaration;
    const emit_const = is_const_decl or !node.is_mut;

    // resolve C type: explicit annotation first, then infer from RHS
    var c_type: []const u8 = "i32";
    if (node.left != null) {
        c_type = c_utils.nodeToCType(allocator, node.left.?) catch "i32";
    } else if (node.right != null) {
        c_type = inferTypeFromExpr(data, node.right.?);
    }

    // declaration with no value: `x : i32;`
    if (node.right == null) {
        if (emit_const) {
            try data.appendCodeFmt(allocator, "const {s} {s};", .{ c_type, var_name });
        } else {
            try data.appendCodeFmt(allocator, "{s} {s};", .{ c_type, var_name });
        }
        if (add_new_line) try data.appendCode(allocator, "\n");
        return;
    }

    const value = try c_expr.printExpression(allocator, data, node.right.?);

    if (emit_const) {
        try data.appendCodeFmt(allocator, "const {s} {s} = {s};", .{ c_type, var_name, value });
    } else {
        try data.appendCodeFmt(allocator, "{s} {s} = {s};", .{ c_type, var_name, value });
    }

    // track type so later declarations can infer from this variable
    data.var_types.put(var_name, c_type) catch {};

    if (add_new_line) try data.appendCode(allocator, "\n");
}

// Infer a C type from a right-hand expression when no explicit type was written.
// Used instead of __auto_type (GCC-only) so the output is portable.
fn inferTypeFromExpr(data: *ConvertData, expr: *ASTNode) []const u8 {
    return switch (expr.node_type) {
        .IntegerLiteral => "i32",
        .FloatLiteral => "f32",
        .BoolLiteral => "bool",
        .StringLiteral => "RazenString",
        .Identifier => data.lookupVarType(expr.token.?.value) orelse "i32",
        .BinaryExpression => if (expr.left != null) inferTypeFromExpr(data, expr.left.?) else "i32",
        else => "i32",
    };
}
