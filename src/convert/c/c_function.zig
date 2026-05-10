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

// Emit a function declaration (or extern prototype).
//
// Linkage rules:
//   ext func    ->  extern <ret> <name>(params);   (no body)
//   const func  ->  static inline <ret> <name>     (compile-time eligible)
//   pub func    ->  <ret> <name>                    (externally visible)
//   func        ->  static <ret> <name>             (file-private)
pub fn processFunctionDeclaration(allocator: *Allocator, data: *ConvertData, node: *ASTNode) ConvertError!void {
    data.error_function = "processFunctionDeclaration";
    if (node.token == null) return ConvertError.Node_Is_Null;

    const func_name = node.token.?.value;
    const is_main = std.mem.eql(u8, func_name, "main");
    const is_ext = node.node_type == ASTNodeType.ExtDeclaration;
    const is_const_func = node.is_const;
    const is_pub = node.is_pub;

    var return_type: []const u8 = "void";
    if (node.left != null and node.left.?.left != null) {
        return_type = c_utils.nodeToCTypeWithSelf(allocator, node.left.?.left.?, data.current_struct_name) catch "void";
    }
    if (is_main) return_type = "int";

    // blank line before each function for readability
    try data.appendCode(allocator, "\n");

    if (is_ext) {
        try data.appendCodeFmt(allocator, "extern {s} {s}(", .{ return_type, func_name });
        if (node.middle != null) try processParameters(allocator, data, node.middle.?);
        try data.appendCode(allocator, ");\n");
        data.node_index += 1;
        return;
    }

    if (is_const_func) {
        try data.appendCodeFmt(allocator, "static inline {s} {s}(", .{ return_type, func_name });
    } else if (!is_pub and !is_main) {
        try data.appendCodeFmt(allocator, "static {s} {s}(", .{ return_type, func_name });
    } else {
        try data.appendCodeFmt(allocator, "{s} {s}(", .{ return_type, func_name });
    }

    if (node.middle != null) try processParameters(allocator, data, node.middle.?);
    try data.appendCode(allocator, ") {\n");
    data.incrementIndexCount();

    // reset the deferred statement list for this function scope
    data.deferred_stmts.clearRetainingCapacity();

    if (node.right != null) try c_body.processBody(allocator, data, node.right.?);

    // flush any remaining defers at the end of the function (LIFO order)
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

// Flush all collected deferred statements in reverse order (last-in first-out).
// Called before every `return` statement and at the end of each function body.
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
        const p_type = c_utils.nodeToCTypeWithSelf(allocator, child.left.?, data.current_struct_name) catch "void*";
        try data.appendCodeFmt(allocator, "{s} {s}", .{ p_type, p_name });
        if (i < items.len - 1) try data.appendCode(allocator, ", ");
    }
}
