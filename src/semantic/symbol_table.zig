const std = @import("std");
const lexer = @import("../lexer/lexer.zig");

const Token = lexer.Token;
const Allocator = std.mem.Allocator;

pub const SymbolType = enum {
    Variable,
    Function,
    Struct,
    Enum,
    Union,
    Trait,
};

pub const Symbol = struct {
    name: []const u8,
    symbol_type: SymbolType,
    is_mut: bool = false,
    param_count: usize = 0, // For functions
    token: Token, // For error reporting
};

pub const Scope = struct {
    symbols: std.StringHashMap(Symbol),
    parent: ?*Scope,

    pub fn init(allocator: *Allocator, parent: ?*Scope) Scope {
        return Scope{
            .symbols = std.StringHashMap(Symbol).init(allocator.*),
            .parent = parent,
        };
    }

    pub fn deinit(self: *Scope) void {
        self.symbols.deinit();
    }

    pub fn define(self: *Scope, symbol: Symbol) bool {
        if (self.symbols.contains(symbol.name)) {
            return false;
        }
        self.symbols.put(symbol.name, symbol) catch return false;
        return true;
    }

    pub fn resolve(self: *const Scope, name: []const u8) ?Symbol {
        if (self.symbols.get(name)) |sym| {
            return sym;
        }
        if (self.parent) |p| {
            return p.resolve(name);
        }
        return null;
    }
};

pub const SymbolTable = struct {
    allocator: *Allocator,
    global_scope: *Scope,
    current_scope: *Scope,

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
        // Since we are using an ArenaAllocator in main, we don't strictly need to deinit all scopes here,
        // but it's good practice. For now, we rely on the Arena to clean up scopes.
        self.global_scope.deinit();
    }

    pub fn pushScope(self: *SymbolTable) !void {
        const new_scope = try self.allocator.create(Scope);
        new_scope.* = Scope.init(self.allocator, self.current_scope);
        self.current_scope = new_scope;
    }

    pub fn popScope(self: *SymbolTable) void {
        if (self.current_scope.parent) |parent| {
            self.current_scope = parent;
        }
    }

    pub fn define(self: *SymbolTable, symbol: Symbol) bool {
        return self.current_scope.define(symbol);
    }

    pub fn resolve(self: *const SymbolTable, name: []const u8) ?Symbol {
        return self.current_scope.resolve(name);
    }
};
