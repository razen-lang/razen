const std = @import("std");
const node_mod = @import("../../ast/node.zig");
const convert_data = @import("../convert_data.zig");
const errors = @import("../errors.zig");

const c_return = @import("c_return.zig");
const c_declaration = @import("c_declaration.zig");
const c_assignment = @import("c_assignment.zig");
const c_expr = @import("c_expr.zig");
const c_utils = @import("c_utils.zig");
const c_unions = @import("c_unions.zig");

const ASTNode = node_mod.ASTNode;
const ASTNodeType = node_mod.ASTNodeType;
const ConvertData = convert_data.ConvertData;
const ConvertError = errors.ConvertError;
const Allocator = std.mem.Allocator;

// Walk the children of a block node and emit each statement.
pub fn processBody(allocator: *Allocator, data: *ConvertData, node: *ASTNode) ConvertError!void {
    data.error_function = "processBody";
    if (node.children == null) return ConvertError.Node_Is_Null;
    const child_count = node.children.?.items.len;
    if (child_count == 0) return;
    for (node.children.?.items) |child| {
        try processFunctionBodyNode(allocator, data, child, true, true);
    }
}

// Replay a stored body block — used when flushing deferred statements.
pub fn processStatement(allocator: *Allocator, data: *ConvertData, node: *ASTNode) ConvertError!void {
    try processBody(allocator, data, node);
}

