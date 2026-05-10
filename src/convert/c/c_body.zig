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

pub fn processBody(allocator: *Allocator, data: *ConvertData, node: *ASTNode) ConvertError!void {
    data.error_function = "processBody";

    if (node.children == null) {
        return ConvertError.Node_Is_Null;
    }

    const child_count = node.children.?.items.len;
    if (child_count == 0) return;

    for (node.children.?.items) |child| {
        try processFunctionBodyNode(allocator, data, child, true, true);
    }
}

/// Public wrapper used by c_function.emitDeferredStatements to replay stored body nodes.
pub fn processStatement(allocator: *Allocator, data: *ConvertData, node: *ASTNode) ConvertError!void {
    try processBody(allocator, data, node);
}

fn processFunctionBodyNode(allocator: *Allocator, data: *ConvertData, node: *ASTNode, add_new_line: bool, add_tabs: bool) ConvertError!void {
    data.error_function = "processFunctionBodyNode";

    switch (node.node_type) {
        ASTNodeType.VarDeclaration, ASTNodeType.ConstDeclaration => {
            // C2 FIX: intercept `var := try call() catch |e| { ... }` at statement level
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
            if (node.middle != null) {
                try processBody(allocator, data, node.middle.?);
            }
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
                // loop items |i| { ... }  →  for (size_t _idx ...) { T i = items[_idx]; ... }
                const items = try c_expr.printExpression(allocator, data, node.left.?);
                const i_name = node.middle.?.token.?.value;
                // infer element type from var_types if known, else i32
                const elem_type = data.lookupVarType(items) orelse "i32";
                try data.appendCodeFmt(allocator,
                    "for (size_t _idx = 0; _idx < sizeof({s})/sizeof({s}[0]); _idx++) {{\n",
                    .{ items, items });
                data.incrementIndexCount();
                try data.addTab(allocator);
                try data.appendCodeFmt(allocator, "{s} {s} = {s}[_idx];\n", .{ elem_type, i_name, items });
                try processBody(allocator, data, node.right.?);
                data.decrementIndexCount();
                try data.addTab(allocator);
                try data.appendCode(allocator, "}\n");
            } else {
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

        // C3+C6 FIX: match → switch/case with tagged-union payload extraction
        ASTNodeType.MatchStatement => {
            if (node.left == null or node.children == null) return ConvertError.Node_Is_Null;
            const match_var = try c_expr.printExpression(allocator, data, node.left.?);

            // C6 FIX: use .tag if match_var is a known tagged union.
            // Check var_types first, then check if any case pattern uses a registered union name.
            const match_var_type = data.lookupVarType(match_var);
            var is_union = if (match_var_type) |t| data.union_registry.contains(t) else false;
            // Second pass: peek at the first non-else case pattern to detect union
            if (!is_union and node.children != null) {
                for (node.children.?.items) |cn| {
                    if (cn.node_type != ASTNodeType.MatchCase or cn.left == null) continue;
                    if (cn.left.?.node_type == ASTNodeType.MemberAccess and cn.left.?.left != null) {
                        const u_name = cn.left.?.left.?.token.?.value;
                        if (data.union_registry.contains(u_name)) {
                            is_union = true;
                        }
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
                    // C6: detect payload pattern: Value.Int(v) parsed as MemberAccess(Value, FunctionCall(Int,[v]))
                    const payload = try extractMatchPayload(allocator, data, case_node.left.?, match_var);
                    try data.appendCodeFmt(allocator, "case {s}:\n", .{payload.case_label});
                    data.incrementIndexCount();
                    // emit payload binding before the body
                    if (payload.binding_name != null and payload.binding_type != null and payload.variant_name != null) {
                        try data.addTab(allocator);
                        try data.appendCodeFmt(allocator, "{s} {s} = {s}.data.{s};\n",
                            .{ payload.binding_type.?, payload.binding_name.?, match_var, payload.variant_name.? });
                        // register binding type for later use
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

        // C1 FIX: store node.left (the body block), NOT the DeferStatement itself.
        // emitDeferredStatements calls processStatement(body_node) → processBody → no infinite loop.
        ASTNodeType.DeferStatement => {
            if (node.left != null) {
                const c_function = @import("c_function.zig");
                data.deferred_stmts.append(allocator.*, node.left.?) catch return ConvertError.Out_Of_Memory;
                _ = c_function; // just ensures it's imported for emitDeferredStatements
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
            try data.appendCodeFmt(allocator, "// TODO: Handle node ({any})\n", .{node.node_type});
        },
    }
}

/// C2 FIX: expand `var := try call() catch |e| { ... }` into:
///   ErrorUnionI32 _tmp0 = call(...);
///   if (_tmp0.error != RAZEN_OK) { <catch body> }
///   const i32 var = _tmp0.value;
/// C2 FIX: expand `var := try call() catch |e| { ... }` into proper C error-union pattern.
///
/// The parser produces two possible shapes:
///
///   Shape A (parseTryStatement via finishInferred):
///     TryExpression
///       .left  = BinaryExpression("catch", FunctionCall, MatchBody)
///       .right = CatchExpression  (sometimes absent)
///
///   Shape B (CatchExpression present):
///     TryExpression
///       .left  = FunctionCall
///       .right = CatchExpression { .left = body_block }
///
/// In both shapes we extract: the inner call, and the catch body block.
fn processTryCatch(allocator: *Allocator, data: *ConvertData, decl_node: *ASTNode, add_tabs: bool) ConvertError!void {
    const var_name = decl_node.token.?.value;
    const try_node = decl_node.right.?; // TryExpression

    // resolve declared type — default i32
    var val_type: []const u8 = "i32";
    if (decl_node.left != null) {
        val_type = c_utils.nodeToCType(allocator, decl_node.left.?) catch "i32";
    }

    const union_type = std.fmt.allocPrint(allocator.*, "ErrorUnion_{s}", .{val_type}) catch return ConvertError.Out_Of_Memory;
    const tmp = try data.freshTmpName(allocator);

    // --- Determine inner_call_node and catch_body_node ---
    var inner_call_node: *ASTNode = undefined;
    var catch_body_node: ?*ASTNode = null;

    if (try_node.right != null and try_node.right.?.node_type == ASTNodeType.CatchExpression) {
        // Shape B: .left = call, .right = CatchExpression
        inner_call_node = try_node.left.?;
        const catch_node = try_node.right.?;
        if (catch_node.left != null and catch_node.left.?.children != null) {
            catch_body_node = catch_node.left.?;
        }
    } else if (try_node.left != null and try_node.left.?.node_type == ASTNodeType.BinaryExpression) {
        // Shape A: .left = BinaryExpression("catch", call, body)
        const bin = try_node.left.?;
        inner_call_node = bin.left.?;
        if (bin.right != null) {
            // bin.right is MatchBody or a block — check for children
            if (bin.right.?.children != null) {
                catch_body_node = bin.right.?;
            } else if (bin.right.?.left != null and bin.right.?.left.?.children != null) {
                catch_body_node = bin.right.?.left.?;
            }
        }
    } else {
        // fallback: treat .left as the call
        inner_call_node = try_node.left.?;
    }

    // 1. emit the call into a typed ErrorUnion temp
    if (add_tabs) try data.addTab(allocator);
    const inner_call = try c_expr.printExpression(allocator, data, inner_call_node);
    try data.appendCodeFmt(allocator, "{s} {s} = {s};\n", .{ union_type, tmp, inner_call });

    // 2. error-check block
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

    // 3. extract the success value
    const emit_const = !decl_node.is_mut or decl_node.node_type == ASTNodeType.ConstDeclaration;
    if (add_tabs) try data.addTab(allocator);
    if (emit_const) {
        try data.appendCodeFmt(allocator, "const {s} {s} = {s}.value;\n", .{ val_type, var_name, tmp });
    } else {
        try data.appendCodeFmt(allocator, "{s} {s} = {s}.value;\n", .{ val_type, var_name, tmp });
    }
    data.var_types.put(var_name, val_type) catch {};
}

/// Replace every '.' with '_' (State.Open → State_Open)
fn dotToUnderscore(allocator: *Allocator, s: []const u8) ConvertError![]u8 {
    const result = allocator.*.dupe(u8, s) catch return ConvertError.Out_Of_Memory;
    for (result) |*c| {
        if (c.* == '.') c.* = '_';
    }
    return result;
}

const MatchPayload = struct {
    case_label: []const u8,     // e.g. "Value_Int"
    variant_name: ?[]const u8,  // e.g. "Int"
    binding_name: ?[]const u8,  // e.g. "v"
    binding_type: ?[]const u8,  // e.g. "i32"
};

/// C6 FIX: Parse a match pattern and extract:
///   - case_label: the C enum tag to switch on (e.g. "Value_Int")
///   - binding: the variable to declare from the payload (e.g. "v")
///   - binding_type: C type from the union registry
///
/// Patterns handled:
///   State.Open           → case State_Open (no payload)
///   Value.Int(v)         → case Value_Int + i32 v = match_var.data.Int;
///   parsed as MemberAccess(Value, FunctionCall(Int, [Identifier(v)]))
fn extractMatchPayload(
    allocator: *Allocator,
    data: *ConvertData,
    pattern: *ASTNode,
    _match_var: []const u8,
) ConvertError!MatchPayload {
    _ = _match_var;

    // Case 1: plain MemberAccess like State.Open (no parens after)
    if (pattern.node_type == ASTNodeType.MemberAccess) {
        if (pattern.left == null or pattern.right == null) {
            return MatchPayload{ .case_label = "default", .variant_name = null, .binding_name = null, .binding_type = null };
        }
        const union_name = pattern.left.?.token.?.value;

        // right is either Identifier (no payload) or FunctionCall (with payload)
        if (pattern.right.?.node_type == ASTNodeType.FunctionCall) {
            // Value.Int(v) — payload binding
            const variant_name = pattern.right.?.token.?.value;
            const case_label = std.fmt.allocPrint(allocator.*, "{s}_{s}", .{ union_name, variant_name }) catch return ConvertError.Out_Of_Memory;

            // extract binding variable name from first argument
            var binding_name: ?[]const u8 = null;
            if (pattern.right.?.children != null and pattern.right.?.children.?.items.len > 0) {
                const arg = pattern.right.?.children.?.items[0];
                if (arg.node_type == ASTNodeType.Argument and arg.left != null) {
                    binding_name = arg.left.?.token.?.value;
                } else if (arg.token != null) {
                    binding_name = arg.token.?.value;
                }
            }

            // look up the variant's C type from the registry
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

    // Fallback: just print the expression and underscore-escape it
    const raw = try c_expr.printExpression(allocator, data, pattern);
    const label = try dotToUnderscore(allocator, raw);
    return MatchPayload{ .case_label = label, .variant_name = null, .binding_name = null, .binding_type = null };
}
