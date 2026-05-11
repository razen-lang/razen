// llvm_return.zig — emit LLVM IR for `ret` statements.
//
// Mirrors the tutorial's llvm_return.zig, adapted to Razen's AST layout:
//   ReturnStatement:
//     token = "ret" keyword
//     left  = value expression (Razen stores the return value on LEFT, not right)

const std = @import("std");
const node_mod = @import("../../ast/node.zig");
const ASTNode = node_mod.ASTNode;
const ASTNodeType = node_mod.ASTNodeType;
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

    // Razen's ReturnStatement stores the value on .left (not .right)
    const val_node = node.left orelse node.right orelse {
        // No value — void return
        convert_data.generated_code.appendFmt(allocator, "\tret void\n", .{})
            catch return ConvertError.Out_Of_Memory;
        return;
    };

    // Allocate a fresh statement list and flatten the return expression
    var statements = std.ArrayList([]const u8).initCapacity(allocator.*, 0)
        catch return ConvertError.Out_Of_Memory;

    const final_value = llvm_flatten.flattenExpression(
        allocator, convert_data, val_node, true, &statements,
    ) catch |err| {
        // Unimplemented expression type — emit a safe fallback
        if (err == ConvertError.Unimplemented_Node_Type) {
            convert_data.generated_code.appendFmt(allocator,
                "\t; TODO: unsupported return expression ({s})\n",
                .{@tagName(val_node.node_type)},
            ) catch {};
            const ret_type = convert_data.current_ret_type orelse "void";
            if (std.mem.eql(u8, ret_type, "void")) {
                convert_data.generated_code.appendFmt(allocator, "\tret void\n", .{})
                    catch return ConvertError.Out_Of_Memory;
            } else {
                convert_data.generated_code.appendFmt(allocator, "\tret {s} 0\n", .{ret_type})
                    catch return ConvertError.Out_Of_Memory;
            }
            return;
        }
        return err;
    };

    // Emit any intermediate SSA instructions first
    if (statements.items.len > 0) {
        for (statements.items) |stmt| {
            convert_data.generated_code.appendFmt(allocator, "\t{s}\n", .{stmt})
                catch return ConvertError.Out_Of_Memory;
        }
    }

    // Emit the actual ret instruction using the current function's return type
    const ret_type = convert_data.current_ret_type orelse "i32";
    convert_data.generated_code.appendFmt(allocator, "\tret {s} {s}\n", .{ ret_type, final_value })
        catch return ConvertError.Out_Of_Memory;
}
