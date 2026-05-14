const std = @import("std");
const node_mod = @import("../../ast/node.zig");
const ASTNode = node_mod.ASTNode;
const ASTNodeType = node_mod.ASTNodeType;
const token_mod = @import("../../lexer/token.zig");
const ConvertError = @import("../errors.zig").ConvertError;
const convert_data_mod = @import("../convert_data.zig");
const ConvertData = convert_data_mod.ConvertData;
const llvm_flatten = @import("llvm_flatten.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub fn processReturn(
    allocator: *Allocator,
    convert_data: *ConvertData,
    node: *ASTNode,
) ConvertError!void {
    convert_data.error_function = "processReturn";

    if (node.token) |tok| {
        if (std.mem.eql(u8, tok.value, "break")) {
            if (convert_data.current_loop_exit_label) |exit_lbl| {
                convert_data.generated_code.appendFmt(allocator, "\tbr label %{s}\n", .{exit_lbl}) catch return ConvertError.Out_Of_Memory;
            } else {
                convert_data.generated_code.appendLine(allocator, "\tret void") catch return ConvertError.Out_Of_Memory;
            }
            convert_data.block_terminated = true;
            return;
        }
        if (std.mem.eql(u8, tok.value, "skip")) {
            if (convert_data.current_loop_continue_label) |cont_lbl| {
                convert_data.generated_code.appendFmt(allocator, "\tbr label %{s}\n", .{cont_lbl}) catch return ConvertError.Out_Of_Memory;
            } else {
                convert_data.generated_code.appendLine(allocator, "\tret void") catch return ConvertError.Out_Of_Memory;
            }
            convert_data.block_terminated = true;
            return;
        }
    }

    const val_node = node.left orelse node.right orelse {
        convert_data.generated_code.appendFmt(allocator, "\tret void\n", .{}) catch return ConvertError.Out_Of_Memory;
        convert_data.block_terminated = true;
        return;
    };

    var statements = std.ArrayList([]const u8).initCapacity(allocator.*, 0) catch return ConvertError.Out_Of_Memory;

    const final_value = llvm_flatten.flattenExpression(
        allocator,
        convert_data,
        val_node,
        true,
        &statements,
    ) catch |err| {
        if (err == ConvertError.Unimplemented_Node_Type) {
            convert_data.generated_code.appendFmt(
                allocator,
                "\t; TODO: unsupported return expression ({s})\n",
                .{@tagName(val_node.node_type)},
            ) catch {};
            const ret_type = convert_data.current_ret_type orelse "void";
            if (std.mem.eql(u8, ret_type, "void")) {
                convert_data.generated_code.appendFmt(allocator, "\tret void\n", .{}) catch return ConvertError.Out_Of_Memory;
            } else {
                convert_data.generated_code.appendFmt(allocator, "\tret {s} 0\n", .{ret_type}) catch return ConvertError.Out_Of_Memory;
            }
            convert_data.block_terminated = true;
            return;
        }
        return err;
    };

    if (statements.items.len > 0) {
        for (statements.items) |stmt| {
            convert_data.generated_code.appendFmt(allocator, "\t{s}\n", .{stmt}) catch return ConvertError.Out_Of_Memory;
        }
    }

    const ret_type = convert_data.current_ret_type orelse "i32";
    convert_data.generated_code.appendFmt(allocator, "\tret {s} {s}\n", .{ ret_type, final_value }) catch return ConvertError.Out_Of_Memory;
    convert_data.block_terminated = true;
}
