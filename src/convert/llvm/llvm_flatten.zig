// llvm_flatten.zig - expression flattening for Razen -> LLVM IR.
//
// Follows the tutorial's flatten_expression.zig pattern,
// adapted to Razen field names (token.value, token.token_type, ASTNodeType.*).
//
// flattenExpression():
//   - Returns the SSA register name or literal holding the result.
//   - Appends all intermediate instructions to `statements`.
//   - Caller emits `statements` then uses the returned value.

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
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// --------------------------------------------------------------------------
// Public entry point
// --------------------------------------------------------------------------

pub fn flattenExpression(
    allocator: *Allocator,
    convert_data: *ConvertData,
    node: *ASTNode,
    no_strings: bool,
    statements: *ArrayList([]const u8),
) ConvertError![]const u8 {
    switch (node.node_type) {

        // -- literals -------------------------------------------------------
        .IntegerLiteral, .BoolLiteral => {
            if (node.token == null) return ConvertError.Node_Is_Null;
            const v = node.token.?.value;
            if (std.mem.eql(u8, v, "true")) return "1";
            if (std.mem.eql(u8, v, "false")) return "0";
            return v;
        },
        .FloatLiteral => {
            if (node.token == null) return ConvertError.Node_Is_Null;
            return node.token.?.value;
        },
        .CharLiteral => {
            if (node.token == null) return ConvertError.Node_Is_Null;
            return node.token.?.value;
        },
        .StringLiteral => {
            if (node.token == null) return ConvertError.Node_Is_Null;
            const s = node.token.?.value;
            _ = s;
            return "0";
        },

        // -- identifier (variable / parameter) ------------------------------
        .Identifier => {
            if (node.token == null) return ConvertError.Node_Is_Null;
            const name = node.token.?.value;

            // Check whether this is a local variable (has alloca)
            if (convert_data.var_types.get(name)) |llvm_type| {
                const addr_key = std.fmt.allocPrint(allocator.*, "%{s}_addr", .{name}) catch return ConvertError.Out_Of_Memory;
                if (convert_data.var_types.get(addr_key) != null) {
                    // Local variable -- emit a load
                    const reg = try freshReg(allocator, convert_data);
                    const line = std.fmt.allocPrint(
                        allocator.*,
                        "{s} = load {s}, {s}* %{s}_addr",
                        .{ reg, llvm_type, llvm_type, name },
                    ) catch return ConvertError.Out_Of_Memory;
                    statements.append(allocator.*, line) catch return ConvertError.Out_Of_Memory;
                    return reg;
                }
                // Parameter -- already in %name
                return std.fmt.allocPrint(allocator.*, "%{s}", .{name}) catch return ConvertError.Out_Of_Memory;
            }
            // Check global constants (e.g. const MAX : i32 = 100)
            if (convert_data.global_constants.get(name)) |val| {
                return val;
            }
            convert_data.error_detail = "Undefined identifier";
            convert_data.error_token = node.token;
            return ConvertError.Invalid_Node_Type;
        },

        // -- binary expression ----------------------------------------------
        .BinaryExpression => {
            return try flattenBinaryExpression(allocator, convert_data, node, no_strings, statements);
        },

        // -- unary: prefix (-x, !x) and postfix (ptr.*) --------------------
        .UnaryExpression => {
            if (node.token == null) return ConvertError.Node_Is_Null;
            const op = node.token.?.value;
            // Razen: prefix ops store operand on .right; postfix (.*) on .left
            const operand_node = node.right orelse node.left orelse return ConvertError.Node_Is_Null;
            const sub = try flattenExpression(allocator, convert_data, operand_node, no_strings, statements);

            // Pointer dereference ptr.* -- emit load
            if (std.mem.eql(u8, op, ".*")) {
                const reg = try freshReg(allocator, convert_data);
                const line = std.fmt.allocPrint(allocator.*, "{s} = load i32, i32* {s}", .{ reg, sub }) catch return ConvertError.Out_Of_Memory;
                statements.append(allocator.*, line) catch return ConvertError.Out_Of_Memory;
                return reg;
            }
            if (std.mem.eql(u8, op, "-")) {
                const reg = try freshReg(allocator, convert_data);
                const line = std.fmt.allocPrint(allocator.*, "{s} = sub i32 0, {s}", .{ reg, sub }) catch return ConvertError.Out_Of_Memory;
                statements.append(allocator.*, line) catch return ConvertError.Out_Of_Memory;
                return reg;
            }
            if (std.mem.eql(u8, op, "!")) {
                const reg = try freshReg(allocator, convert_data);
                const line = std.fmt.allocPrint(allocator.*, "{s} = xor i1 {s}, true", .{ reg, sub }) catch return ConvertError.Out_Of_Memory;
                statements.append(allocator.*, line) catch return ConvertError.Out_Of_Memory;
                return reg;
            }
            // Address-of & -- return the alloca pointer as-is
            if (std.mem.eql(u8, op, "&")) {
                return sub;
            }
            // Unknown unary op -- return operand unchanged
            return sub;
        },

        // -- function call --------------------------------------------------
        .FunctionCall => {
            return try flattenFunctionCall(allocator, convert_data, node, statements);
        },

        // -- member access (std.fmt.X etc.) -- return placeholder ----------
        .MemberAccess => return "0",

        else => {
            convert_data.error_detail = "flattenExpression: unsupported node type";
            convert_data.error_token = node.token;
            return ConvertError.Unimplemented_Node_Type;
        },
    }
}

