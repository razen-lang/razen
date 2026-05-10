const std = @import("std");
const node_mod = @import("../../ast/node.zig");
const convert_data = @import("../convert_data.zig");
const errors = @import("../errors.zig");

const ASTNode = node_mod.ASTNode;
const ASTNodeType = node_mod.ASTNodeType;
const ConvertData = convert_data.ConvertData;
const ConvertError = errors.ConvertError;
const Allocator = std.mem.Allocator;
const String = []const u8;

pub fn printExpression(allocator: *Allocator, data: *ConvertData, node: *ASTNode) ConvertError!String {
    if (node.token == null) {
        return ConvertError.Node_Is_Null;
    }

    switch (node.node_type) {
        ASTNodeType.IntegerLiteral,
        ASTNodeType.FloatLiteral,
        ASTNodeType.BoolLiteral,
        ASTNodeType.Identifier,
        => {
            return node.token.?.value;
        },
        ASTNodeType.StringLiteral => {
            return std.fmt.allocPrint(allocator.*, "\"{s}\"", .{node.token.?.value}) catch return ConvertError.Out_Of_Memory;
        },
        ASTNodeType.BinaryExpression => {
            if (node.left == null or node.right == null) return ConvertError.Node_Is_Null;
            const left = try printExpression(allocator, data, node.left.?);
            const right = try printExpression(allocator, data, node.right.?);
            return std.fmt.allocPrint(allocator.*, "({s} {s} {s})", .{ left, node.token.?.value, right }) catch return ConvertError.Out_Of_Memory;
        },
        ASTNodeType.FunctionCall => {
            const func_name = node.token.?.value;
            var args_str = std.ArrayList(u8).initCapacity(allocator.*, 0) catch return ConvertError.Out_Of_Memory;
            
            if (node.children != null) {
                for (node.children.?.items, 0..) |child, i| {
                    if (child.left != null) {
                        const arg_val = try printExpression(allocator, data, child.left.?);
                        args_str.appendSlice(allocator.*, arg_val) catch return ConvertError.Out_Of_Memory;
                    }
                    if (i < node.children.?.items.len - 1) {
                        args_str.appendSlice(allocator.*, ", ") catch return ConvertError.Out_Of_Memory;
                    }
                }
            }
            return std.fmt.allocPrint(allocator.*, "{s}({s})", .{ func_name, args_str.items }) catch return ConvertError.Out_Of_Memory;
        },
        else => {
            data.error_token = node.token;
            return ConvertError.Unimplemented_Node_Type;
        }
    }
}