fn processFunctionBodyNode(allocator: *Allocator, data: *ConvertData, node: *ASTNode, add_new_line: bool, add_tabs: bool) ConvertError!void {
    data.error_function = "processFunctionBodyNode";

    switch (node.node_type) {
        ASTNodeType.VarDeclaration, ASTNodeType.ConstDeclaration => {
            // try/catch on the RHS needs multi-line expansion; handle it here
            // before passing to processDeclaration which only does single-line output.
            if (node.right != null and node.right.?.node_type == ASTNodeType.TryExpression) {
                try processTryCatch(allocator, data, node, add_tabs);
                data.last_statement_was_return = false;
                return;
            }
            try c_declaration.processDeclaration(allocator, data, node, add_new_line, add_tabs);
            data.last_statement_was_return = false;
        },
        ASTNodeType.Assignment => {
            try c_assignment.processAssignment(allocator, data, node, add_new_line, add_tabs);
            data.last_statement_was_return = false;
        },
        ASTNodeType.FunctionCall => {
            if (add_tabs) try data.addTab(allocator);
            const call_str = try c_expr.printExpression(allocator, data, node);
            try data.appendCodeFmt(allocator, "{s};\n", .{call_str});
            data.last_statement_was_return = false;
        },
        ASTNodeType.IfStatement => {
            if (add_tabs) try data.addTab(allocator);
            const cond = try c_expr.printExpression(allocator, data, node.left.?);
            try data.appendCodeFmt(allocator, "if ({s}) {{\n", .{cond});
            data.incrementIndexCount();
            if (node.middle != null) try processBody(allocator, data, node.middle.?);
            data.decrementIndexCount();
            try data.addTab(allocator);
            if (node.right != null) {
                try data.appendCode(allocator, "} else {\n");
                data.incrementIndexCount();
                try processBody(allocator, data, node.right.?);
                data.decrementIndexCount();
                try data.addTab(allocator);
            }
            try data.appendCode(allocator, "}\n");
            data.last_statement_was_return = false;
        },
        ASTNodeType.LoopStatement => {
            if (add_tabs) try data.addTab(allocator);
            if (node.left != null and node.middle != null and node.right != null) {
                // `loop items |i| { ... }` — iterating over an array
                const items = try c_expr.printExpression(allocator, data, node.left.?);
                const i_name = node.middle.?.token.?.value;
                // try to infer element type; fall back to i32
                const elem_type = data.lookupVarType(items) orelse "i32";
                try data.appendCodeFmt(allocator, "for (size_t _idx = 0; _idx < sizeof({s})/sizeof({s}[0]); _idx++) {{\n", .{ items, items });
                data.incrementIndexCount();
                try data.addTab(allocator);
                try data.appendCodeFmt(allocator, "{s} {s} = {s}[_idx];\n", .{ elem_type, i_name, items });
                try processBody(allocator, data, node.right.?);
                data.decrementIndexCount();
                try data.addTab(allocator);
                try data.appendCode(allocator, "}\n");
            } else {
                // plain `loop { ... }` — infinite loop
                try data.appendCode(allocator, "while (1) {\n");
                data.incrementIndexCount();
                if (node.right != null) {
                    try processBody(allocator, data, node.right.?);
                } else if (node.left != null and node.left.?.node_type == ASTNodeType.LoopBody) {
                    try processBody(allocator, data, node.left.?);
                }
                data.decrementIndexCount();
                try data.addTab(allocator);
                try data.appendCode(allocator, "}\n");
            }
            data.last_statement_was_return = false;
        },
        ASTNodeType.MatchStatement => {
            if (node.left == null or node.children == null) return ConvertError.Node_Is_Null;
            const match_var = try c_expr.printExpression(allocator, data, node.left.?);

            // Use `switch(var.tag)` for tagged unions, `switch(var)` for plain enums.
            // Check var_types first; if not found, peek at the first case pattern.
            const match_var_type = data.lookupVarType(match_var);
            var is_union = if (match_var_type) |t| data.union_registry.contains(t) else false;
            if (!is_union and node.children != null) {
                for (node.children.?.items) |cn| {
                    if (cn.node_type != ASTNodeType.MatchCase or cn.left == null) continue;
                    if (cn.left.?.node_type == ASTNodeType.MemberAccess and cn.left.?.left != null) {
                        const u_name = cn.left.?.left.?.token.?.value;
                        if (data.union_registry.contains(u_name)) is_union = true;
                    }
                    break;
                }
            }
            const switch_expr = if (is_union)
                (std.fmt.allocPrint(allocator.*, "{s}.tag", .{match_var}) catch return ConvertError.Out_Of_Memory)
            else
                match_var;

            if (add_tabs) try data.addTab(allocator);
            try data.appendCodeFmt(allocator, "switch ({s}) {{\n", .{switch_expr});

            for (node.children.?.items) |case_node| {
                if (case_node.node_type != ASTNodeType.MatchCase) continue;
                if (add_tabs) try data.addTab(allocator);

                if (case_node.left != null) {
                    const payload = try extractMatchPayload(allocator, data, case_node.left.?, match_var);
                    try data.appendCodeFmt(allocator, "case {s}:\n", .{payload.case_label});
                    data.incrementIndexCount();
                    // declare the payload variable before the case body
                    if (payload.binding_name != null and payload.binding_type != null and payload.variant_name != null) {
                        try data.addTab(allocator);
                        try data.appendCodeFmt(allocator, "{s} {s} = {s}.data.{s};\n", .{
                            payload.binding_type.?,
                            payload.binding_name.?,
                            match_var,
                            payload.variant_name.?,
                        });
                        data.var_types.put(payload.binding_name.?, payload.binding_type.?) catch {};
                    }
                } else {
                    try data.appendCode(allocator, "default:\n");
                    data.incrementIndexCount();
                }

                if (case_node.right != null and case_node.right.?.left != null) {
                    try processBody(allocator, data, case_node.right.?.left.?);
                }
                if (add_tabs) try data.addTab(allocator);
                try data.appendCode(allocator, "break;\n");
                data.decrementIndexCount();
            }

            if (add_tabs) try data.addTab(allocator);
            try data.appendCode(allocator, "}\n");
            data.last_statement_was_return = false;
        },
        ASTNodeType.DeferStatement => {
            // Don't emit defers immediately; collect the body block and flush
            // them in LIFO order before every return and at the end of the function.
            if (node.left != null) {
                const c_function = @import("c_function.zig");
                data.deferred_stmts.append(allocator.*, node.left.?) catch return ConvertError.Out_Of_Memory;
                _ = c_function;
            }
            data.last_statement_was_return = false;
        },
        ASTNodeType.MemberAccess => {
            if (add_tabs) try data.addTab(allocator);
            const call_str = try c_expr.printExpression(allocator, data, node);
            try data.appendCodeFmt(allocator, "{s};\n", .{call_str});
            data.last_statement_was_return = false;
        },
        ASTNodeType.ReturnStatement => {
            if (node.token != null and std.mem.eql(u8, node.token.?.value, "break")) {
                if (add_tabs) try data.addTab(allocator);
                try data.appendCode(allocator, "break;\n");
                data.last_statement_was_return = false;
            } else {
                data.last_statement_was_return = true;
                try c_return.processReturn(allocator, data, node);
            }
        },
        else => {
            if (add_tabs) try data.addTab(allocator);
            try data.appendCodeFmt(allocator, "// unhandled node: {any}\n", .{node.node_type});
        },
    }
}

