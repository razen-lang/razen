const std = @import("std");
const node_mod = @import("../ast/node.zig");
const lexer = @import("../lexer/lexer.zig");
const symbol_table = @import("symbol_table.zig");
const semantic_errors = @import("errors.zig");

const ASTNode = node_mod.ASTNode;
const ASTNodeType = node_mod.ASTNodeType;
const SymbolTable = symbol_table.SymbolTable;
const Symbol = symbol_table.Symbol;
const SymbolType = symbol_table.SymbolType;
const SemanticError = semantic_errors.SemanticError;
const Allocator = std.mem.Allocator;
const print = std.debug.print;

pub const Analyzer = struct {
    allocator: *Allocator,
    sym_table: SymbolTable,
    has_errors: bool = false,
    
    pub fn init(allocator: *Allocator) !Analyzer {
        return Analyzer{
            .allocator = allocator,
            .sym_table = try SymbolTable.init(allocator),
        };
    }
    
    pub fn deinit(self: *Analyzer) void {
        self.sym_table.deinit();
    }
    
    fn reportError(self: *Analyzer, token: lexer.Token, comptime msg: []const u8, args: anytype) void {
        self.has_errors = true;
        print("\n{s}Semantic Error:{s} line {}\n  ", .{ lexer.RED, lexer.RESET, token.line });
        print(msg, args);
        print("\n", .{});
    }

    pub fn analyze(self: *Analyzer, ast_nodes: *std.ArrayList(*ASTNode)) !void {
        // Pass 1: Global declarations (Functions, Structs, Enums)
        for (ast_nodes.items) |node| {
            try self.declareGlobal(node);
        }
        
        // Pass 2: Analyze bodies
        for (ast_nodes.items) |node| {
            try self.analyzeNode(node);
        }
    }
    
    fn declareGlobal(self: *Analyzer, node: *ASTNode) !void {
        if (node.token == null) return;
        
        const name = node.token.?.value;
        var sym_type = SymbolType.Variable;
        var param_count: usize = 0;
        
        switch (node.node_type) {
            ASTNodeType.FunctionDeclaration, ASTNodeType.ExtDeclaration => {
                sym_type = SymbolType.Function;
                if (node.middle != null and node.middle.?.children != null) {
                    param_count = node.middle.?.children.?.items.len;
                }
            },
            ASTNodeType.StructDeclaration => sym_type = SymbolType.Struct,
            ASTNodeType.EnumDeclaration => sym_type = SymbolType.Enum,
            ASTNodeType.UnionDeclaration => sym_type = SymbolType.Union,
            ASTNodeType.BehaveDeclaration => sym_type = SymbolType.Trait,
            else => return, // Only tracking globals here
        }
        
        const sym = Symbol{
            .name = name,
            .symbol_type = sym_type,
            .param_count = param_count,
            .token = node.token.?,
        };
        
        if (!self.sym_table.define(sym)) {
            self.reportError(node.token.?, "Global '{s}' is already declared.", .{ name });
        }
    }
    
    fn analyzeNode(self: *Analyzer, node: *ASTNode) !void {
        switch (node.node_type) {
            ASTNodeType.FunctionDeclaration => {
                try self.sym_table.pushScope();
                
                // Add parameters to scope
                if (node.middle != null and node.middle.?.children != null) {
                    for (node.middle.?.children.?.items) |param_node| {
                        if (param_node.token) |tok| {
                            const p_sym = Symbol{
                                .name = tok.value,
                                .symbol_type = SymbolType.Variable,
                                .is_mut = true, // params are passed by value and usually mut
                                .token = tok,
                            };
                            if (!self.sym_table.define(p_sym)) {
                                self.reportError(tok, "Parameter '{s}' is already declared.", .{ tok.value });
                            }
                        }
                    }
                }
                
                // Analyze body
                if (node.right != null) {
                    try self.analyzeNode(node.right.?);
                }
                
                self.sym_table.popScope();
            },
            ASTNodeType.Block, ASTNodeType.IfBody, ASTNodeType.ElseBody, ASTNodeType.LoopBody, ASTNodeType.MatchBody => {
                try self.sym_table.pushScope();
                if (node.children != null) {
                    for (node.children.?.items) |stmt| {
                        try self.analyzeNode(stmt);
                    }
                } else {
                    // some blocks (like ifbody) might just point to a single statement or have children in left/right depending on parser changes
                    if (node.left != null) try self.analyzeNode(node.left.?);
                }
                self.sym_table.popScope();
            },
            ASTNodeType.VarDeclaration, ASTNodeType.ConstDeclaration => {
                // analyze right side first (RHS can't use LHS variable)
                if (node.right != null) {
                    try self.analyzeNode(node.right.?);
                }
                
                if (node.token) |tok| {
                    const is_mut = node.is_mut;
                    const sym = Symbol{
                        .name = tok.value,
                        .symbol_type = SymbolType.Variable,
                        .is_mut = is_mut,
                        .token = tok,
                    };
                    if (!self.sym_table.define(sym)) {
                        self.reportError(tok, "Variable '{s}' is already declared in this scope.", .{ tok.value });
                    }
                }
            },
            ASTNodeType.Assignment => {
                // Check if LHS is valid and mutable
                if (node.left != null and node.left.?.node_type == ASTNodeType.Identifier) {
                    if (node.left.?.token) |tok| {
                        if (self.sym_table.resolve(tok.value)) |sym| {
                            if (!sym.is_mut) {
                                self.reportError(tok, "Cannot reassign to constant '{s}'. Use 'mut' to make it mutable.", .{ tok.value });
                            }
                        } else {
                            self.reportError(tok, "Use of undeclared variable '{s}'.", .{ tok.value });
                        }
                    }
                }
                
                if (node.right != null) {
                    try self.analyzeNode(node.right.?);
                }
            },
            ASTNodeType.Identifier => {
                if (node.token) |tok| {
                    if (self.sym_table.resolve(tok.value) == null) {
                        // For now we skip strict checking on identifiers like 'std' to avoid false positives,
                        // unless it looks like a standard variable. We will just check if it's missing.
                        // Let's implement a whitelist for now or just report it.
                        if (!std.mem.eql(u8, tok.value, "std") and !std.mem.eql(u8, tok.value, "self")) {
                            self.reportError(tok, "Use of undeclared identifier '{s}'.", .{ tok.value });
                        }
                    }
                }
            },
            ASTNodeType.FunctionCall => {
                if (node.token) |tok| {
                    if (self.sym_table.resolve(tok.value)) |sym| {
                        if (sym.symbol_type == SymbolType.Function) {
                            var arg_count: usize = 0;
                            if (node.children != null) {
                                arg_count = node.children.?.items.len;
                            }
                            if (arg_count != sym.param_count) {
                                self.reportError(tok, "Function '{s}' expects {} arguments, but got {}.", .{ tok.value, sym.param_count, arg_count });
                            }
                        }
                    }
                }
                
                // analyze args
                if (node.children != null) {
                    for (node.children.?.items) |arg| {
                        try self.analyzeNode(arg);
                    }
                }
            },
            ASTNodeType.BinaryExpression, ASTNodeType.TryExpression => {
                if (node.left != null) try self.analyzeNode(node.left.?);
                if (node.right != null) try self.analyzeNode(node.right.?);
            },
            ASTNodeType.IfStatement => {
                if (node.left != null) try self.analyzeNode(node.left.?);
                if (node.middle != null) try self.analyzeNode(node.middle.?);
                if (node.right != null) try self.analyzeNode(node.right.?);
            },
            ASTNodeType.LoopStatement => {
                try self.sym_table.pushScope();
                // If it's `loop items |i|`, add `i` to scope
                if (node.middle != null and node.middle.?.node_type == ASTNodeType.Identifier) {
                    if (node.middle.?.token) |tok| {
                        _ = self.sym_table.define(Symbol{
                            .name = tok.value,
                            .symbol_type = SymbolType.Variable,
                            .is_mut = false,
                            .token = tok,
                        });
                    }
                }
                if (node.left != null) try self.analyzeNode(node.left.?);
                if (node.right != null) try self.analyzeNode(node.right.?);
                self.sym_table.popScope();
            },
            ASTNodeType.MatchStatement => {
                if (node.left != null) try self.analyzeNode(node.left.?);
                if (node.children != null) {
                    for (node.children.?.items) |case_node| {
                        if (case_node.left != null) try self.analyzeNode(case_node.left.?);
                        if (case_node.right != null) try self.analyzeNode(case_node.right.?);
                    }
                }
            },
            ASTNodeType.ReturnStatement => {
                if (node.left != null) try self.analyzeNode(node.left.?);
            },
            else => {
                // Ignore types, strings, etc.
            }
        }
    }
};
