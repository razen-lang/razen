const std = @import("std");
const node = @import("../ast/node.zig");
const ASTNode = node.ASTNode;
const Token = @import("../lexer/lexer.zig").Token;
const ConvertError = @import("errors.zig").ConvertError;

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

// A simple growable byte buffer used to accumulate the generated C source.
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

// State threaded through the entire code generation pass.
// One ConvertData lives per convert() call; all emitters share it.
pub const ConvertData = struct {
    ast_nodes: *ArrayList(*ASTNode),
    generated_code: *StringBuilder,
    node_index: usize = 0,
    tab_count: usize = 0,

    // set by emitters when they hit an error, for better diagnostics
    error_detail: ?[]const u8 = null,
    error_token: ?Token = null,
    error_function: ?[]const u8 = null,

    last_statement_was_return: bool = false,

    // variable name -> C type, built up as declarations are emitted.
    // used for type inference when a variable has no explicit annotation.
    var_types: std.StringHashMap([]const u8),

    // deferred statement body blocks, collected during a function body walk.
    // flushed in LIFO order before every return and at the end of the function.
    deferred_stmts: std.ArrayList(*ASTNode),

    // monotonic counter for generating unique temporary variable names (_tmp0, _tmp1, ...)
    tmp_counter: usize = 0,

    // set to the current struct/behave name while emitting its body,
    // so that @Self in method signatures resolves to the right C type name.
    current_struct_name: ?[]const u8 = null,

    // union name -> (variant name -> C type).
    // populated as unions are emitted; used for tagged-union match and construction.
    union_registry: std.StringHashMap(std.StringHashMap([]const u8)),

    pub fn getNode(self: *ConvertData) ?*ASTNode {
        if (self.node_index >= self.ast_nodes.items.len) return null;
        return self.ast_nodes.items[self.node_index];
    }

    pub fn getNextNode(self: *ConvertData) ?*ASTNode {
        self.node_index += 1;
        if (self.node_index >= self.ast_nodes.items.len) return null;
        return self.ast_nodes.items[self.node_index];
    }

    pub fn incrementIndexCount(self: *ConvertData) void {
        self.tab_count += 1;
    }

    pub fn decrementIndexCount(self: *ConvertData) void {
        if (self.tab_count > 0) self.tab_count -= 1;
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

    pub fn lookupVarType(self: *ConvertData, name: []const u8) ?[]const u8 {
        return self.var_types.get(name);
    }

    // generate a fresh name like _tmp0, _tmp1, ... for try/catch expansion temps
    pub fn freshTmpName(self: *ConvertData, allocator: *Allocator) ConvertError![]u8 {
        const name = std.fmt.allocPrint(allocator.*, "_tmp{d}", .{self.tmp_counter}) catch return ConvertError.Out_Of_Memory;
        self.tmp_counter += 1;
        return name;
    }
};
