const std = @import("std");
const lexer = @import("../lexer/lexer.zig");
const type_info = @import("type_info.zig");

const Token = lexer.Token;
const Allocator = std.mem.Allocator;
const TypeInfo = type_info.TypeInfo;

pub const SymbolType = enum {
    Variable,
    Function,
    Struct,
    Enum,
    Union,
    Trait,
    ErrorSet,
    Module,
    TypeAlias,
};

pub const Symbol = struct {
    name: []const u8,
    symbol_type: SymbolType,
    resolved_type: ?*TypeInfo = null,
    is_mut: bool = false,
    param_count: usize = 0,
    param_types: ?*std.ArrayList(*TypeInfo) = null,
    return_type: ?*TypeInfo = null,
    token: Token,
    is_pub: bool = false,
    fields: ?*std.StringHashMap(*Symbol) = null,
    is_async: bool = false,
    is_const: bool = false,
};

pub const Scope = struct {
    symbols: std.StringHashMap(*Symbol),
    parent: ?*Scope,
    is_loop: bool = false,

    pub fn init(allocator: *Allocator, parent: ?*Scope) Scope {
        return Scope{
            .symbols = std.StringHashMap(*Symbol).init(allocator.*),
            .parent = parent,
        };
    }

    pub fn deinit(self: *Scope) void {
        self.symbols.deinit();
    }

    pub fn define(self: *Scope, symbol: *Symbol) bool {
        if (self.symbols.contains(symbol.name)) return false;
        self.symbols.put(symbol.name, symbol) catch return false;
        return true;
    }

    pub fn resolve(self: *const Scope, name: []const u8) ?*Symbol {
        if (self.symbols.getPtr(name)) |entry| return entry.*;
        if (self.parent) |p| return p.resolve(name);
        return null;
    }

    pub fn resolveLocal(self: *const Scope, name: []const u8) ?*Symbol {
        if (self.symbols.getPtr(name)) |entry| return entry.*;
        return null;
    }

    pub fn isDefinedInCurrentScope(self: *const Scope, name: []const u8) bool {
        return self.symbols.contains(name);
    }

    pub fn inLoop(self: *const Scope) bool {
        if (self.is_loop) return true;
        if (self.parent) |p| return p.inLoop();
        return false;
    }
};

pub const SymbolTable = struct {
    allocator: *Allocator,
    global_scope: *Scope,
    current_scope: *Scope,
    loop_depth: usize = 0,

    pub fn init(allocator: *Allocator) !SymbolTable {
        const global = try allocator.create(Scope);
        global.* = Scope.init(allocator, null);
        return SymbolTable{
            .allocator = allocator,
            .global_scope = global,
            .current_scope = global,
        };
    }

    pub fn deinit(self: *SymbolTable) void {
        self.global_scope.deinit();
    }

    pub fn pushScope(self: *SymbolTable) !void {
        const new_scope = try self.allocator.create(Scope);
        new_scope.* = Scope.init(self.allocator, self.current_scope);
        self.current_scope = new_scope;
    }

    pub fn pushLoopScope(self: *SymbolTable) !void {
        const new_scope = try self.allocator.create(Scope);
        new_scope.* = Scope.init(self.allocator, self.current_scope);
        new_scope.is_loop = true;
        self.current_scope = new_scope;
        self.loop_depth += 1;
    }

    pub fn popScope(self: *SymbolTable) void {
        if (self.current_scope.parent) |parent| {
            if (self.current_scope.is_loop) self.loop_depth -= 1;
            self.current_scope = parent;
        }
    }

    pub fn define(self: *SymbolTable, symbol: *Symbol) bool {
        return self.current_scope.define(symbol);
    }

    pub fn defineGlobal(self: *SymbolTable, symbol: *Symbol) bool {
        return self.global_scope.define(symbol);
    }

    pub fn resolve(self: *const SymbolTable, name: []const u8) ?*Symbol {
        return self.current_scope.resolve(name);
    }

    pub fn resolveGlobal(self: *const SymbolTable, name: []const u8) ?*Symbol {
        return self.global_scope.resolve(name);
    }

    pub fn isInLoop(self: *const SymbolTable) bool {
        return self.loop_depth > 0;
    }
};