// --------------------------------------------------------------------------
// Binary expression
// --------------------------------------------------------------------------

fn flattenBinaryExpression(
    allocator: *Allocator,
    convert_data: *ConvertData,
    node: *ASTNode,
    no_strings: bool,
    statements: *ArrayList([]const u8),
) ConvertError![]const u8 {
    if (node.left == null) {
        convert_data.error_detail = "flattenBinaryExpression: node.left null";
        return ConvertError.Node_Is_Null;
    }
    if (node.right == null) {
        convert_data.error_detail = "flattenBinaryExpression: node.right null";
        return ConvertError.Node_Is_Null;
    }
    if (node.token == null) {
        convert_data.error_detail = "flattenBinaryExpression: node.token null";
        return ConvertError.Node_Is_Null;
    }

    var left_stmts = std.ArrayList([]const u8).initCapacity(allocator.*, 0) catch return ConvertError.Out_Of_Memory;
    const lv = try flattenExpression(allocator, convert_data, node.left.?, no_strings, &left_stmts);

    var right_stmts = std.ArrayList([]const u8).initCapacity(allocator.*, 0) catch return ConvertError.Out_Of_Memory;
    const rv = try flattenExpression(allocator, convert_data, node.right.?, no_strings, &right_stmts);

    const op = node.token.?.value;

    // Flush sub-statements in order
    statements.appendSlice(allocator.*, left_stmts.items) catch return ConvertError.Out_Of_Memory;
    statements.appendSlice(allocator.*, right_stmts.items) catch return ConvertError.Out_Of_Memory;

    // Comparison -> icmp (i1) + zext to i32
    if (llvm_utils.convertToLLVMCmp(op)) |pred| {
        const icmp_reg = try freshReg(allocator, convert_data);
        const icmp_line = std.fmt.allocPrint(allocator.*, "{s} = {s} {s}, {s}", .{ icmp_reg, pred, lv, rv }) catch return ConvertError.Out_Of_Memory;
        statements.append(allocator.*, icmp_line) catch return ConvertError.Out_Of_Memory;
        const ze_reg = try freshReg(allocator, convert_data);
        const ze_line = std.fmt.allocPrint(allocator.*, "{s} = zext i1 {s} to i32", .{ ze_reg, icmp_reg }) catch return ConvertError.Out_Of_Memory;
        statements.append(allocator.*, ze_line) catch return ConvertError.Out_Of_Memory;
        return ze_reg;
    }

    // Arithmetic -> add / sub / mul / ...
    if (llvm_utils.convertToLLVMOperator(op)) |instr| {
        const reg = try freshReg(allocator, convert_data);
        const line = std.fmt.allocPrint(allocator.*, "{s} = {s} {s}, {s}", .{ reg, instr, lv, rv }) catch return ConvertError.Out_Of_Memory;
        statements.append(allocator.*, line) catch return ConvertError.Out_Of_Memory;
        return reg;
    }

    // Logical && / ||
    if (std.mem.eql(u8, op, "&&") or std.mem.eql(u8, op, "and")) {
        const reg = try freshReg(allocator, convert_data);
        const line = std.fmt.allocPrint(allocator.*, "{s} = and i1 {s}, {s}", .{ reg, lv, rv }) catch return ConvertError.Out_Of_Memory;
        statements.append(allocator.*, line) catch return ConvertError.Out_Of_Memory;
        return reg;
    }
    if (std.mem.eql(u8, op, "||") or std.mem.eql(u8, op, "or")) {
        const reg = try freshReg(allocator, convert_data);
        const line = std.fmt.allocPrint(allocator.*, "{s} = or i1 {s}, {s}", .{ reg, lv, rv }) catch return ConvertError.Out_Of_Memory;
        statements.append(allocator.*, line) catch return ConvertError.Out_Of_Memory;
        return reg;
    }

    convert_data.error_detail = "Unknown binary operator";
    convert_data.error_token = node.token;
    return ConvertError.Unimplemented_Node_Type;
}

