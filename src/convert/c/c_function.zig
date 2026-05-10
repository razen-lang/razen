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
    const is_ext = node.node_type == ASTNodeType.ExtDeclaration;

    // F9/F10: determine linkage prefix
    // const func → static inline (F10)
    // pub func   → no prefix (externally visible)
    // plain func → static (file-private, F9)
    const is_const_func = node.is_const;
    const is_pub = node.is_pub;

    // Return type — use nodeToCTypeWithSelf so ?T / !T / Error!T all resolve
    var return_type: []const u8 = "void";
    if (node.left != null and node.left.?.left != null) {
        return_type = c_utils.nodeToCTypeWithSelf(allocator, node.left.?.left.?, data.current_struct_name) catch "void";
    }
    if (is_main) return_type = "int"; // Bug 1

    // blank line before every function (Bug 2)
    try data.appendCode(allocator, "\n");

    // Bug 6: extern — emit prototype only, no body
    if (is_ext) {
        try data.appendCodeFmt(allocator, "extern {s} {s}(", .{ return_type, func_name });
        if (node.middle != null) try processParameters(allocator, data, node.middle.?);
        try data.appendCode(allocator, ");\n");
        data.node_index += 1;
        return;
    }

    // F9+F10: emit correct linkage prefix
    if (is_const_func) {
        // F10: const func → static inline (can be evaluated at compile time by C compiler)
        try data.appendCodeFmt(allocator, "static inline {s} {s}(", .{ return_type, func_name });
    } else if (!is_pub and !is_main) {
        // F9: file-private function
        try data.appendCodeFmt(allocator, "static {s} {s}(", .{ return_type, func_name });
    } else {
        // pub func or main — no prefix
        try data.appendCodeFmt(allocator, "{s} {s}(", .{ return_type, func_name });
    }

    if (node.middle != null) try processParameters(allocator, data, node.middle.?);
    try data.appendCode(allocator, ") {\n");
    data.incrementIndexCount();

    // Bug 7: clear deferred list at start of each function
    data.deferred_stmts.clearRetainingCapacity();

    if (node.right != null) try c_body.processBody(allocator, data, node.right.?);

    // Bug 7: flush remaining defers at end of function (LIFO)
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

/// Bug 7: flush deferred statements in LIFO order.
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
    const items = params_node.children.?.items;

    for (items, 0..) |child, i| {
        if (child.token == null or child.left == null) return ConvertError.Node_Is_Null;

        const p_name = child.token.?.value;
        // use nodeToCTypeWithSelf so @Self and ?T / !T resolve in params too
        const p_type = c_utils.nodeToCTypeWithSelf(allocator, child.left.?, data.current_struct_name) catch "void*";

        // F9: mut param → no const qualifier (mutable by caller intent)
        if (child.is_mut) {
            try data.appendCodeFmt(allocator, "{s} {s}", .{ p_type, p_name });
        } else {
            try data.appendCodeFmt(allocator, "{s} {s}", .{ p_type, p_name });
        }

        if (i < items.len - 1) try data.appendCode(allocator, ", ");
    }
}
