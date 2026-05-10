const std = @import("std");
const node_mod = @import("../../ast/node.zig");
const convert_data = @import("../convert_data.zig");
const errors = @import("../errors.zig");
const c_utils = @import("c_utils.zig");

const ASTNode = node_mod.ASTNode;
const ASTNodeType = node_mod.ASTNodeType;
const ConvertData = convert_data.ConvertData;
const ConvertError = errors.ConvertError;
const Allocator = std.mem.Allocator;

/// C3 FIX: Razen unions are tagged unions. Emit a proper C tagged-union struct:
///
///   typedef struct {
///       enum { NetErr_Code, NetErr_Msg } tag;
///       union {
///           i32 Code;
///           RazenStr Msg;
///       } data;
///   } NetErr;
///
pub fn processUnion(allocator: *Allocator, data: *ConvertData, node: *ASTNode) ConvertError!void {
    data.error_function = "processUnion";

    if (node.token == null) return ConvertError.Node_Is_Null;
    const union_name = node.token.?.value;

    // ── outer struct ──────────────────────────────────────────────────────
    try data.appendCodeFmt(allocator, "typedef struct {{\n", .{});

    // ── discriminant enum  ────────────────────────────────────────────────
    try data.appendCode(allocator, "\tenum {\n");
    if (node.children != null) {
        for (node.children.?.items, 0..) |member_node, idx| {
            if (member_node.node_type != ASTNodeType.UnionField) continue;
            const var_name = member_node.token.?.value;
            const comma: []const u8 = if (idx < node.children.?.items.len - 1) "," else "";
            try data.appendCodeFmt(allocator, "\t\t{s}_{s}{s}\n", .{ union_name, var_name, comma });
        }
    }
    try data.appendCode(allocator, "\t} tag;\n");

    // ── payload union  ────────────────────────────────────────────────────
    try data.appendCode(allocator, "\tunion {\n");
    if (node.children != null) {
        for (node.children.?.items) |member_node| {
            if (member_node.node_type != ASTNodeType.UnionField) continue;
            const var_name = member_node.token.?.value;

            if (member_node.left != null) {
                // simple variant: Code: i32
                const c_type = c_utils.nodeToCType(allocator, member_node.left.?) catch "void*";
                try data.appendCodeFmt(allocator, "\t\t{s} {s};\n", .{ c_type, var_name });
            } else if (member_node.children != null) {
                // struct variant: Binary { left: Expr, right: Expr, op: str }
                try data.appendCode(allocator, "\t\tstruct {\n");
                for (member_node.children.?.items) |sf| {
                    if (sf.left != null) {
                        const sf_type = c_utils.nodeToCType(allocator, sf.left.?) catch "void*";
                        try data.appendCodeFmt(allocator, "\t\t\t{s} {s};\n", .{ sf_type, sf.token.?.value });
                    }
                }
                try data.appendCodeFmt(allocator, "\t\t}} {s};\n", .{var_name});
            } else {
                // unit variant (no payload) — use a sentinel byte
                try data.appendCodeFmt(allocator, "\t\tuint8_t _{s}_unit;\n", .{var_name});
            }
        }
    }
    try data.appendCode(allocator, "\t} data;\n");

    // ── close outer struct ────────────────────────────────────────────────
    try data.appendCodeFmt(allocator, "}} {s};\n\n", .{union_name});
}
