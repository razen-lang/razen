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
const ArrayList = std.ArrayList;

pub fn processStruct(allocator: *Allocator, data: *ConvertData, node: *ASTNode) ConvertError!void {
    data.error_function = "processStruct";

    if (node.token == null) {
        data.error_detail = "no struct name";
        return ConvertError.Node_Is_Null;
    }
    const struct_name = node.token.?.value;

    try data.appendCodeFmt(allocator, "typedef struct {{\n", .{});

    if (node.children != null) {
        for (node.children.?.items) |member_node| {
            if (member_node.node_type == ASTNodeType.StructField) {
                const var_name = member_node.token.?.value;
                if (member_node.left == null) {
                    data.error_detail = "member type node is null in struct";
                    return ConvertError.Node_Is_Null;
                }
                const c_type_text = c_utils.nodeToCType(allocator, member_node.left.?) catch return ConvertError.Invalid_Var_Type;
                try data.appendCodeFmt(allocator, "\t{s} {s};\n", .{ c_type_text, var_name });
            } else if (member_node.node_type == ASTNodeType.FunctionDeclaration) {
                // Inline functions/methods — we ignore them in the struct layout in C,
                // but we could emit them as function pointers if requested.
                // For a flat struct, we just skip it.
            }
        }
    }

    try data.appendCodeFmt(allocator, "}} {s};\n\n", .{struct_name});
}

pub fn processBehave(allocator: *Allocator, data: *ConvertData, node: *ASTNode) ConvertError!void {
    data.error_function = "processBehave";

    if (node.token == null) {
        data.error_detail = "no behave name";
        return ConvertError.Node_Is_Null;
    }
    const behave_name = node.token.?.value;

    // A Behave (Trait) in C can be represented as a struct of function pointers and fields.
    try data.appendCodeFmt(allocator, "typedef struct {{\n", .{});

    if (node.children != null) {
        for (node.children.?.items) |member_node| {
            if (member_node.node_type == ASTNodeType.StructField) {
                // e.g. needs tag: u8
                const var_name = member_node.token.?.value;
                if (member_node.left != null) {
                    const c_type_text = c_utils.nodeToCType(allocator, member_node.left.?) catch return ConvertError.Invalid_Var_Type;
                    try data.appendCodeFmt(allocator, "\t{s} {s};\n", .{ c_type_text, var_name });
                }
            } else if (member_node.node_type == ASTNodeType.FunctionDeclaration) {
                // e.g. func serialize(x: @Self) -> [u8]
                const func_name = member_node.token.?.value;
                var ret_type: []const u8 = "void";
                if (member_node.left != null and member_node.left.?.left != null) {
                    ret_type = c_utils.nodeToCType(allocator, member_node.left.?.left.?) catch "void";
                }

                try data.appendCodeFmt(allocator, "\t{s} (*{s})(", .{ ret_type, func_name });

                // parameters
                if (member_node.middle != null and member_node.middle.?.children != null) {
                    const params = member_node.middle.?.children.?.items;
                    for (params, 0..) |p, i| {
                        if (p.left != null) {
                            const p_type = c_utils.nodeToCType(allocator, p.left.?) catch "void*";
                            try data.appendCodeFmt(allocator, "{s} {s}", .{ p_type, p.token.?.value });
                        }
                        if (i < params.len - 1) {
                            try data.appendCode(allocator, ", ");
                        }
                    }
                } else {
                    try data.appendCode(allocator, "void");
                }

                try data.appendCode(allocator, ");\n");
            }
        }
    }

    try data.appendCodeFmt(allocator, "}} {s};\n\n", .{behave_name});
}
