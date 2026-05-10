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

/// F13 helper: check if the next argument in a list is a tuple/array literal
fn isTupleArg(children: []*ASTNode, idx: usize) bool {
    if (idx >= children.len) return false;
    if (children[idx].left == null) return false;
    return children[idx].left.?.node_type == ASTNodeType.ArrayLiteral;
}

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
                        return std.fmt.allocPrint(allocator.*, "({s}){{ .tag = {s}, .data = {{ .{s} = {s} }} }}", .{ union_name, tag, variant_name, payload_str.items }) catch return ConvertError.Out_Of_Memory;
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

            // F16 FIX: ptr.* dereference — right token is "*"
            if (node.right.?.token != null and std.mem.eql(u8, node.right.?.token.?.value, "*")) {
                const ptr_expr = try printExpression(allocator, data, node.left.?);
                return std.fmt.allocPrint(allocator.*, "(*{s})", .{ptr_expr}) catch return ConvertError.Out_Of_Memory;
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
                const children = node.children.?.items;
                for (children, 0..) |child, i| {
                    if (child.left != null) {
                        // F13 FIX: skip tuple literal .{...} args (format arg tuples)
                        // They get expanded inline as additional C args
                        const is_tuple_arg = child.left.?.node_type == ASTNodeType.ArrayLiteral;
                        if (!is_tuple_arg) {
                            const arg_val = try printExpression(allocator, data, child.left.?);
                            args_str.appendSlice(allocator.*, arg_val) catch return ConvertError.Out_Of_Memory;
                            if (i < children.len - 1 and !isTupleArg(children, i + 1)) {
                                args_str.appendSlice(allocator.*, ", ") catch return ConvertError.Out_Of_Memory;
                            }
                        } else {
                            // expand tuple items as additional args
                            if (child.left.?.children != null) {
                                for (child.left.?.children.?.items, 0..) |telem, ti| {
                                    const tv = try printExpression(allocator, data, telem);
                                    if (args_str.items.len > 0) {
                                        args_str.appendSlice(allocator.*, ", ") catch return ConvertError.Out_Of_Memory;
                                    }
                                    args_str.appendSlice(allocator.*, tv) catch return ConvertError.Out_Of_Memory;
                                    _ = ti;
                                }
                            }
                        }
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
            if (std.mem.eql(u8, bname, "SizeOf")) {
                if (node.children != null and node.children.?.items.len > 0) {
                    const t_arg = try printExpression(allocator, data, node.children.?.items[0]);
                    return std.fmt.allocPrint(allocator.*, "sizeof({s})", .{t_arg}) catch return ConvertError.Out_Of_Memory;
                }
                return "sizeof(void)";
            }
            // F12: allocator builtins — map to razen_core.h allocator stubs
            if (std.mem.eql(u8, bname, "c")) return "razen_c_allocator()";
            if (std.mem.eql(u8, bname, "page")) return "razen_page_allocator()";
            if (std.mem.eql(u8, bname, "arena")) return "razen_arena_allocator()";
            if (std.mem.eql(u8, bname, "pool")) return "razen_pool_allocator()";
            if (std.mem.eql(u8, bname, "stack")) return "razen_stack_allocator()";
            if (std.mem.eql(u8, bname, "fixed")) return "razen_fixed_allocator()";
            if (std.mem.eql(u8, bname, "gpa")) return "razen_gpa_allocator()";
            if (std.mem.eql(u8, bname, "debug")) return "razen_debug_allocator()";
            return std.fmt.allocPrint(allocator.*, "razen_{s}()", .{bname}) catch return ConvertError.Out_Of_Memory;
        },

        // F16 FIX: UnaryExpression covers -x, !x, &x (address-of), and ptr.* (deref)
        ASTNodeType.UnaryExpression => {
            if (node.token == null or node.left == null) return ConvertError.Node_Is_Null;
            const operand = try printExpression(allocator, data, node.left.?);
            const op = node.token.?.value;
            if (std.mem.eql(u8, op, "&")) {
                // &x → &x (address-of)
                return std.fmt.allocPrint(allocator.*, "&{s}", .{operand}) catch return ConvertError.Out_Of_Memory;
            }
            if (std.mem.eql(u8, op, "*") or std.mem.eql(u8, op, ".*")) {
                // ptr.* or *ptr → (*ptr) dereference
                return std.fmt.allocPrint(allocator.*, "(*{s})", .{operand}) catch return ConvertError.Out_Of_Memory;
            }
            // -x, !x
            return std.fmt.allocPrint(allocator.*, "{s}{s}", .{ op, operand }) catch return ConvertError.Out_Of_Memory;
        },

        // F15 FIX: StructLiteral / Annotation used for struct construction
        // Person { name: "Ayaan", age: 22 } → (Person){ .name = "Ayaan", .age = 22 }
        ASTNodeType.Annotation => {
            // @Generic, @TypeOf etc. — just emit the name
            if (node.token == null) return "/* @builtin */";
            const bname = node.token.?.value;
            if (std.mem.eql(u8, bname, "TypeOf") and node.children != null and node.children.?.items.len > 0) {
                const arg = try printExpression(allocator, data, node.children.?.items[0]);
                return std.fmt.allocPrint(allocator.*, "typeof({s})", .{arg}) catch return ConvertError.Out_Of_Memory;
            }
            return std.fmt.allocPrint(allocator.*, "/* @{s} */", .{bname}) catch return ConvertError.Out_Of_Memory;
        },

        else => {
            data.error_token = node.token;
            return ConvertError.Unimplemented_Node_Type;
        },
    }
}
