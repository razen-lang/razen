const std = @import("std");
const token_mod = @import("../lexer/token.zig");
const TokenType = token_mod.TokenType;
const Allocator = std.mem.Allocator;

pub const TypeCategory = enum {
    Integer,
    Float,
    Bool,
    Char,
    Void,
    Noret,
    Str,
    String,
    Any,
    Pointer,
    Optional,
    Failable,
    ErrorUnion,
    Array,
    Struct,
    Enum,
    Union,
    ErrorSet,
    Function,
    Named,
    Unknown,
};

pub const TypeInfo = struct {
    category: TypeCategory,
    name: ?[]const u8 = null,
    pointee_type: ?*TypeInfo = null,
    elem_type: ?*TypeInfo = null,
    error_type: ?*TypeInfo = null,
    ok_type: ?*TypeInfo = null,
    array_size: ?u64 = null,
    param_types: ?*std.ArrayList(*TypeInfo) = null,
    return_type: ?*TypeInfo = null,
    is_mut: bool = false,

    pub fn isNumeric(self: *const TypeInfo) bool {
        return self.category == TypeCategory.Integer or self.category == TypeCategory.Float;
    }

    pub fn isInteger(self: *const TypeInfo) bool {
        return self.category == TypeCategory.Integer;
    }

    pub fn isFloat(self: *const TypeInfo) bool {
        return self.category == TypeCategory.Float;
    }

    pub fn isBool(self: *const TypeInfo) bool {
        return self.category == TypeCategory.Bool;
    }

    pub fn isVoid(self: *const TypeInfo) bool {
        return self.category == TypeCategory.Void;
    }

    pub fn canBeBool(self: *const TypeInfo) bool {
        return self.category == TypeCategory.Bool or self.category == TypeCategory.Integer;
    }

    pub fn format(self: *const TypeInfo, buf: *std.ArrayList(u8)) void {
        switch (self.category) {
            TypeCategory.Integer => {
                if (self.name) |n| buf.appendSlice(n) catch return else buf.appendSlice("int") catch return;
            },
            TypeCategory.Float => {
                if (self.name) |n| buf.appendSlice(n) catch return else buf.appendSlice("float") catch return;
            },
            TypeCategory.Bool => buf.appendSlice("bool") catch return,
            TypeCategory.Char => buf.appendSlice("char") catch return,
            TypeCategory.Void => buf.appendSlice("void") catch return,
            TypeCategory.Noret => buf.appendSlice("noret") catch return,
            TypeCategory.Str => buf.appendSlice("str") catch return,
            TypeCategory.String => buf.appendSlice("string") catch return,
            TypeCategory.Any => buf.appendSlice("any") catch return,
            TypeCategory.Named => {
                if (self.name) |n| buf.appendSlice(n) catch return else buf.appendSlice("unknown") catch return;
            },
            TypeCategory.Pointer => {
                buf.appendSlice("*") catch return;
                if (self.pointee_type) |pt| pt.format(buf);
            },
            TypeCategory.Optional => {
                buf.appendSlice("?") catch return;
                if (self.elem_type) |et| et.format(buf);
            },
            TypeCategory.Failable => {
                buf.appendSlice("!") catch return;
                if (self.elem_type) |et| et.format(buf);
            },
            TypeCategory.ErrorUnion => {
                if (self.error_type) |et| et.format(buf);
                buf.appendSlice("!") catch return;
                if (self.ok_type) |ot| ot.format(buf);
            },
            TypeCategory.Array => {
                buf.appendSlice("[") catch return;
                if (self.elem_type) |et| et.format(buf);
                if (self.array_size) |s| {
                    buf.appendSlice("; ") catch return;
                    var n: [20]u8 = undefined;
                    const ns = std.fmt.bufPrint(&n, "{}", .{s}) catch "";
                    buf.appendSlice(ns) catch return;
                }
                buf.appendSlice("]") catch return;
            },
            TypeCategory.Struct, TypeCategory.Enum, TypeCategory.Union, TypeCategory.ErrorSet => {
                if (self.name) |n| buf.appendSlice(n) catch return;
            },
            TypeCategory.Function => {
                buf.appendSlice("func(") catch return;
                if (self.param_types) |params| {
                    for (params.items, 0..) |pt, i| {
                        if (i > 0) buf.appendSlice(", ") catch return;
                        pt.format(buf);
                    }
                }
                buf.appendSlice(") -> ") catch return;
                if (self.return_type) |rt| rt.format(buf);
            },
            TypeCategory.Unknown => buf.appendSlice("?") catch return,
        }
    }

    pub fn eql(self: *const TypeInfo, other: *const TypeInfo) bool {
        if (self.category != other.category) return false;
        switch (self.category) {
            TypeCategory.Integer, TypeCategory.Float => {
                if (self.name) |sn| {
                    if (other.name) |on| return std.mem.eql(u8, sn, on);
                    return false;
                }
                return other.name == null;
            },
            TypeCategory.Bool, TypeCategory.Char, TypeCategory.Void,
            TypeCategory.Noret, TypeCategory.Str, TypeCategory.String,
            TypeCategory.Any, TypeCategory.Unknown => return true,
            TypeCategory.Named => {
                if (self.name) |sn| {
                    if (other.name) |on| return std.mem.eql(u8, sn, on);
                }
                return false;
            },
            TypeCategory.Struct, TypeCategory.Enum, TypeCategory.Union, TypeCategory.ErrorSet => {
                if (self.name) |sn| {
                    if (other.name) |on| return std.mem.eql(u8, sn, on);
                }
                return false;
            },
            TypeCategory.Pointer => {
                if (self.pointee_type) |sp| {
                    if (other.pointee_type) |op| return sp.eql(op);
                }
                return other.pointee_type == null;
            },
            TypeCategory.Optional => {
                if (self.elem_type) |se| {
                    if (other.elem_type) |oe| return se.eql(oe);
                }
                return other.elem_type == null;
            },
            else => return false,
        }
    }
};

pub fn primitiveFromToken(tt: TokenType, name: []const u8) TypeInfo {
    return switch (tt) {
        TokenType.Bool => TypeInfo{ .category = TypeCategory.Bool },
        TokenType.Char => TypeInfo{ .category = TypeCategory.Char },
        TokenType.Void => TypeInfo{ .category = TypeCategory.Void },
        TokenType.Noret => TypeInfo{ .category = TypeCategory.Noret },
        TokenType.Str => TypeInfo{ .category = TypeCategory.Str },
        TokenType.String => TypeInfo{ .category = TypeCategory.String },
        TokenType.Any => TypeInfo{ .category = TypeCategory.Any },
        else => {
            if (token_utils.isIntegerType(tt)) {
                return TypeInfo{ .category = TypeCategory.Integer, .name = name };
            }
            if (token_utils.isFloatType(tt)) {
                return TypeInfo{ .category = TypeCategory.Float, .name = name };
            }
            return TypeInfo{ .category = TypeCategory.Unknown };
        },
    };
}

pub fn isNumericToken(tt: TokenType) bool {
    return token_utils.isIntegerType(tt) or token_utils.isFloatType(tt);
}

const token_utils = @import("../ast/token_utils.zig");
