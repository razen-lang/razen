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

            // If the operator is 'catch', this is a try-catch binary expression.
            // In C, there is no direct equivalent, so we generate a macro or function call.
            // For now, we'll output `RAZEN_CATCH(left, right)`.
            if (std.mem.eql(u8, node.token.?.value, "catch")) {
                const right = try printExpression(allocator, data, node.right.?);
                return std.fmt.allocPrint(allocator.*, "RAZEN_CATCH({s}, {s})", .{ left, right }) catch return ConvertError.Out_Of_Memory;
            }

            const right = try printExpression(allocator, data, node.right.?);
            return std.fmt.allocPrint(allocator.*, "({s} {s} {s})", .{ left, node.token.?.value, right }) catch return ConvertError.Out_Of_Memory;
        },
        ASTNodeType.MemberAccess => {
            if (node.left == null or node.right == null) return ConvertError.Node_Is_Null;
            const left = try printExpression(allocator, data, node.left.?);
            const right = try printExpression(allocator, data, node.right.?);
            // Razen uses . for both struct fields and static namespace access (e.g. State.Open).
            // In C, namespaces usually use underscores (State_Open). For now we output `left.right` or `left_right`.
            // We'll use `_` for simplicity since C doesn't have namespaces.
            // Actually, `std.io.print` -> `std_io_print`.
            return std.fmt.allocPrint(allocator.*, "{s}_{s}", .{ left, right }) catch return ConvertError.Out_Of_Memory;
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
        ASTNodeType.TryExpression => {
            if (node.left == null) return ConvertError.Node_Is_Null;
            const inner = try printExpression(allocator, data, node.left.?);
            return std.fmt.allocPrint(allocator.*, "RAZEN_TRY({s})", .{inner}) catch return ConvertError.Out_Of_Memory;
        },
        ASTNodeType.MatchBody => {
            if (node.left == null) return ConvertError.Node_Is_Null;
            // MatchBody is |e| { block }. This is complex to render as a C expression.
            // We'll emit a block string for now.
            return "{ /* block expr */ }";
        },
        ASTNodeType.ArrayLiteral => {
            var elems = std.ArrayList(u8).initCapacity(allocator.*, 0) catch return ConvertError.Out_Of_Memory;
            if (node.children != null) {
                for (node.children.?.items, 0..) |child, i| {
                    const arg_val = try printExpression(allocator, data, child);
                    elems.appendSlice(allocator.*, arg_val) catch return ConvertError.Out_Of_Memory;
                    if (i < node.children.?.items.len - 1) {
                        elems.appendSlice(allocator.*, ", ") catch return ConvertError.Out_Of_Memory;
                    }
                }
            }
            return std.fmt.allocPrint(allocator.*, "{{{s}}}", .{elems.items}) catch return ConvertError.Out_Of_Memory;
        },
        ASTNodeType.BuiltinExpression => {
            if (node.token == null) return ConvertError.Node_Is_Null;
            const bname = node.token.?.value;
            // Map known builtins to our razen_core.h C versions
            if (std.mem.eql(u8, bname, "SizeOf")) {
                if (node.children != null and node.children.?.items.len > 0) {
                    const t_arg = try printExpression(allocator, data, node.children.?.items[0]);
                    return std.fmt.allocPrint(allocator.*, "sizeof({s})", .{t_arg}) catch return ConvertError.Out_Of_Memory;
                }
                return "sizeof(void)";
            }
            if (std.mem.eql(u8, bname, "c") or std.mem.eql(u8, bname, "arena") or std.mem.eql(u8, bname, "page")) {
                // Return the instance name, e.g. builtin_c_allocator
                return std.fmt.allocPrint(allocator.*, "builtin_{s}_allocator", .{bname}) catch return ConvertError.Out_Of_Memory;
            }
            // fallback
            return std.fmt.allocPrint(allocator.*, "builtin_{s}", .{bname}) catch return ConvertError.Out_Of_Memory;
        },
        else => {
            data.error_token = node.token;
            return ConvertError.Unimplemented_Node_Type;
        },
    }
}
