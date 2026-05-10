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

pub fn processUnion(allocator: *Allocator, data: *ConvertData, node: *ASTNode) ConvertError!void {
    data.error_function = "processUnion";

    if (node.token == null) return ConvertError.Node_Is_Null;
    const union_name = node.token.?.value;

    // Razen Unions (NetErr) act like tagged unions.
    // We can emit a C union of structs for now.
    try data.appendCodeFmt(allocator, "typedef union {{\n", .{});

    if (node.children != null) {
        for (node.children.?.items) |member_node| {
            if (member_node.node_type == ASTNodeType.UnionField) {
                const var_name = member_node.token.?.value;

                if (member_node.left != null) {
                    // Record style `Code: i32` or Tuple style `Code(i32)` -> left is the Type
                    const c_type_text = c_utils.nodeToCType(allocator, member_node.left.?) catch return ConvertError.Invalid_Var_Type;
                    try data.appendCodeFmt(allocator, "\t{s} {s};\n", .{ c_type_text, var_name });
                } else if (member_node.children != null) {
                    // Struct style `Code { code: i32, msg: str }` -> struct inside the union
                    try data.appendCodeFmt(allocator, "\tstruct {{\n", .{});
                    for (member_node.children.?.items) |sf| {
                        if (sf.left != null) {
                            const sf_type = c_utils.nodeToCType(allocator, sf.left.?) catch return ConvertError.Invalid_Var_Type;
                            try data.appendCodeFmt(allocator, "\t\t{s} {s};\n", .{ sf_type, sf.token.?.value });
                        }
                    }
                    try data.appendCodeFmt(allocator, "\t}} {s};\n", .{var_name});
                } else {
                    // no payload
                    try data.appendCodeFmt(allocator, "\tint {s}_empty;\n", .{var_name});
                }
            }
        }
    }

    try data.appendCodeFmt(allocator, "}} {s};\n\n", .{union_name});
}
