const std = @import("std");
const node_mod = @import("../../ast/node.zig");
const convert_data = @import("../convert_data.zig");
const errors = @import("../errors.zig");
const c_utils = @import("c_utils.zig");

const ASTNode = node_mod.ASTNode;
const ASTNodeType = node_mod.ASTNodeType;
const ConvertData = convert_data.ConvertData;
const ConvertError = errors.ConvertError;
const Allocator = std.mem.Allocator;

// Emit a Razen enum as a C typedef enum.
// Supports: optional backing type (e.g. `enum Status: u16`),
// explicit discriminant values, and bit-flag expressions (e.g. `1 << 0`).
pub fn processEnum(allocator: *Allocator, data: *ConvertData, node: *ASTNode) ConvertError!void {
    data.error_function = "processEnum";
    if (node.token == null) return ConvertError.Node_Is_Null;
    const enum_name = node.token.?.value;

    // backing type lives on node.left when the parser saw `enum Name: u8 { ... }`
    var backing_type: ?[]const u8 = null;
    if (node.left != null and node.left.?.node_type == ASTNodeType.VarType) {
        const bt = c_utils.nodeToCType(allocator, node.left.?) catch null;
        backing_type = bt;
    }

    if (backing_type) |bt| {
        try data.appendCodeFmt(allocator, "typedef enum : {s} {{\n", .{mapBackingType(bt)});
    } else {
        try data.appendCodeFmt(allocator, "typedef enum {{\n", .{});
    }

    if (node.children != null) {
        const items = node.children.?.items;
        for (items, 0..) |member_node, i| {
            if (member_node.node_type != ASTNodeType.EnumField) continue;
            const var_name = member_node.token.?.value;
            try data.appendCodeFmt(allocator, "\t{s}_{s}", .{ enum_name, var_name });
            if (member_node.right != null) {
                const val = try printEnumValue(allocator, member_node.right.?);
                try data.appendCodeFmt(allocator, " = {s}", .{val});
            }
            if (i < items.len - 1) {
                try data.appendCode(allocator, ",\n");
            } else {
                try data.appendCode(allocator, "\n");
            }
        }
    }

    try data.appendCodeFmt(allocator, "}} {s};\n\n", .{enum_name});
}

// Emit a Razen error set as a C typedef enum.
// Adds an `_Ok = 0` sentinel so that `error != RAZEN_OK` checks work correctly
// in the try/catch expansion.
// Also emits a `<Name>_Result` struct for use as an error-union return type.
pub fn processErrorDecl(allocator: *Allocator, data: *ConvertData, node: *ASTNode) ConvertError!void {
    data.error_function = "processErrorDecl";
    if (node.token == null) return ConvertError.Node_Is_Null;
    const err_name = node.token.?.value;

    try data.appendCodeFmt(allocator, "typedef enum {{\n", .{});
    try data.appendCodeFmt(allocator, "\t{s}_Ok = 0,\n", .{err_name});

    if (node.children != null) {
        const items = node.children.?.items;
        for (items, 0..) |member_node, i| {
            if (member_node.node_type != ASTNodeType.ErrorField) continue;
            const var_name = member_node.token.?.value;
            try data.appendCodeFmt(allocator, "\t{s}_{s}", .{ err_name, var_name });
            if (i < items.len - 1) {
                try data.appendCode(allocator, ",\n");
            } else {
                try data.appendCode(allocator, "\n");
            }
        }
    }

    try data.appendCodeFmt(allocator, "}} {s};\n\n", .{err_name});

    // emit a generic result struct so `FileError!str` has a concrete C type
    try data.appendCodeFmt(
        allocator,
        "typedef struct {{ {s} error; void* value; }} {s}_Result;\n\n",
        .{ err_name, err_name },
    );
}

// Recursively print an enum field value — handles integer literals and
// binary expressions like `1 << 2` used in bit-flag enums.
fn printEnumValue(allocator: *Allocator, node: *ASTNode) ConvertError![]const u8 {
    switch (node.node_type) {
        .IntegerLiteral => return node.token.?.value,
        .BinaryExpression => {
            if (node.token != null and node.left != null and node.right != null) {
                const lhs = try printEnumValue(allocator, node.left.?);
                const rhs = try printEnumValue(allocator, node.right.?);
                return std.fmt.allocPrint(allocator.*, "{s} {s} {s}", .{ lhs, node.token.?.value, rhs }) catch return ConvertError.Out_Of_Memory;
            }
            return "0";
        },
        else => {
            if (node.token != null) return node.token.?.value;
            return "0";
        },
    }
}

// Map a Razen type name to the C keyword used inside `enum : <type>`.
fn mapBackingType(razen_type: []const u8) []const u8 {
    if (std.mem.eql(u8, razen_type, "i8")) return "int8_t";
    if (std.mem.eql(u8, razen_type, "u8")) return "uint8_t";
    if (std.mem.eql(u8, razen_type, "i16")) return "int16_t";
    if (std.mem.eql(u8, razen_type, "u16")) return "uint16_t";
    if (std.mem.eql(u8, razen_type, "i32") or std.mem.eql(u8, razen_type, "int")) return "int32_t";
    if (std.mem.eql(u8, razen_type, "u32") or std.mem.eql(u8, razen_type, "uint")) return "uint32_t";
    if (std.mem.eql(u8, razen_type, "i64")) return "int64_t";
    if (std.mem.eql(u8, razen_type, "u64")) return "uint64_t";
    return "int";
}
