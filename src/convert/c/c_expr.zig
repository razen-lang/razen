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

/// printLValue: like printExpression but MemberAccess uses '.' (for assignment targets like c.value).
/// Dot-notation (struct field access) is needed on the LHS of assignments.
pub fn printLValue(allocator: *Allocator, data: *ConvertData, node: *ASTNode) ConvertError!String {
    if (node.token == null) return ConvertError.Node_Is_Null;
    if (node.node_type == ASTNodeType.MemberAccess) {
        if (node.left == null or node.right == null) return ConvertError.Node_Is_Null;
        const left = try printLValue(allocator, data, node.left.?);
        const right = try printLValue(allocator, data, node.right.?);
        return std.fmt.allocPrint(allocator.*, "{s}.{s}", .{ left, right }) catch return ConvertError.Out_Of_Memory;
    }
    // everything else: delegate to printExpression
    return printExpression(allocator, data, node);
}

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

            // C7 FIX: detect union variant construction: Value.Int(42)
            // Parsed as MemberAccess(Identifier(Value), FunctionCall(Int, [42]))
            if (node.right.?.node_type == ASTNodeType.FunctionCall) {
                const union_name = node.left.?.token.?.value;
                const variant_name = node.right.?.token.?.value;
                const c_unions = @import("c_unions.zig");
                if (c_unions.lookupVariantType(data, union_name, variant_name)) |variant_type| {
                    // it IS a known union constructor
                    const tag = std.fmt.allocPrint(allocator.*, "{s}_{s}", .{ union_name, variant_name }) catch return ConvertError.Out_Of_Memory;
                    if (std.mem.eql(u8, variant_type, "unit")) {
                        // unit variant: (Value){ .tag = Value_Idle }
                        return std.fmt.allocPrint(allocator.*, "({s}){{ .tag = {s} }}", .{ union_name, tag }) catch return ConvertError.Out_Of_Memory;
                    } else if (std.mem.eql(u8, variant_type, "struct")) {
                        // struct variant — emit as-is for now (needs named fields)
                        return std.fmt.allocPrint(allocator.*, "({s}){{ .tag = {s} }}", .{ union_name, tag }) catch return ConvertError.Out_Of_Memory;
                    } else {
                        // payload variant: (Value){ .tag = Value_Int, .data = { .Int = 42 } }
                        var payload_str = std.ArrayList(u8).initCapacity(allocator.*, 0) catch return ConvertError.Out_Of_Memory;
                        if (node.right.?.children != null) {
                            for (node.right.?.children.?.items, 0..) |arg, i| {
                                if (arg.left != null) {
                                    const av = try printExpression(allocator, data, arg.left.?);
                                    payload_str.appendSlice(allocator.*, av) catch return ConvertError.Out_Of_Memory;
                                }
                                if (i < node.right.?.children.?.items.len - 1) {
                                    payload_str.appendSlice(allocator.*, ", ") catch return ConvertError.Out_Of_Memory;
                                }
                            }
                        }
                        return std.fmt.allocPrint(allocator.*, "({s}){{ .tag = {s}, .data = {{ .{s} = {s} }} }}",
                            .{ union_name, tag, variant_name, payload_str.items }) catch return ConvertError.Out_Of_Memory;
                    }
                }
                // not a known union constructor — fall through to namespace call
                // e.g. std.fmt.println(...) → std_fmt_println(...)
                const func_name_raw = try printExpression(allocator, data, node.left.?);
                const right_call = node.right.?;
                const func_full = std.fmt.allocPrint(allocator.*, "{s}_{s}", .{ func_name_raw, right_call.token.?.value }) catch return ConvertError.Out_Of_Memory;
                var args_str = std.ArrayList(u8).initCapacity(allocator.*, 0) catch return ConvertError.Out_Of_Memory;
                if (right_call.children != null) {
                    for (right_call.children.?.items, 0..) |arg, i| {
                        if (arg.left != null) {
                            const av = try printExpression(allocator, data, arg.left.?);
                            args_str.appendSlice(allocator.*, av) catch return ConvertError.Out_Of_Memory;
                        }
                        if (i < right_call.children.?.items.len - 1) {
                            args_str.appendSlice(allocator.*, ", ") catch return ConvertError.Out_Of_Memory;
                        }
                    }
                }
                return std.fmt.allocPrint(allocator.*, "{s}({s})", .{ func_full, args_str.items }) catch return ConvertError.Out_Of_Memory;
            }

            // plain member access: std.fmt → std_fmt, State.Open → State_Open
            const left = try printExpression(allocator, data, node.left.?);
            const right = try printExpression(allocator, data, node.right.?);
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
