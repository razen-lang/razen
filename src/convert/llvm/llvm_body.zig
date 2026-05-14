// llvm_body.zig — emit LLVM IR for function body statements.
//
// Mirrors the tutorial's llvm_body.zig pattern, extended with Razen-specific
// statement types (VarDeclaration, IfStatement, LoopStatement, Assignment).

const std = @import("std");
const node_mod = @import("../../ast/node.zig");
const ASTNode = node_mod.ASTNode;
const ASTNodeType = node_mod.ASTNodeType;
const token_mod = @import("../../lexer/token.zig");
const TokenType = token_mod.TokenType;
const ConvertError = @import("../errors.zig").ConvertError;
const convert_data_mod = @import("../convert_data.zig");
const ConvertData = convert_data_mod.ConvertData;
const llvm_utils = @import("llvm_utils.zig");
const llvm_flatten = @import("llvm_flatten.zig");
const llvm_return = @import("llvm_return.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

/// Walk every child of a body/block node and emit IR for each statement.
pub fn processBody(
    allocator: *Allocator,
    convert_data: *ConvertData,
    node: *ASTNode,
) ConvertError!void {
    convert_data.error_function = "processBody";

    if (node.children == null) return;

    const child_count = node.children.?.items.len;
    if (child_count == 0) return;

    for (0..child_count) |i| {
        const child: *ASTNode = node.children.?.items[i];
        try processFunctionBodyNode(allocator, convert_data, child);
    }
}

// ── statement dispatcher ──────────────────────────────────────────────────────

fn processFunctionBodyNode(
    allocator: *Allocator,
    convert_data: *ConvertData,
    node: *ASTNode,
) ConvertError!void {
    switch (node.node_type) {
        .ReturnStatement => try llvm_return.processReturn(allocator, convert_data, node),
        .VarDeclaration, .ConstDeclaration => try processLocalDecl(allocator, convert_data, node),
        .Assignment => try processAssignment(allocator, convert_data, node),
        .IfStatement => try processIf(allocator, convert_data, node),
        .LoopStatement => try processLoop(allocator, convert_data, node),
        .FunctionCall, .MemberAccess => try processCallStmt(allocator, convert_data, node),
        .Block, .IfBody, .ElseBody, .LoopBody => try processBody(allocator, convert_data, node),
        .Comment => {},
        // Not yet implemented — emit a comment and keep going
        .TryExpression, .CatchExpression, .DeferStatement, .MatchStatement, .MatchCase, .MatchBody, .BuiltinExpression => {
            convert_data.generated_code.appendFmt(
                allocator,
                "\t; TODO: {s}\n",
                .{@tagName(node.node_type)},
            ) catch {};
        },
        else => {},
    }
}

// ── variable declaration (alloca + optional store) ────────────────────────────
//
// AST layout (Razen):
//   token = variable name
//   left  = type node chain  (VarType at the deepest .left)
//   right = initial value expression (optional)

fn processLocalDecl(
    allocator: *Allocator,
    convert_data: *ConvertData,
    node: *ASTNode,
) ConvertError!void {
    convert_data.error_function = "processLocalDecl";

    if (node.token == null) return ConvertError.Node_Is_Null;
    const var_name = node.token.?.value;

    // ── resolve LLVM type ──────────────────────────────────────────────────
    var llvm_type: []const u8 = "i32";
    if (node.left) |type_node| {
        var base = type_node;
        while (base.left != null) base = base.left.?;
        if (base.token) |tok| {
            if (llvm_utils.convertToLLVMType(tok)) |t| llvm_type = t;
        }
    }

    // alloca
    const addr_reg = std.fmt.allocPrint(allocator.*, "%{s}_addr", .{var_name}) catch return ConvertError.Out_Of_Memory;
    convert_data.generated_code.appendFmt(allocator, "\t{s} = alloca {s}\n", .{ addr_reg, llvm_type }) catch return ConvertError.Out_Of_Memory;

    // optional initial store
    if (node.right) |val_node| {
        var stmts = std.ArrayList([]const u8).initCapacity(allocator.*, 0) catch return ConvertError.Out_Of_Memory;
        const val = llvm_flatten.flattenExpression(allocator, convert_data, val_node, true, &stmts) catch |err| {
            _ = @errorName(err);
            convert_data.generated_code.appendFmt(
                allocator,
                "\t; TODO: unsupported initial value ({s})\n",
                .{@tagName(val_node.node_type)},
            ) catch {};
            return;
        };
        for (stmts.items) |s| {
            convert_data.generated_code.appendFmt(allocator, "\t{s}\n", .{s}) catch return ConvertError.Out_Of_Memory;
        }
        convert_data.generated_code.appendFmt(allocator, "\tstore {s} {s}, {s}* {s}\n", .{
            llvm_type, val, llvm_type, addr_reg,
        }) catch return ConvertError.Out_Of_Memory;
    }

    // Record for later loads/stores
    convert_data.var_types.put(var_name, llvm_type) catch return ConvertError.Out_Of_Memory;
    // Store alloca metadata as "<type>|<addr>" keyed by addr_reg
    const meta = std.fmt.allocPrint(allocator.*, "{s}|{s}", .{ llvm_type, addr_reg }) catch return ConvertError.Out_Of_Memory;
    convert_data.var_types.put(addr_reg, meta) catch return ConvertError.Out_Of_Memory;
}

// ── assignment ────────────────────────────────────────────────────────────────

fn processAssignment(
    allocator: *Allocator,
    convert_data: *ConvertData,
    node: *ASTNode,
) ConvertError!void {
    convert_data.error_function = "processAssignment";

    if (node.left == null) return ConvertError.Node_Is_Null;
    if (node.right == null) return ConvertError.Node_Is_Null;

    const left_node = node.left.?;
    if (left_node.node_type != .Identifier) return ConvertError.Unimplemented_Node_Type;
    if (left_node.token == null) return ConvertError.Node_Is_Null;

    const var_name = left_node.token.?.value;
    const llvm_type = convert_data.var_types.get(var_name) orelse "i32";
    const addr_reg = std.fmt.allocPrint(allocator.*, "%{s}_addr", .{var_name}) catch return ConvertError.Out_Of_Memory;

    var stmts = std.ArrayList([]const u8).initCapacity(allocator.*, 0) catch return ConvertError.Out_Of_Memory;
    const val = llvm_flatten.flattenExpression(allocator, convert_data, node.right.?, true, &stmts) catch |err| {
        _ = @errorName(err);
        convert_data.generated_code.appendFmt(
            allocator,
            "\t; TODO: unsupported assignment rhs ({s})\n",
            .{@tagName(node.right.?.node_type)},
        ) catch {};
        return;
    };
    for (stmts.items) |s| {
        convert_data.generated_code.appendFmt(allocator, "\t{s}\n", .{s}) catch return ConvertError.Out_Of_Memory;
    }

    const op_tok = node.token orelse return ConvertError.Node_Is_Null;
    const op = op_tok.value;

    if (std.mem.eql(u8, op, "=")) {
        convert_data.generated_code.appendFmt(allocator, "\tstore {s} {s}, {s}* {s}\n", .{
            llvm_type, val, llvm_type, addr_reg,
        }) catch return ConvertError.Out_Of_Memory;
    } else {
        const old_reg = try llvm_flatten.freshReg(allocator, convert_data);
        convert_data.generated_code.appendFmt(allocator, "\t{s} = load {s}, {s}* {s}\n", .{
            old_reg, llvm_type, llvm_type, addr_reg,
        }) catch return ConvertError.Out_Of_Memory;

        var op_stripped = op;
        if (op.len > 0 and op[op.len - 1] == '=') {
            op_stripped = op[0 .. op.len - 1];
        }

        if (llvm_utils.convertToLLVMOperator(op_stripped)) |instr| {
            const new_reg = try llvm_flatten.freshReg(allocator, convert_data);
            convert_data.generated_code.appendFmt(allocator, "\t{s} = {s} {s}, {s}\n", .{
                new_reg, instr, old_reg, val,
            }) catch return ConvertError.Out_Of_Memory;

            convert_data.generated_code.appendFmt(allocator, "\tstore {s} {s}, {s}* {s}\n", .{
                llvm_type, new_reg, llvm_type, addr_reg,
            }) catch return ConvertError.Out_Of_Memory;
        } else {
            convert_data.generated_code.appendFmt(allocator, "\t; TODO: unsupported compound assignment {s}\n", .{op}) catch {};
        }
    }
}

// ── if / else ─────────────────────────────────────────────────────────────────
//
// Razen IfStatement AST layout:
//   left   = condition expression
//   middle = IfBody  (then branch — has .children)
//   right  = ElseBody (optional — has .children)

fn processIf(
    allocator: *Allocator,
    convert_data: *ConvertData,
    node: *ASTNode,
) ConvertError!void {
    convert_data.error_function = "processIf";

    const cond_node = node.left orelse return ConvertError.Node_Is_Null;

    var stmts = std.ArrayList([]const u8).initCapacity(allocator.*, 0) catch return ConvertError.Out_Of_Memory;
    const cond_val = llvm_flatten.flattenExpression(allocator, convert_data, cond_node, true, &stmts) catch |err| {
        _ = @errorName(err);
        convert_data.generated_code.appendFmt(
            allocator,
            "\t; TODO: unsupported if condition ({s})\n",
            .{@tagName(cond_node.node_type)},
        ) catch {};
        return;
    };
    for (stmts.items) |s| {
        convert_data.generated_code.appendFmt(allocator, "\t{s}\n", .{s}) catch return ConvertError.Out_Of_Memory;
    }

    const then_lbl = try freshLabel(allocator, convert_data);
    const merge_lbl = try freshLabel(allocator, convert_data);

    var then_terminated = false;
    var else_terminated = false;

    if (node.right != null) {
        const else_lbl = try freshLabel(allocator, convert_data);
        convert_data.generated_code.appendFmt(
            allocator,
            "\tbr i1 {s}, label %{s}, label %{s}\n",
            .{ cond_val, then_lbl, else_lbl },
        ) catch return ConvertError.Out_Of_Memory;

        convert_data.generated_code.appendFmt(allocator, "{s}:\n", .{then_lbl}) catch return ConvertError.Out_Of_Memory;
        convert_data.block_terminated = false;
        if (node.middle) |then_body| try processBody(allocator, convert_data, then_body);
        then_terminated = convert_data.block_terminated;
        if (!then_terminated)
            convert_data.generated_code.appendFmt(allocator, "\tbr label %{s}\n", .{merge_lbl}) catch return ConvertError.Out_Of_Memory;

        convert_data.generated_code.appendFmt(allocator, "{s}:\n", .{else_lbl}) catch return ConvertError.Out_Of_Memory;
        convert_data.block_terminated = false;
        try processBody(allocator, convert_data, node.right.?);
        else_terminated = convert_data.block_terminated;
        if (!else_terminated)
            convert_data.generated_code.appendFmt(allocator, "\tbr label %{s}\n", .{merge_lbl}) catch return ConvertError.Out_Of_Memory;
    } else {
        convert_data.generated_code.appendFmt(
            allocator,
            "\tbr i1 {s}, label %{s}, label %{s}\n",
            .{ cond_val, then_lbl, merge_lbl },
        ) catch return ConvertError.Out_Of_Memory;

        convert_data.generated_code.appendFmt(allocator, "{s}:\n", .{then_lbl}) catch return ConvertError.Out_Of_Memory;
        convert_data.block_terminated = false;
        if (node.middle) |then_body| try processBody(allocator, convert_data, then_body);
        then_terminated = convert_data.block_terminated;
        if (!then_terminated)
            convert_data.generated_code.appendFmt(allocator, "\tbr label %{s}\n", .{merge_lbl}) catch return ConvertError.Out_Of_Memory;
    }

    const need_merge = if (node.right != null) !then_terminated or !else_terminated else true;
    if (need_merge) {
        convert_data.block_terminated = false;
        convert_data.generated_code.appendFmt(allocator, "{s}:\n", .{merge_lbl}) catch return ConvertError.Out_Of_Memory;
    } else {
        convert_data.block_terminated = true;
    }
}

// ── loop (infinite, back-edge only) ──────────────────────────────────────────

fn processLoop(
    allocator: *Allocator,
    convert_data: *ConvertData,
    node: *ASTNode,
) ConvertError!void {
    convert_data.error_function = "processLoop";

    const loop_lbl = try freshLabel(allocator, convert_data);
    const exit_lbl = try freshLabel(allocator, convert_data);

    const saved_exit = convert_data.current_loop_exit_label;
    const saved_continue = convert_data.current_loop_continue_label;
    convert_data.current_loop_exit_label = exit_lbl;
    convert_data.current_loop_continue_label = loop_lbl;

    convert_data.generated_code.appendFmt(allocator, "\tbr label %{s}\n", .{loop_lbl}) catch return ConvertError.Out_Of_Memory;
    convert_data.generated_code.appendFmt(allocator, "{s}:\n", .{loop_lbl}) catch return ConvertError.Out_Of_Memory;

    if (node.right) |body| try processBody(allocator, convert_data, body);

    convert_data.generated_code.appendFmt(allocator, "\tbr label %{s}\n", .{loop_lbl}) catch return ConvertError.Out_Of_Memory;
    convert_data.generated_code.appendFmt(allocator, "{s}:\n", .{exit_lbl}) catch return ConvertError.Out_Of_Memory;

    convert_data.current_loop_exit_label = saved_exit;
    convert_data.current_loop_continue_label = saved_continue;
}

// ── standalone function call / member-access call ─────────────────────────────
//
// For  std.fmt.println("…")  the AST is:
//   MemberAccess  .
//     left  = MemberAccess  .
//               left = Identifier  std
//               right= Identifier  fmt
//     right = FunctionCall  println
//
// We walk down to the deepest right FunctionCall and emit it.

fn processCallStmt(
    allocator: *Allocator,
    convert_data: *ConvertData,
    node: *ASTNode,
) ConvertError!void {
    convert_data.error_function = "processCallStmt";

    // Unwrap MemberAccess chains to find the innermost FunctionCall.
    // Guard: if .right is null (e.g. ptr.* dereference) just emit a TODO comment.
    var target = node;
    while (target.node_type == .MemberAccess) {
        if (target.right) |r| {
            target = r;
        } else {
            convert_data.generated_code.appendFmt(
                allocator,
                "\t; TODO: MemberAccess with null right child\n",
                .{},
            ) catch {};
            return;
        }
    }

    var stmts = std.ArrayList([]const u8).initCapacity(allocator.*, 0) catch return ConvertError.Out_Of_Memory;

    _ = llvm_flatten.flattenExpression(allocator, convert_data, target, true, &stmts) catch |err| {
        _ = @errorName(err);
        convert_data.generated_code.appendFmt(
            allocator,
            "\t; TODO: skipped call ({s})\n",
            .{@tagName(target.node_type)},
        ) catch {};
        return;
    };
    for (stmts.items) |s| {
        convert_data.generated_code.appendFmt(allocator, "\t{s}\n", .{s}) catch return ConvertError.Out_Of_Memory;
    }
}

// ── label helper ─────────────────────────────────────────────────────────────

fn freshLabel(allocator: *Allocator, convert_data: *ConvertData) ConvertError![]u8 {
    const name = std.fmt.allocPrint(allocator.*, "lbl{d}", .{convert_data.tmp_counter}) catch return ConvertError.Out_Of_Memory;
    convert_data.tmp_counter += 1;
    return name;
}
