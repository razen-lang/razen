const std = @import("std");
const node_mod = @import("../../ast/node.zig");
const convert_data = @import("../convert_data.zig");
const errors = @import("../errors.zig");

const c_expr = @import("c_expr.zig");
const c_function = @import("c_function.zig");

const ASTNode = node_mod.ASTNode;
const ConvertData = convert_data.ConvertData;
const ConvertError = errors.ConvertError;
const Allocator = std.mem.Allocator;

pub fn processReturn(allocator: *Allocator, data: *ConvertData, node: *ASTNode) ConvertError!void {
    data.error_function = "processReturn";

    // Bug 7: flush all collected deferred statements before every return (LIFO)
    try c_function.emitDeferredStatements(allocator, data);

    try data.addTab(allocator);

    if (node.left == null) {
        if (node.token != null) {
            if (std.mem.eql(u8, node.token.?.value, "break")) {
                try data.appendCode(allocator, "break;\n");
                return;
            } else if (std.mem.eql(u8, node.token.?.value, "skip")) {
                try data.appendCode(allocator, "continue;\n");
                return;
            }
        }
        try data.appendCode(allocator, "return;\n");
        return;
    }

    const value = try c_expr.printExpression(allocator, data, node.left.?);
    try data.appendCodeFmt(allocator, "return {s};\n", .{value});
}
