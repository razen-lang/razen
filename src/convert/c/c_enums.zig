const std = @import("std");
const node_mod = @import("../../ast/node.zig");
const convert_data = @import("../convert_data.zig");
const errors = @import("../errors.zig");

const ASTNode = node_mod.ASTNode;
const ASTNodeType = node_mod.ASTNodeType;
const ConvertData = convert_data.ConvertData;
const ConvertError = errors.ConvertError;
const Allocator = std.mem.Allocator;

pub fn processEnum(allocator: *Allocator, data: *ConvertData, node: *ASTNode) ConvertError!void {
    data.error_function = "processEnum";

    if (node.token == null) {
        data.error_detail = "no enum name";
        return ConvertError.Node_Is_Null;
    }
    const enum_name = node.token.?.value;

    try data.appendCodeFmt(allocator, "typedef enum {{\n", .{});

    if (node.children != null) {
        for (node.children.?.items, 0..) |member_node, i| {
            if (member_node.node_type == ASTNodeType.EnumField) {
                const var_name = member_node.token.?.value;
                try data.appendCodeFmt(allocator, "\t{s}_{s}", .{ enum_name, var_name });
                
                // if it has a specific value assigned  = 200
                if (member_node.right != null) {
                    if (member_node.right.?.node_type == ASTNodeType.IntegerLiteral) {
                        try data.appendCodeFmt(allocator, " = {s}", .{ member_node.right.?.token.?.value });
                    }
                }
                
                if (i < node.children.?.items.len - 1) {
                    try data.appendCode(allocator, ",\n");
                } else {
                    try data.appendCode(allocator, "\n");
                }
            }
        }
    }

    try data.appendCodeFmt(allocator, "}} {s};\n\n", .{enum_name});
}

// Error blocks are technically just tagged enums
pub fn processErrorDecl(allocator: *Allocator, data: *ConvertData, node: *ASTNode) ConvertError!void {
    data.error_function = "processErrorDecl";

    if (node.token == null) return ConvertError.Node_Is_Null;
    const err_name = node.token.?.value;

    try data.appendCodeFmt(allocator, "typedef enum {{\n", .{});

    if (node.children != null) {
        for (node.children.?.items, 0..) |member_node, i| {
            if (member_node.node_type == ASTNodeType.ErrorField) {
                const var_name = member_node.token.?.value;
                try data.appendCodeFmt(allocator, "\t{s}_{s}", .{ err_name, var_name });
                
                if (i < node.children.?.items.len - 1) {
                    try data.appendCode(allocator, ",\n");
                } else {
                    try data.appendCode(allocator, "\n");
                }
            }
        }
    }

    try data.appendCodeFmt(allocator, "}} {s};\n\n", .{err_name});
}
