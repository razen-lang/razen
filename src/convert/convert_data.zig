const std = @import("std");
const node = @import("../ast/node.zig");
const ASTNode = node.ASTNode;
const Token = @import("../lexer/lexer.zig").Token;
const ConvertError = @import("errors.zig").ConvertError;

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

pub const StringBuilder = struct {
    list: ArrayList(u8),

    pub fn init(allocator: Allocator) !StringBuilder {
        return StringBuilder{
            .list = try ArrayList(u8).initCapacity(allocator, 0),
        };
    }

    pub fn append(self: *StringBuilder, allocator: *Allocator, text: []const u8) !void {
        try self.list.appendSlice(allocator.*, text);
    }

    pub fn appendLine(self: *StringBuilder, allocator: *Allocator, text: []const u8) !void {
        try self.list.appendSlice(allocator.*, text);
        try self.list.append(allocator.*, '\n');
    }

    pub fn appendFmt(self: *StringBuilder, allocator: *Allocator, comptime fmt: []const u8, args: anytype) !void {
        const text = try std.fmt.allocPrint(allocator.*, fmt, args);
        try self.list.appendSlice(allocator.*, text);
    }

    pub fn toOwnedSlice(self: *StringBuilder, allocator: *Allocator) ![]u8 {
        return self.list.toOwnedSlice(allocator.*);
    }
};

pub const ConvertData = struct {
    ast_nodes: *ArrayList(*ASTNode),
    generated_code: *StringBuilder,
    node_index: usize = 0,
    tab_count: usize = 0,

    error_detail: ?[]const u8 = null,
    error_token: ?Token = null,
    error_function: ?[]const u8 = null,

    // grabs the next AST node to convert
    pub fn getNode(self: *ConvertData) ?*ASTNode {
        if (self.node_index >= self.ast_nodes.items.len) {
            return null;
        }
        return self.ast_nodes.items[self.node_index];
    }

    // grab with increment
    pub fn getNextNode(self: *ConvertData) ?*ASTNode {
        self.node_index += 1;
        if (self.node_index >= self.ast_nodes.items.len) {
            return null;
        }
        return self.ast_nodes.items[self.node_index];
    }

    pub fn incrementIndexCount(self: *ConvertData) void {
        self.tab_count += 1;
    }

    pub fn decrementIndexCount(self: *ConvertData) void {
        if (self.tab_count > 0) {
            self.tab_count -= 1;
        }
    }

    pub fn addTab(self: *ConvertData, allocator: *Allocator) ConvertError!void {
        for (0..self.tab_count) |_| {
            self.generated_code.append(allocator, "\t") catch return ConvertError.Out_Of_Memory;
        }
    }

    pub fn addNLWithTabs(self: *ConvertData, allocator: *Allocator) ConvertError!void {
        self.generated_code.append(allocator, "\n") catch return ConvertError.Out_Of_Memory;
        self.addTab(allocator) catch return ConvertError.Out_Of_Memory;
    }

    pub fn appendCode(self: *ConvertData, allocator: *Allocator, code: []const u8) ConvertError!void {
        self.generated_code.append(allocator, code) catch return ConvertError.Out_Of_Memory;
    }

    pub fn appendCodeFmt(self: *ConvertData, allocator: *Allocator, comptime fmt: []const u8, args: anytype) ConvertError!void {
        self.generated_code.appendFmt(allocator, fmt, args) catch return ConvertError.Out_Of_Memory;
    }
};
