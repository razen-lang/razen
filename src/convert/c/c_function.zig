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
    // Bug 6: detect ext func (routed as ExtDeclaration from c_convert)
    const is_ext = node.node_type == ASTNodeType.ExtDeclaration;

    var return_type: []const u8 = "void";
    if (node.left != null and node.left.?.left != null) {
        return_type = c_utils.nodeToCType(allocator, node.left.?.left.?) catch "void";
    }
    // Bug 1: force main() return type to int (already present, kept for safety)
    if (is_main) {
        return_type = "int";
    }

    // Bug 2: blank line before every function for readability
    try data.appendCode(allocator, "\n");

    // Bug 6: extern declaration — emit prototype only, no body
    if (is_ext) {
        try data.appendCodeFmt(allocator, "extern {s} {s}(", .{ return_type, func_name });
        if (node.middle != null) {
            try processParameters(allocator, data, node.middle.?);
        }
        try data.appendCode(allocator, ");\n");
        data.node_index += 1;
        return;
    }

    try data.appendCodeFmt(allocator, "{s} {s}(", .{ return_type, func_name });

    if (node.middle != null) {
        try processParameters(allocator, data, node.middle.?);
    }

    try data.appendCode(allocator, ") {\n");
    data.incrementIndexCount();

    // Bug 7: clear deferred list at the start of each new function
    data.deferred_stmts.clearRetainingCapacity();

    if (node.right != null) {
        try c_body.processBody(allocator, data, node.right.?);
    }

    // Bug 7: emit any remaining defers at end of function body (LIFO)
    try emitDeferredStatements(allocator, data);
    data.deferred_stmts.clearRetainingCapacity();

    if (is_main and !data.last_statement_was_return) {
        try data.addTab(allocator);
        try data.appendCode(allocator, "return 0;\n");
    }

    data.decrementIndexCount();
    try data.appendCode(allocator, "}\n");
    data.node_index += 1;
}

/// Bug 7: emit deferred statements in reverse (LIFO) order.
/// Called both at end-of-function and before every return.
pub fn emitDeferredStatements(allocator: *Allocator, data: *ConvertData) ConvertError!void {
    if (data.deferred_stmts.items.len == 0) return;
    var i = data.deferred_stmts.items.len;
    while (i > 0) {
        i -= 1;
        try c_body.processStatement(allocator, data, data.deferred_stmts.items[i]);
    }
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
