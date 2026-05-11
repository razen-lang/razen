// llvm_function.zig — emit LLVM IR for function declarations.
//
// Mirrors the tutorial's llvm_function.zig exactly, adapted to Razen's AST:
//
//   FunctionDeclaration:
//     token  = function name
//     left   = ReturnType node → .left = VarType node (has the type token)
//     middle = Parameters node (children = list of Parameter nodes)
//     right  = Block / LoopBody / IfBody  (the function body)

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
const llvm_body = @import("llvm_body.zig");
const Allocator = std.mem.Allocator;

pub fn processFunctionDeclaration(
    allocator: *Allocator,
    convert_data: *ConvertData,
    node: *ASTNode,
) ConvertError!void {
    convert_data.error_function = "processFunctionDeclaration";

    // ── write   define <ret_type> @<name>(<params>) { ──────────────────────
    try writeFunctionSignature(allocator, convert_data, node);

    // ── body ───────────────────────────────────────────────────────────────
    convert_data.generated_code.appendLine(allocator, "entry:")
        catch return ConvertError.Out_Of_Memory;

    // Reset tmp_counter per function so %t0 … labels are local
    convert_data.tmp_counter = 0;

    if (node.right) |body| {
        try llvm_body.processBody(allocator, convert_data, body);
    } else {
        // Empty body — emit a safe default terminator
        const ret_type = convert_data.current_ret_type orelse "void";
        if (std.mem.eql(u8, ret_type, "void")) {
            convert_data.generated_code.appendLine(allocator, "\tret void")
                catch return ConvertError.Out_Of_Memory;
        } else {
            convert_data.generated_code.appendFmt(allocator, "\tret {s} 0\n", .{ret_type})
                catch return ConvertError.Out_Of_Memory;
        }
    }

    convert_data.generated_code.append(allocator, "}\n\n")
        catch return ConvertError.Out_Of_Memory;
}

// ── function signature line ───────────────────────────────────────────────────

fn writeFunctionSignature(
    allocator: *Allocator,
    convert_data: *ConvertData,
    node: *ASTNode,
) ConvertError!void {
    convert_data.error_function = "writeFunctionSignature";

    // ── function name ──────────────────────────────────────────────────────
    const fn_token = node.token orelse {
        convert_data.error_detail = "FunctionDeclaration: token (name) is null";
        return ConvertError.Node_Is_Null;
    };
    const fn_name = fn_token.value;

    // ── return type ────────────────────────────────────────────────────────
    // AST: node.left = ReturnType  → .left = VarType (token = actual type kw)
    var ret_type: []const u8 = "void";
    if (node.left) |ret_node| {
        var base = ret_node;
        while (base.left != null) base = base.left.?;
        if (base.token) |tok| {
            if (llvm_utils.convertToLLVMType(tok)) |t| ret_type = t;
        }
    }
    convert_data.current_ret_type = ret_type;

    // ── emit define line ───────────────────────────────────────────────────
    convert_data.generated_code.appendFmt(allocator, "define {s} @{s}(", .{ ret_type, fn_name })
        catch return ConvertError.Out_Of_Memory;

    // ── parameters ─────────────────────────────────────────────────────────
    if (node.middle != null) {
        try writeParameters(allocator, convert_data, node);
    }

    convert_data.generated_code.append(allocator, ") {\n")
        catch return ConvertError.Out_Of_Memory;
}

fn writeParameters(
    allocator: *Allocator,
    convert_data: *ConvertData,
    node: *ASTNode,
) ConvertError!void {
    const params_node = node.middle orelse return;
    const children = params_node.children orelse return;
    const child_count = children.items.len;
    if (child_count == 0) return;

    for (0..child_count) |i| {
        const child = children.items[i];
        if (child.token == null) {
            convert_data.error_detail = "Parameter: token (name) is null";
            return ConvertError.Node_Is_Null;
        }
        const param_name = child.token.?.value;

        // Resolve the parameter type (same recursive walk as return type)
        const type_node = child.left orelse {
            convert_data.error_detail = "Parameter: left (type) is null";
            return ConvertError.Node_Is_Null;
        };
        var base = type_node;
        while (base.left != null) base = base.left.?;

        var param_type: []const u8 = "i32";
        if (base.token) |tok| {
            if (llvm_utils.convertToLLVMType(tok)) |t| param_type = t;
        }

        // In LLVM IR, parameters are plain values: `i32 %name`
        convert_data.generated_code.appendFmt(allocator, "{s} %{s}", .{ param_type, param_name })
            catch return ConvertError.Out_Of_Memory;

        if (i < child_count - 1) {
            convert_data.generated_code.append(allocator, ", ")
                catch return ConvertError.Out_Of_Memory;
        }

        // Record parameter name so load codegen can find it
        convert_data.var_types.put(param_name, param_type) catch return ConvertError.Out_Of_Memory;
    }
}
