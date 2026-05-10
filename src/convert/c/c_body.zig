const std = @import("std");
const node_mod = @import("../../ast/node.zig");
const convert_data = @import("../convert_data.zig");
const errors = @import("../errors.zig");

const c_return = @import("c_return.zig");
const c_declaration = @import("c_declaration.zig");
const c_assignment = @import("c_assignment.zig");
const c_expr = @import("c_expr.zig");

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

/// Public wrapper used by c_function.emitDeferredStatements to replay stored nodes.
pub fn processStatement(allocator: *Allocator, data: *ConvertData, node: *ASTNode) ConvertError!void {
    try processFunctionBodyNode(allocator, data, node, true, true);
}

fn processFunctionBodyNode(allocator: *Allocator, data: *ConvertData, node: *ASTNode, add_new_line: bool, add_tabs: bool) ConvertError!void {
    data.error_function = "processFunctionBodyNode";

    switch (node.node_type) {
        ASTNodeType.VarDeclaration => {
            try c_declaration.processDeclaration(allocator, data, node, add_new_line, add_tabs);
            data.last_statement_was_return = false;
        },
        ASTNodeType.ConstDeclaration => {
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
            try data.appendCodeFmt(allocator, "{s};", .{call_str});
            if (add_new_line) try data.appendCode(allocator, "\n");
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
                // loop items |i| { ... }
                const items = try c_expr.printExpression(allocator, data, node.left.?);
                const i = node.middle.?.token.?.value;
                try data.appendCodeFmt(allocator, "// Simplified loop array\n", .{});
                try data.addTab(allocator);
                try data.appendCodeFmt(allocator, "for (size_t _idx = 0; _idx < sizeof({s})/sizeof({s}[0]); _idx++) {{\n", .{ items, items });
                data.incrementIndexCount();
                try data.addTab(allocator);
                try data.appendCodeFmt(allocator, "__auto_type {s} = {s}[_idx];\n", .{ i, items });
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

        // Bug 8: emit match as switch/case instead of if/else if
        ASTNodeType.MatchStatement => {
            if (node.left == null or node.children == null) return ConvertError.Node_Is_Null;
            const match_var = try c_expr.printExpression(allocator, data, node.left.?);

            if (add_tabs) try data.addTab(allocator);
            try data.appendCodeFmt(allocator, "switch ({s}) {{\n", .{match_var});

            for (node.children.?.items) |case_node| {
                if (case_node.node_type != ASTNodeType.MatchCase) continue;

                if (add_tabs) try data.addTab(allocator);

                if (case_node.left != null) {
                    // e.g. State.Open → State_Open
                    const raw_label = try c_expr.printExpression(allocator, data, case_node.left.?);
                    const case_label = try dotToUnderscore(allocator, raw_label);
                    try data.appendCodeFmt(allocator, "case {s}:\n", .{case_label});
                } else {
                    // wildcard / else → default
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

        // Bug 7: don't emit defer immediately — collect it, flush before returns/end-of-function
        ASTNodeType.DeferStatement => {
            if (node.left != null) {
                data.deferred_stmts.append(allocator.*, node) catch return ConvertError.Out_Of_Memory;
            }
            data.last_statement_was_return = false;
        },

        ASTNodeType.MemberAccess => {
            if (add_tabs) try data.addTab(allocator);
            const call_str = try c_expr.printExpression(allocator, data, node);
            try data.appendCodeFmt(allocator, "{s};", .{call_str});
            if (add_new_line) try data.appendCode(allocator, "\n");
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

/// Bug 8 helper: replace every '.' with '_' in a label string (e.g. "State.Open" → "State_Open").
fn dotToUnderscore(allocator: *Allocator, s: []const u8) ConvertError![]u8 {
    const result = allocator.*.dupe(u8, s) catch return ConvertError.Out_Of_Memory;
    for (result) |*c| {
        if (c.* == '.') c.* = '_';
    }
    return result;
}
