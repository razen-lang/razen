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

fn processFunctionBodyNode(allocator: *Allocator, data: *ConvertData, node: *ASTNode, add_new_line: bool, add_tabs: bool) ConvertError!void {
    data.error_function = "processFunctionBodyNode";

    switch (node.node_type) {
        ASTNodeType.ReturnStatement => try c_return.processReturn(allocator, data, node),
        ASTNodeType.VarDeclaration => try c_declaration.processDeclaration(allocator, data, node, add_new_line, add_tabs),
        ASTNodeType.ConstDeclaration => try c_declaration.processDeclaration(allocator, data, node, add_new_line, add_tabs),
        ASTNodeType.Assignment => try c_assignment.processAssignment(allocator, data, node, add_new_line, add_tabs),
        ASTNodeType.FunctionCall => {
            if (add_tabs) try data.addTab(allocator);
            const call_str = try c_expr.printExpression(allocator, data, node);
            try data.appendCodeFmt(allocator, "{s};", .{ call_str });
            if (add_new_line) try data.appendCode(allocator, "\n");
        },
        ASTNodeType.IfStatement => {
            if (add_tabs) try data.addTab(allocator);
            const cond = try c_expr.printExpression(allocator, data, node.left.?);
            try data.appendCodeFmt(allocator, "if ({s}) {{\n", .{ cond });
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
        },
        ASTNodeType.LoopStatement => {
            if (add_tabs) try data.addTab(allocator);
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
        },
        else => {
            // @TODO future AST statements
            if (add_tabs) try data.addTab(allocator);
            try data.appendCodeFmt(allocator, "// TODO: Handle node ({any})\n", .{ node.node_type });
        }
    }
}
