const std = @import("std");
const node_mod = @import("../../ast/node.zig");
const convert_data = @import("../convert_data.zig");
const errors = @import("../errors.zig");
const lexer = @import("../../lexer/lexer.zig");

const c_expr = @import("c_expr.zig");

const ASTNode = node_mod.ASTNode;
const ConvertData = convert_data.ConvertData;
const ConvertError = errors.ConvertError;
const Allocator = std.mem.Allocator;

pub fn processDeclaration(allocator: *Allocator, data: *ConvertData, node: *ASTNode, add_new_line: bool, add_tabs: bool) ConvertError!void {
    data.error_function = "processDeclaration";

    if (node.token == null) return ConvertError.Node_Is_Null;

    if (add_tabs) {
        try data.addTab(allocator);
    }

    var c_type: []const u8 = "__auto_type";
    if (node.left != null) {
        const c_utils = @import("c_utils.zig");
        c_type = c_utils.nodeToCType(allocator, node.left.?) catch "__auto_type";
    }

    if (node.right == null) {
        try data.appendCodeFmt(allocator, "{s} {s};", .{ c_type, node.token.?.value });
        if (add_new_line) {
            try data.appendCode(allocator, "\n");
        }
        return;
    }

    const value = try c_expr.printExpression(allocator, data, node.right.?);
    try data.appendCodeFmt(allocator, "{s} {s} = {s};", .{ c_type, node.token.?.value, value });

    if (add_new_line) {
        try data.appendCode(allocator, "\n");
    }
}
