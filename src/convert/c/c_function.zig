const std = @import("std");
const node_mod = @import("../../ast/node.zig");
const convert_data = @import("../convert_data.zig");
const errors = @import("../errors.zig");
const lexer = @import("../../lexer/lexer.zig");

const c_utils = @import("c_utils.zig");
const c_body = @import("c_body.zig");

const ASTNode = node_mod.ASTNode;
const ASTNodeType = node_mod.ASTNodeType;
const ConvertData = convert_data.ConvertData;
const ConvertError = errors.ConvertError;
const Allocator = std.mem.Allocator;

pub fn processFunctionDeclaration(allocator: *Allocator, data: *ConvertData, node: *ASTNode) ConvertError!void {
    data.error_function = "processFunctionDeclaration";

    if (node.token == null) return ConvertError.Node_Is_Null;

    const func_name = node.token.?.value;
    const is_main = std.mem.eql(u8, func_name, "main");

    var return_type: []const u8 = "void";
    if (node.left != null and node.left.?.left != null) {
        return_type = c_utils.nodeToCType(allocator, node.left.?.left.?) catch "void";
    }
    // After getting return_type, force main to use "int"
    if (is_main) {
        return_type = "int";
    }

    try data.appendCodeFmt(allocator, "{s} {s}(", .{ return_type, func_name });

    if (node.middle != null) {
        try processParameters(allocator, data, node.middle.?);
    }

    try data.appendCode(allocator, ") {\n");
    data.incrementIndexCount();

    if (node.right != null) {
        try c_body.processBody(allocator, data, node.right.?);
    }

    if (is_main and !data.last_statement_was_return) {
        try data.addTab(allocator);
        try data.appendCode(allocator, "return 0;\n");
    }

    data.decrementIndexCount();
    try data.appendCode(allocator, "}\n\n");
}

fn processParameters(allocator: *Allocator, data: *ConvertData, params_node: *ASTNode) ConvertError!void {
    if (params_node.children == null) return;

    for (params_node.children.?.items, 0..) |child, i| {
        if (child.token == null or child.left == null) return ConvertError.Node_Is_Null;

        const p_name = child.token.?.value;
        const p_type = c_utils.nodeToCType(allocator, child.left.?) catch "void*";

        try data.appendCodeFmt(allocator, "{s} {s}", .{ p_type, p_name });

        if (i < params_node.children.?.items.len - 1) {
            try data.appendCode(allocator, ", ");
        }
    }
}