// Expand `res := try call() catch |e| { ... }` into the C error-union pattern:
//
//   ErrorUnion_i32 _tmp0 = call(...);
//   if (_tmp0.error != RAZEN_OK) { <catch body> }
//   const i32 res = _tmp0.value;
//
// The parser can emit two different AST shapes depending on context — both
// are handled here by inspecting the TryExpression children directly.
fn processTryCatch(allocator: *Allocator, data: *ConvertData, decl_node: *ASTNode, add_tabs: bool) ConvertError!void {
    const var_name = decl_node.token.?.value;
    const try_node = decl_node.right.?;

    var val_type: []const u8 = "i32";
    if (decl_node.left != null) {
        val_type = c_utils.nodeToCType(allocator, decl_node.left.?) catch "i32";
    }

    const union_type = std.fmt.allocPrint(allocator.*, "ErrorUnion_{s}", .{val_type}) catch return ConvertError.Out_Of_Memory;
    const tmp = try data.freshTmpName(allocator);

    var inner_call_node: *ASTNode = undefined;
    var catch_body_node: ?*ASTNode = null;

    if (try_node.right != null and try_node.right.?.node_type == ASTNodeType.CatchExpression) {
        // Shape: TryExpr { left=call, right=CatchExpr { left=body } }
        inner_call_node = try_node.left.?;
        const catch_node = try_node.right.?;
        if (catch_node.left != null and catch_node.left.?.children != null) {
            catch_body_node = catch_node.left.?;
        }
    } else if (try_node.left != null and try_node.left.?.node_type == ASTNodeType.BinaryExpression) {
        // Shape: TryExpr { left=BinExpr("catch", call, body) }
        const bin = try_node.left.?;
        inner_call_node = bin.left.?;
        if (bin.right != null) {
            if (bin.right.?.children != null) {
                catch_body_node = bin.right.?;
            } else if (bin.right.?.left != null and bin.right.?.left.?.children != null) {
                catch_body_node = bin.right.?.left.?;
            }
        }
    } else {
        inner_call_node = try_node.left.?;
    }

    // 1. call into a temp ErrorUnion variable
    if (add_tabs) try data.addTab(allocator);
    const inner_call = try c_expr.printExpression(allocator, data, inner_call_node);
    try data.appendCodeFmt(allocator, "{s} {s} = {s};\n", .{ union_type, tmp, inner_call });

    // 2. check for error and run the catch block
    if (add_tabs) try data.addTab(allocator);
    try data.appendCodeFmt(allocator, "if ({s}.error != RAZEN_OK) {{\n", .{tmp});
    data.incrementIndexCount();
    if (catch_body_node) |body| {
        try processBody(allocator, data, body);
    } else {
        try data.addTab(allocator);
        try data.appendCode(allocator, "return;\n");
    }
    data.decrementIndexCount();
    if (add_tabs) try data.addTab(allocator);
    try data.appendCode(allocator, "}\n");

    // 3. unpack the success value
    const emit_const = !decl_node.is_mut or decl_node.node_type == ASTNodeType.ConstDeclaration;
    if (add_tabs) try data.addTab(allocator);
    if (emit_const) {
        try data.appendCodeFmt(allocator, "const {s} {s} = {s}.value;\n", .{ val_type, var_name, tmp });
    } else {
        try data.appendCodeFmt(allocator, "{s} {s} = {s}.value;\n", .{ val_type, var_name, tmp });
    }
    data.var_types.put(var_name, val_type) catch {};
}

