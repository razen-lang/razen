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

/// F4 FIX: enum with backing type + explicit values
/// F5 FIX: bit-flag enum values (1 << 0 already handled by printExpression)
/// Design:
///   enum HttpStatus: u16 { Ok = 200, NotFound = 400 }
///   → typedef enum : uint16_t { HttpStatus_Ok = 200, ... } HttpStatus;
///
///   enum Permission: u8 { Read = 1 << 0, Write = 1 << 1 }
///   → typedef enum : uint8_t { Permission_Read = 1 << 0, ... } Permission;
pub fn processEnum(allocator: *Allocator, data: *ConvertData, node: *ASTNode) ConvertError!void {
    data.error_function = "processEnum";

    if (node.token == null) return ConvertError.Node_Is_Null;
    const enum_name = node.token.?.value;

    // F9 FIX: file-private functions get `static` — for enums this just affects
    // forward declarations, but we note it for consistency.
    // Enums are always typedef'd so visibility is implicit.

    // F4: check for backing type on node.left
    // node.left is a VarType node if the parser saw `enum Name: u8 { ... }`
    var backing_type: ?[]const u8 = null;
    if (node.left != null) {
        // left may be a VarType (backing type) or a trait node — only use it if it's VarType
        if (node.left.?.node_type == ASTNodeType.VarType) {
            const bt = c_utils.nodeToCType(allocator, node.left.?) catch null;
            backing_type = bt;
        }
    }

    if (backing_type) |bt| {
        // map Razen type names to C underlying types for enum
        const c_backing = mapBackingType(bt);
        try data.appendCodeFmt(allocator, "typedef enum : {s} {{\n", .{c_backing});
    } else {
        try data.appendCodeFmt(allocator, "typedef enum {{\n", .{});
    }

    if (node.children != null) {
        const items = node.children.?.items;
        for (items, 0..) |member_node, i| {
            if (member_node.node_type != ASTNodeType.EnumField) continue;
            const var_name = member_node.token.?.value;
            try data.appendCodeFmt(allocator, "\t{s}_{s}", .{ enum_name, var_name });

            // F4+F5: explicit value or bit-flag expression
            if (member_node.right != null) {
                const val = try printEnumValue(allocator, data, member_node.right.?);
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

/// Error declarations are enum-style but always plain (no backing type, no bit flags)
pub fn processErrorDecl(allocator: *Allocator, data: *ConvertData, node: *ASTNode) ConvertError!void {
    data.error_function = "processErrorDecl";

    if (node.token == null) return ConvertError.Node_Is_Null;
    const err_name = node.token.?.value;

    // Add RAZEN_OK sentinel as the zero value so error-check `error != RAZEN_OK` works
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

    // F2 FIX: emit the ErrorUnion typedef for this error type so
    // `func read_file() -> FileError!str` has a concrete C type.
    // This emits: typedef struct { FileError error; RazenStr value; } FileError_Result_str;
    // Generic form: typedef struct { <Error> error; <T> value; } <Error>_Result;
    // We emit a generic void* form here; specific forms get emitted at use-sites.
    try data.appendCodeFmt(allocator,
        "typedef struct {{ {s} error; void* value; }} {s}_Result;\n\n",
        .{ err_name, err_name });
}

/// Recursively print an enum value expression (handles literals and bit-shifts)
fn printEnumValue(allocator: *Allocator, data: *ConvertData, node: *ASTNode) ConvertError![]const u8 {
    switch (node.node_type) {
        .IntegerLiteral => return node.token.?.value,
        .BinaryExpression => {
            if (node.token != null and node.left != null and node.right != null) {
                const lhs = try printEnumValue(allocator, data, node.left.?);
                const rhs = try printEnumValue(allocator, data, node.right.?);
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

/// Map Razen type name to C enum underlying type keyword
fn mapBackingType(razen_type: []const u8) []const u8 {
    if (std.mem.eql(u8, razen_type, "i8"))   return "int8_t";
    if (std.mem.eql(u8, razen_type, "u8"))   return "uint8_t";
    if (std.mem.eql(u8, razen_type, "i16"))  return "int16_t";
    if (std.mem.eql(u8, razen_type, "u16"))  return "uint16_t";
    if (std.mem.eql(u8, razen_type, "i32") or std.mem.eql(u8, razen_type, "int")) return "int32_t";
    if (std.mem.eql(u8, razen_type, "u32") or std.mem.eql(u8, razen_type, "uint")) return "uint32_t";
    if (std.mem.eql(u8, razen_type, "i64"))  return "int64_t";
    if (std.mem.eql(u8, razen_type, "u64"))  return "uint64_t";
    return "int"; // default
}
