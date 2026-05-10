const std = @import("std");
const node_mod = @import("../../ast/node.zig");
const convert_data = @import("../convert_data.zig");
const errors = @import("../errors.zig");

const c_expr = @import("c_expr.zig");

const ASTNode = node_mod.ASTNode;
const ConvertData = convert_data.ConvertData;
const ConvertError = errors.ConvertError;
const Allocator = std.mem.Allocator;

pub fn processAssignment(allocator: *Allocator, data: *ConvertData, node: *ASTNode, add_new_line: bool, add_tabs: bool) ConvertError!void {
    data.error_function = "processAssignment";

    if (node.left == null or node.token == null) {
        return ConvertError.Node_Is_Null;
    }

    if (add_tabs) {
        try data.addTab(allocator);
    }

    // C8 FIX: use printLValue so field access (c.value) uses '.' not '_'
    const target = try c_expr.printLValue(allocator, data, node.left.?);

    if (node.right == null) {
        try data.appendCodeFmt(allocator, "{s} {s};", .{ target, node.token.?.value });
    } else {
        const value = try c_expr.printExpression(allocator, data, node.right.?);
        try data.appendCodeFmt(allocator, "{s} {s} {s};", .{ target, node.token.?.value, value });
    }

    if (add_new_line) {
        try data.appendCode(allocator, "\n");
    }
}
