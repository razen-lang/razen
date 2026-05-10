const std = @import("std");
const node_mod = @import("../../ast/node.zig");
const convert_data = @import("../convert_data.zig");
const errors = @import("../errors.zig");

const c_return = @import("c_return.zig");
const c_declaration = @import("c_declaration.zig");
const c_assignment = @import("c_assignment.zig");
const c_expr = @import("c_expr.zig");
const c_utils = @import("c_utils.zig");

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

        // C3 FIX: match → switch/case (already correct), but also handles tagged-union payload
        ASTNodeType.MatchStatement => {
            if (node.left == null or node.children == null) return ConvertError.Node_Is_Null;
            const match_var = try c_expr.printExpression(allocator, data, node.left.?);

            if (add_tabs) try data.addTab(allocator);
            try data.appendCodeFmt(allocator, "switch ({s}) {{\n", .{match_var});

            for (node.children.?.items) |case_node| {
                if (case_node.node_type != ASTNodeType.MatchCase) continue;

                if (add_tabs) try data.addTab(allocator);

                if (case_node.left != null) {
                    const raw_label = try c_expr.printExpression(allocator, data, case_node.left.?);
                    const case_label = try dotToUnderscore(allocator, raw_label);
                    try data.appendCodeFmt(allocator, "case {s}:\n", .{case_label});
                } else {
                    try data.appendCode(allocator, "default:\n");
                }

                data.incrementIndexCount();
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
fn processTryCatch(allocator: *Allocator, data: *ConvertData, decl_node: *ASTNode, add_tabs: bool) ConvertError!void {
    const var_name = decl_node.token.?.value;
    const try_node = decl_node.right.?; // TryExpression

    // resolve declared type or default to i32
    var val_type: []const u8 = "i32";
    if (decl_node.left != null) {
        val_type = c_utils.nodeToCType(allocator, decl_node.left.?) catch "i32";
    }

    // capitalise first letter for ErrorUnion<Type>
    const union_type = std.fmt.allocPrint(allocator.*, "ErrorUnion_{s}", .{val_type}) catch return ConvertError.Out_Of_Memory;
    const tmp = try data.freshTmpName(allocator);

    // 1. emit the call into a typed ErrorUnion temp
    if (add_tabs) try data.addTab(allocator);
    const inner_call = try c_expr.printExpression(allocator, data, try_node.left.?);
    try data.appendCodeFmt(allocator, "{s} {s} = {s};\n", .{ union_type, tmp, inner_call });

    // 2. emit the error-check block (the catch body)
    if (add_tabs) try data.addTab(allocator);
    try data.appendCodeFmt(allocator, "if ({s}.error != RAZEN_OK) {{\n", .{tmp});
    data.incrementIndexCount();
    // catch body is: TryExpression.right = BinaryExpression(catch, inner, body)
    // body lives in try_node.right?.right (MatchBody / block)
    if (try_node.right != null and try_node.right.?.node_type == ASTNodeType.BinaryExpression) {
        const catch_bin = try_node.right.?;
        if (catch_bin.right != null and catch_bin.right.?.children != null) {
            try processBody(allocator, data, catch_bin.right.?);
        } else {
            // bare `ret` in catch
            if (add_tabs) try data.addTab(allocator);
            try data.appendCode(allocator, "return;\n");
        }
    } else {
        if (add_tabs) try data.addTab(allocator);
        try data.appendCode(allocator, "return;\n");
    }
    data.decrementIndexCount();
    if (add_tabs) try data.addTab(allocator);
    try data.appendCode(allocator, "}\n");

    // 3. extract the value
    const emit_const = !decl_node.is_mut or decl_node.node_type == ASTNodeType.ConstDeclaration;
    if (add_tabs) try data.addTab(allocator);
    if (emit_const) {
        try data.appendCodeFmt(allocator, "const {s} {s} = {s}.value;\n", .{ val_type, var_name, tmp });
    } else {
        try data.appendCodeFmt(allocator, "{s} {s} = {s}.value;\n", .{ val_type, var_name, tmp });
    }

    // track variable type
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
