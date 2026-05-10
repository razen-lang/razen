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

pub fn processDeclaration(allocator: *Allocator, data: *ConvertData, node: *ASTNode, add_new_line: bool, add_tabs: bool) ConvertError!void {
    data.error_function = "processDeclaration";

    if (node.token == null) return ConvertError.Node_Is_Null;

    if (add_tabs) {
        try data.addTab(allocator);
    }

    const var_name = node.token.?.value;
    // Bug 5: ConstDeclaration is always const
    // Bug 3: VarDeclaration without `mut` is also const
    const is_const_decl = node.node_type == ASTNodeType.ConstDeclaration;
    const emit_const = is_const_decl or !node.is_mut;

    // Bug 4: resolve type — explicit type annotation first, then infer from RHS
    var c_type: []const u8 = "i32"; // safe portable default instead of __auto_type
    if (node.left != null) {
        c_type = c_utils.nodeToCType(allocator, node.left.?) catch "i32";
    } else if (node.right != null) {
        // Bug 4: no explicit type — infer from the right-hand expression
        c_type = inferTypeFromExpr(data, node.right.?);
    }

    // No-value declaration: e.g. `x : i32;`
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

    // Bug 4: record this variable's type so later uses can look it up
    data.var_types.put(var_name, c_type) catch {};

    if (add_new_line) {
        try data.appendCode(allocator, "\n");
    }
}

/// Bug 4: infer a portable C type from a right-hand AST expression.
/// Called only when the declaration has no explicit type annotation.
fn inferTypeFromExpr(data: *ConvertData, expr: *ASTNode) []const u8 {
    return switch (expr.node_type) {
        .IntegerLiteral  => "i32",
        .FloatLiteral    => "f32",
        .BoolLiteral     => "bool",
        .StringLiteral   => "RazenString",
        // If it's an identifier, look up whatever type we already resolved for it
        .Identifier      => data.lookupVarType(expr.token.?.value) orelse "i32",
        // Binary expression: use the type of the left operand
        .BinaryExpression => if (expr.left != null) inferTypeFromExpr(data, expr.left.?) else "i32",
        else             => "i32",
    };
}