// --------------------------------------------------------------------------
// Function call
// --------------------------------------------------------------------------

fn flattenFunctionCall(
    allocator: *Allocator,
    convert_data: *ConvertData,
    node: *ASTNode,
    statements: *ArrayList([]const u8),
) ConvertError![]const u8 {
    if (node.token == null) return ConvertError.Node_Is_Null;
    const fn_name = node.token.?.value;

    var args_buf = std.ArrayList(u8).initCapacity(allocator.*, 0) catch return ConvertError.Out_Of_Memory;

    if (node.children) |children| {
        for (children.items, 0..) |arg_node, i| {
            const expr_node: *ASTNode = if (arg_node.left != null) arg_node.left.? else arg_node;
            var arg_stmts = std.ArrayList([]const u8).initCapacity(allocator.*, 4) catch return ConvertError.Out_Of_Memory;
            const arg_val = try flattenExpression(allocator, convert_data, expr_node, true, &arg_stmts);
            for (arg_stmts.items) |s| {
                statements.append(allocator.*, s) catch return ConvertError.Out_Of_Memory;
            }
            if (i > 0) args_buf.appendSlice(allocator.*, ", ") catch return ConvertError.Out_Of_Memory;
            const arg_text = std.fmt.allocPrint(allocator.*, "i32 {s}", .{arg_val}) catch return ConvertError.Out_Of_Memory;
            args_buf.appendSlice(allocator.*, arg_text) catch return ConvertError.Out_Of_Memory;
        }
    }

    const reg = try freshReg(allocator, convert_data);
    const line = std.fmt.allocPrint(allocator.*, "{s} = call i32 @{s}({s})", .{ reg, fn_name, args_buf.items }) catch return ConvertError.Out_Of_Memory;
    statements.append(allocator.*, line) catch return ConvertError.Out_Of_Memory;
    return reg;
}

// --------------------------------------------------------------------------
// SSA register helper
// --------------------------------------------------------------------------

pub fn freshReg(allocator: *Allocator, convert_data: *ConvertData) ConvertError![]u8 {
    const name = std.fmt.allocPrint(allocator.*, "%t{d}", .{convert_data.tmp_counter}) catch return ConvertError.Out_Of_Memory;
    convert_data.tmp_counter += 1;
    return name;
}