// Turn "State.Open" into "State_Open" for use as a C case label.
fn dotToUnderscore(allocator: *Allocator, s: []const u8) ConvertError![]u8 {
    const result = allocator.*.dupe(u8, s) catch return ConvertError.Out_Of_Memory;
    for (result) |*c| {
        if (c.* == '.') c.* = '_';
    }
    return result;
}

const MatchPayload = struct {
    case_label: []const u8,
    variant_name: ?[]const u8,
    binding_name: ?[]const u8,
    binding_type: ?[]const u8,
};

// Parse a match pattern and pull out:
//   case_label   — C enum tag (e.g. "Value_Int")
//   variant_name — union variant name for .data access (e.g. "Int")
//   binding_name — variable to declare from the payload (e.g. "v")
//   binding_type — C type for that variable, from the union registry
//
// Handles two pattern forms:
//   State.Open       -> case State_Open (no payload)
//   Value.Int(v)     -> case Value_Int  + declare `i32 v = match_var.data.Int`
fn extractMatchPayload(
    allocator: *Allocator,
    data: *ConvertData,
    pattern: *ASTNode,
    _match_var: []const u8,
) ConvertError!MatchPayload {
    _ = _match_var;

    if (pattern.node_type == ASTNodeType.MemberAccess) {
        if (pattern.left == null or pattern.right == null) {
            return MatchPayload{ .case_label = "default", .variant_name = null, .binding_name = null, .binding_type = null };
        }
        const union_name = pattern.left.?.token.?.value;

        if (pattern.right.?.node_type == ASTNodeType.FunctionCall) {
            // Value.Int(v) — has a payload binding
            const variant_name = pattern.right.?.token.?.value;
            const case_label = std.fmt.allocPrint(allocator.*, "{s}_{s}", .{ union_name, variant_name }) catch return ConvertError.Out_Of_Memory;

            var binding_name: ?[]const u8 = null;
            if (pattern.right.?.children != null and pattern.right.?.children.?.items.len > 0) {
                const arg = pattern.right.?.children.?.items[0];
                if (arg.node_type == ASTNodeType.Argument and arg.left != null) {
                    binding_name = arg.left.?.token.?.value;
                } else if (arg.token != null) {
                    binding_name = arg.token.?.value;
                }
            }

            const binding_type = c_unions.lookupVariantType(data, union_name, variant_name);
            return MatchPayload{
                .case_label = case_label,
                .variant_name = variant_name,
                .binding_name = binding_name,
                .binding_type = binding_type,
            };
        } else {
            // State.Open — no payload
            const variant_name = pattern.right.?.token.?.value;
            const case_label = std.fmt.allocPrint(allocator.*, "{s}_{s}", .{ union_name, variant_name }) catch return ConvertError.Out_Of_Memory;
            return MatchPayload{ .case_label = case_label, .variant_name = variant_name, .binding_name = null, .binding_type = null };
        }
    }

    // fallback for anything not a MemberAccess pattern
    const raw = try c_expr.printExpression(allocator, data, pattern);
    const label = try dotToUnderscore(allocator, raw);
    return MatchPayload{ .case_label = label, .variant_name = null, .binding_name = null, .binding_type = null };
}
