const std = @import("std");
const node_mod = @import("../ast/node.zig");
const lexer = @import("../lexer/lexer.zig");
const tok_utils = @import("../ast/token_utils.zig");
const token_mod = @import("../lexer/token.zig");
const symbol_table = @import("symbol_table.zig");
const semantic_errors = @import("errors.zig");
const type_info = @import("type_info.zig");

const ASTNode = node_mod.ASTNode;
const ASTNodeType = node_mod.ASTNodeType;
const TokenType = token_mod.TokenType;
const SymbolTable = symbol_table.SymbolTable;
const Symbol = symbol_table.Symbol;
const SymbolType = symbol_table.SymbolType;
const SemanticError = semantic_errors.SemanticError;
const Allocator = std.mem.Allocator;
const TypeInfo = type_info.TypeInfo;
const TypeCategory = type_info.TypeCategory;
const print = std.debug.print;

pub const Analyzer = struct {
    allocator: *Allocator,
    sym_table: SymbolTable,
    has_errors: bool = false,
    current_return_type: ?*TypeInfo = null,
    current_func_name: ?[]const u8 = null,
    undeclared_whitelist: std.StringHashMap(void),

    pub fn init(allocator: *Allocator) !Analyzer {
        var self = Analyzer{
            .allocator = allocator,
            .sym_table = try SymbolTable.init(allocator),
            .undeclared_whitelist = std.StringHashMap(void).init(allocator.*),
        };
        try self.undeclared_whitelist.put("std", {});
        try self.undeclared_whitelist.put("self", {});
        try self.undeclared_whitelist.put("true", {});
        try self.undeclared_whitelist.put("false", {});
        try self.undeclared_whitelist.put("print", {});
        try self.undeclared_whitelist.put("println", {});
        try self.undeclared_whitelist.put("eprint", {});
        try self.undeclared_whitelist.put("eprintln", {});
        try self.undeclared_whitelist.put("exit", {});
        try self.undeclared_whitelist.put("assert", {});
        try self.undeclared_whitelist.put("panic", {});
        try self.undeclared_whitelist.put("clock_ms", {});
        try self.undeclared_whitelist.put("clock_ns", {});
        return self;
    }

    pub fn deinit(self: *Analyzer) void {
        self.sym_table.deinit();
        self.undeclared_whitelist.deinit();
    }

    fn reportError(self: *Analyzer, token: lexer.Token, comptime msg: []const u8, args: anytype) void {
        self.has_errors = true;
        print("{s}Semantic Error{s} at line {}: ", .{ lexer.RED, lexer.RESET, token.line + 1 });
        print(msg, args);
        print("\n", .{});
    }

    pub fn analyze(self: *Analyzer, ast_nodes: *std.ArrayList(*ASTNode)) SemanticError!void {
        for (ast_nodes.items) |node| {
            try self.declareGlobal(node);
        }
        for (ast_nodes.items) |node| {
            _ = try self.analyzeNode(node);
        }
    }

    fn resolveTypeFromNode(self: *Analyzer, type_node: *ASTNode) ?*TypeInfo {
        if (type_node.node_type != ASTNodeType.VarType) return null;
        const tok = type_node.token orelse return null;
        const tt = tok.token_type;
        const name = tok.value;

        if (type_info.isNumericToken(tt)) {
            const ti = self.allocator.create(TypeInfo) catch return null;
            ti.* = type_info.primitiveFromToken(tt, name);
            return ti;
        }

        switch (tt) {
            TokenType.Bool => return allocType(self, .Bool),
            TokenType.Char => return allocType(self, .Char),
            TokenType.Void => return allocType(self, .Void),
            TokenType.Noret => return allocType(self, .Noret),
            TokenType.Str => return allocType(self, .Str),
            TokenType.String => return allocType(self, .String),
            TokenType.Any => return allocType(self, .Any),
            TokenType.Identifier => {
                if (self.sym_table.resolveGlobal(name)) |sym| {
                    if (sym.resolved_type) |rt| return rt;
                    if (sym.symbol_type == SymbolType.Struct) return namedType(self, name, .Struct);
                    if (sym.symbol_type == SymbolType.Enum) return namedType(self, name, .Enum);
                    if (sym.symbol_type == SymbolType.Union) return namedType(self, name, .Union);
                    if (sym.symbol_type == SymbolType.ErrorSet) return namedType(self, name, .ErrorSet);
                }
                return namedType(self, name, .Named);
            },
            TokenType.Star => {
                const ti = allocType(self, .Pointer);
                if (type_node.left) |inner| ti.pointee_type = self.resolveTypeFromNode(inner);
                return ti;
            },
            TokenType.QuestionMark => {
                const ti = allocType(self, .Optional);
                if (type_node.left) |inner| ti.elem_type = self.resolveTypeFromNode(inner);
                return ti;
            },
            TokenType.ExclamationMark => {
                const ti = allocType(self, .Failable);
                if (type_node.left) |inner| ti.elem_type = self.resolveTypeFromNode(inner);
                return ti;
            },
            TokenType.Error => {
                const ti = allocType(self, .ErrorUnion);
                if (type_node.left) |inner| ti.ok_type = self.resolveTypeFromNode(inner);
                return ti;
            },
            else => {
                if (type_node.left) |inner| return self.resolveTypeFromNode(inner);
                return null;
            },
        }
    }

    fn inferTypeFromLiteral(self: *Analyzer, node: *ASTNode) ?*TypeInfo {
        switch (node.node_type) {
            ASTNodeType.IntegerLiteral => {
                const ti = self.allocType(.Integer);
                ti.name = "i32";
                return ti;
            },
            ASTNodeType.FloatLiteral => {
                const ti = self.allocType(.Float);
                ti.name = "f64";
                return ti;
            },
            ASTNodeType.BoolLiteral => return self.allocType(.Bool),
            ASTNodeType.CharLiteral => return self.allocType(.Char),
            ASTNodeType.StringLiteral => return self.allocType(.Str),
            else => return null,
        }
    }

    fn allocType(self: *Analyzer, cat: TypeCategory) *TypeInfo {
        const ti = self.allocator.create(TypeInfo) catch unreachable;
        ti.* = TypeInfo{ .category = cat };
        return ti;
    }

    fn namedType(self: *Analyzer, name: []const u8, cat: TypeCategory) *TypeInfo {
        const ti = self.allocator.create(TypeInfo) catch unreachable;
        ti.* = TypeInfo{ .category = cat, .name = name };
        return ti;
    }

    fn declareGlobal(self: *Analyzer, node: *ASTNode) SemanticError!void {
        const tok = node.token orelse return;
        const name = tok.value;

        switch (node.node_type) {
            ASTNodeType.FunctionDeclaration, ASTNodeType.ExtDeclaration => {
                const sym = try self.allocator.create(Symbol);
                sym.* = Symbol{
                    .name = name,
                    .symbol_type = SymbolType.Function,
                    .token = tok,
                    .is_pub = node.is_pub,
                    .is_async = node.is_async,
                    .is_const = node.is_const,
                };
                if (node.middle) |params_node| {
                    if (params_node.children) |params| sym.param_count = params.items.len;
                }
                if (node.left) |ret_type_node| {
                    if (ret_type_node.node_type == ASTNodeType.ReturnType and ret_type_node.left != null) {
                        sym.return_type = self.resolveTypeFromNode(ret_type_node.left.?);
                    }
                }
                if (!self.sym_table.defineGlobal(sym)) {
                    self.reportError(tok, "'{s}' is already declared in this scope.", .{name});
                }
            },
            ASTNodeType.StructDeclaration => {
                const sym = try self.allocator.create(Symbol);
                sym.* = Symbol{
                    .name = name,
                    .symbol_type = SymbolType.Struct,
                    .token = tok,
                    .is_pub = node.is_pub,
                };
                const fields = try self.allocator.create(std.StringHashMap(*Symbol));
                fields.* = std.StringHashMap(*Symbol).init(self.allocator.*);
                sym.fields = fields;

                if (node.children) |children| {
                    for (children.items) |child| {
                        if (child.node_type == ASTNodeType.StructField) {
                            const ftok = child.token orelse continue;
                            const fsym = try self.allocator.create(Symbol);
                            fsym.* = Symbol{
                                .name = ftok.value,
                                .symbol_type = SymbolType.Variable,
                                .token = ftok,
                            };
                            if (child.left) |ftype| fsym.resolved_type = self.resolveTypeFromNode(ftype);
                            fields.put(ftok.value, fsym) catch {};
                        }
                    }
                }
                if (!self.sym_table.defineGlobal(sym)) {
                    self.reportError(tok, "Struct '{s}' is already declared.", .{name});
                }
            },
            ASTNodeType.EnumDeclaration => {
                const sym = try self.allocator.create(Symbol);
                sym.* = Symbol{
                    .name = name,
                    .symbol_type = SymbolType.Enum,
                    .token = tok,
                    .is_pub = node.is_pub,
                };
                const variants = try self.allocator.create(std.StringHashMap(*Symbol));
                variants.* = std.StringHashMap(*Symbol).init(self.allocator.*);
                sym.fields = variants;
                if (node.children) |children| {
                    for (children.items) |child| {
                        if (child.node_type == ASTNodeType.EnumField) {
                            const ftok = child.token orelse continue;
                            const vsym = try self.allocator.create(Symbol);
                            vsym.* = Symbol{
                                .name = ftok.value,
                                .symbol_type = SymbolType.Variable,
                                .token = ftok,
                            };
                            variants.put(ftok.value, vsym) catch {};
                        }
                    }
                }
                if (!self.sym_table.defineGlobal(sym)) {
                    self.reportError(tok, "Enum '{s}' is already declared.", .{name});
                }
            },
            ASTNodeType.UnionDeclaration => {
                const sym = try self.allocator.create(Symbol);
                sym.* = Symbol{ .name = name, .symbol_type = SymbolType.Union, .token = tok, .is_pub = node.is_pub };
                if (!self.sym_table.defineGlobal(sym)) {
                    self.reportError(tok, "Union '{s}' is already declared.", .{name});
                }
            },
            ASTNodeType.ErrorDeclaration => {
                const sym = try self.allocator.create(Symbol);
                sym.* = Symbol{ .name = name, .symbol_type = SymbolType.ErrorSet, .token = tok };
                if (!self.sym_table.defineGlobal(sym)) {
                    self.reportError(tok, "Error set '{s}' is already declared.", .{name});
                }
            },
            ASTNodeType.BehaveDeclaration => {
                const sym = try self.allocator.create(Symbol);
                sym.* = Symbol{ .name = name, .symbol_type = SymbolType.Trait, .token = tok };
                if (!self.sym_table.defineGlobal(sym)) {
                    self.reportError(tok, "Behaviour '{s}' is already declared.", .{name});
                }
            },
            ASTNodeType.TypeAliasDeclaration => {
                const sym = try self.allocator.create(Symbol);
                sym.* = Symbol{ .name = name, .symbol_type = SymbolType.TypeAlias, .token = tok };
                if (node.left) |alias_type| sym.resolved_type = self.resolveTypeFromNode(alias_type);
                if (!self.sym_table.defineGlobal(sym)) {
                    self.reportError(tok, "Type alias '{s}' is already declared.", .{name});
                }
            },
            ASTNodeType.ModuleDeclaration, ASTNodeType.UseDeclaration => {
                const sym = try self.allocator.create(Symbol);
                sym.* = Symbol{ .name = name, .symbol_type = SymbolType.Module, .token = tok };
                _ = self.sym_table.defineGlobal(sym);
            },
            ASTNodeType.ConstDeclaration => {
                const sym = try self.allocator.create(Symbol);
                sym.* = Symbol{
                    .name = name,
                    .symbol_type = SymbolType.Variable,
                    .token = tok,
                    .is_mut = node.is_mut,
                    .is_const = true,
                };
                if (node.left) |type_node| sym.resolved_type = self.resolveTypeFromNode(type_node);
                if (!self.sym_table.defineGlobal(sym)) {
                    self.reportError(tok, "Constant '{s}' is already declared.", .{name});
                }
            },
            else => {},
        }
    }

    fn analyzeNode(self: *Analyzer, node: *ASTNode) SemanticError!?*TypeInfo {
        return self.anaNode(node);
    }

    fn anaNode(self: *Analyzer, node: *ASTNode) SemanticError!?*TypeInfo {
        switch (node.node_type) {
            ASTNodeType.Invalid, ASTNodeType.Comment => return null,
            ASTNodeType.FunctionDeclaration => return try self.anaFuncDecl(node),
            ASTNodeType.ExtDeclaration => return null,
            ASTNodeType.Block => return try self.anaBlock(node),
            ASTNodeType.IfBody, ASTNodeType.ElseBody, ASTNodeType.LoopBody, ASTNodeType.MatchBody => return try self.anaBody(node),
            ASTNodeType.MatchCase => {
                if (node.right) |r| return try self.anaNode(r);
                return null;
            },
            ASTNodeType.VarDeclaration, ASTNodeType.ConstDeclaration => return try self.anaVarDecl(node),
            ASTNodeType.Assignment => return try self.anaAssignment(node),
            ASTNodeType.ReturnStatement => {
                const tok = node.token orelse return null;
                if (std.mem.eql(u8, tok.value, "break")) {
                    if (!self.sym_table.isInLoop()) {
                        self.reportError(tok, "'break' outside of a loop is not allowed.", .{});
                    }
                    return null;
                }
                if (std.mem.eql(u8, tok.value, "skip")) {
                    if (!self.sym_table.isInLoop()) {
                        self.reportError(tok, "'skip' outside of a loop is not allowed.", .{});
                    }
                    return null;
                }
                return try self.anaReturn(node);
            },
            ASTNodeType.IfStatement => return try self.anaIf(node),
            ASTNodeType.LoopStatement => return try self.anaLoop(node),
            ASTNodeType.MatchStatement => return try self.anaMatch(node),
            ASTNodeType.DeferStatement => {
                if (node.left) |stmt| _ = try self.anaNode(stmt);
                return null;
            },
            ASTNodeType.TryExpression => {
                if (node.left) |expr| _ = try self.anaNode(expr);
                if (node.right) |catch_node| {
                    if (catch_node.node_type == ASTNodeType.CatchExpression) {
                        if (catch_node.left) |catch_body| _ = try self.anaNode(catch_body);
                    }
                }
                return null;
            },

            ASTNodeType.BinaryExpression => return try self.anaBinary(node),
            ASTNodeType.UnaryExpression => return try self.anaUnary(node),
            ASTNodeType.MemberAccess => return try self.anaMemberAccess(node),
            ASTNodeType.Identifier => return self.anaIdentifier(node),
            ASTNodeType.FunctionCall => return try self.anaFunctionCall(node),
            ASTNodeType.CatchExpression => {
                if (node.left) |l| return try self.anaNode(l);
                return null;
            },
            ASTNodeType.IntegerLiteral, ASTNodeType.FloatLiteral, ASTNodeType.BoolLiteral, ASTNodeType.CharLiteral, ASTNodeType.StringLiteral => return self.inferTypeFromLiteral(node),
            ASTNodeType.BuiltinExpression => return null,
            ASTNodeType.ArrayLiteral => {
                if (node.children) |children| {
                    for (children.items) |elem| _ = try self.anaNode(elem);
                }
                return null;
            },
            else => return null,
        }
    }

    fn anaFuncDecl(self: *Analyzer, node: *ASTNode) SemanticError!?*TypeInfo {
        const tok = node.token orelse return null;
        const name = tok.value;

        var ret_type: ?*TypeInfo = null;
        if (node.left) |ret_type_node| {
            if (ret_type_node.node_type == ASTNodeType.ReturnType and ret_type_node.left != null) {
                ret_type = self.resolveTypeFromNode(ret_type_node.left.?);
            }
        }

        self.current_return_type = ret_type;
        self.current_func_name = name;

        try self.sym_table.pushScope();

        if (node.middle) |params_node| {
            if (params_node.children) |params| {
                for (params.items) |param| {
                    if (param.node_type == ASTNodeType.Parameter) {
                        const ptok = param.token orelse continue;
                        const psym = try self.allocator.create(Symbol);
                        psym.* = Symbol{
                            .name = ptok.value,
                            .symbol_type = SymbolType.Variable,
                            .token = ptok,
                            .is_mut = param.is_mut,
                        };
                        if (param.left) |ptype| psym.resolved_type = self.resolveTypeFromNode(ptype);
                        if (!self.sym_table.define(psym)) {
                            self.reportError(ptok, "Parameter '{s}' is already declared.", .{ptok.value});
                        }
                    }
                }
            }
        }

        var has_explicit_return = false;
        if (node.right) |body| {
            if (body.node_type == ASTNodeType.Block) {
                const body_type = try self.anaBlock(body);
                if (body_type != null) has_explicit_return = true;
            }
        }

        if (ret_type != null and !has_explicit_return) {
            if (ret_type.?.category != TypeCategory.Void and ret_type.?.category != TypeCategory.Noret) {
                self.reportError(tok, "Function '{s}' expects return type but may not return a value.", .{name});
            }
        }

        self.sym_table.popScope();
        self.current_return_type = null;
        self.current_func_name = null;
        return ret_type;
    }

    fn anaBlock(self: *Analyzer, node: *ASTNode) SemanticError!?*TypeInfo {
        try self.sym_table.pushScope();
        var last_type: ?*TypeInfo = null;
        if (node.children) |children| {
            for (children.items) |stmt| last_type = try self.anaNode(stmt);
        } else if (node.left) |left| {
            last_type = try self.anaNode(left);
        }
        self.sym_table.popScope();
        return last_type;
    }

    fn anaBody(self: *Analyzer, node: *ASTNode) SemanticError!?*TypeInfo {
        try self.sym_table.pushScope();
        var last_type: ?*TypeInfo = null;
        if (node.children) |children| {
            for (children.items) |stmt| last_type = try self.anaNode(stmt);
        } else if (node.left) |left| {
            if (left.node_type == ASTNodeType.Block) {
                last_type = try self.anaBlock(left);
            } else {
                last_type = try self.anaNode(left);
            }
        }
        self.sym_table.popScope();
        return last_type;
    }

    fn anaVarDecl(self: *Analyzer, node: *ASTNode) SemanticError!?*TypeInfo {
        const tok = node.token orelse return null;
        const name = tok.value;

        var decl_type: ?*TypeInfo = null;
        if (node.left) |type_node| decl_type = self.resolveTypeFromNode(type_node);

        if (node.right) |init_expr| {
            const init_type = try self.anaNode(init_expr);
            if (decl_type != null and init_type != null) {
                if (!self.typesCompatible(decl_type.?, init_type.?)) {
                    self.reportError(tok, "Type mismatch initializing variable '{s}'.", .{name});
                }
            }
        }

        const is_global = self.sym_table.current_scope == self.sym_table.global_scope;
        if (self.sym_table.current_scope.isDefinedInCurrentScope(name)) {
            if (!is_global) {
                self.reportError(tok, "Variable '{s}' is already declared in this scope.", .{name});
            }
        } else {
            const sym = try self.allocator.create(Symbol);
            sym.* = Symbol{
                .name = name,
                .symbol_type = SymbolType.Variable,
                .resolved_type = decl_type,
                .token = tok,
                .is_mut = node.is_mut,
                .is_const = node.is_const,
            };
            _ = self.sym_table.define(sym);
        }
        return decl_type;
    }

    fn anaAssignment(self: *Analyzer, node: *ASTNode) SemanticError!?*TypeInfo {
        if (node.left) |lhs| {
            if (lhs.node_type == ASTNodeType.Identifier) {
                const ltok = lhs.token orelse return null;
                if (self.sym_table.resolve(ltok.value)) |sym| {
                    if (!sym.is_mut and !sym.is_const) {
                        self.reportError(ltok, "Cannot assign to immutable variable '{s}'. Use 'mut' to make it mutable.", .{ltok.value});
                    }
                    if (node.right) |rhs| {
                        const rhs_type = try self.anaNode(rhs);
                        if (sym.resolved_type != null and rhs_type != null) {
                            if (!self.typesCompatible(sym.resolved_type.?, rhs_type.?)) {
                                self.reportError(ltok, "Type mismatch in assignment to '{s}'.", .{ltok.value});
                            }
                        }
                    }
                } else if (!self.undeclared_whitelist.contains(ltok.value)) {
                    self.reportError(ltok, "Use of undeclared identifier '{s}'.", .{ltok.value});
                }
            } else if (lhs.node_type == ASTNodeType.MemberAccess) {
                _ = try self.anaMemberAccess(lhs);
            } else if (lhs.node_type == ASTNodeType.UnaryExpression) {
                const tok = lhs.token orelse return null;
                if (!std.mem.eql(u8, tok.value, ".*")) {
                    self.reportError(tok, "Invalid left-hand side of assignment.", .{});
                }
            }
            if (node.right) |rhs| return try self.anaNode(rhs);
        }
        return null;
    }

    fn anaReturn(self: *Analyzer, node: *ASTNode) SemanticError!?*TypeInfo {
        var ret_type: ?*TypeInfo = null;
        if (node.left) |ret_expr| {
            ret_type = try self.anaNode(ret_expr);
        } else {
            const ti = self.allocator.create(TypeInfo) catch return null;
            ti.* = TypeInfo{ .category = TypeCategory.Void };
            ret_type = ti;
        }

        if (self.current_return_type) |expected| {
            if (ret_type) |actual| {
                if (!self.typesCompatible(expected, actual)) {
                    const tok = node.token orelse return null;
                    self.reportError(tok, "Function returns a different type than declared.", .{});
                }
            }
        }
        return ret_type;
    }

    fn anaIf(self: *Analyzer, node: *ASTNode) SemanticError!?*TypeInfo {
        if (node.left) |cond| {
            const cond_type = try self.anaNode(cond);
            if (cond_type) |ct| {
                if (!ct.isBool()) {
                    const tok = cond.token orelse return null;
                    self.reportError(tok, "'if' condition must be a boolean.", .{});
                }
            }
        }
        if (node.middle) |if_body| _ = try self.anaBody(if_body);
        if (node.right) |else_body| _ = try self.anaBody(else_body);
        return null;
    }

    fn anaLoop(self: *Analyzer, node: *ASTNode) SemanticError!?*TypeInfo {
        if (node.left) |cond| {
            const cond_type = try self.anaNode(cond);
            if (cond_type) |ct| {
                if (!ct.isBool()) {
                    const tok = cond.token orelse return null;
                    self.reportError(tok, "'loop' condition must be a boolean.", .{});
                }
            }
        }
        try self.sym_table.pushLoopScope();
        if (node.middle) |item_node| {
            if (item_node.node_type == ASTNodeType.Identifier) {
                if (item_node.token) |itok| {
                    const isym = try self.allocator.create(Symbol);
                    isym.* = Symbol{ .name = itok.value, .symbol_type = SymbolType.Variable, .token = itok };
                    _ = self.sym_table.define(isym);
                }
            }
        }
        if (node.right) |body| {
            if (body.node_type == ASTNodeType.LoopBody) {
                if (body.children) |children| {
                    for (children.items) |stmt| _ = try self.anaNode(stmt);
                }
            }
        }
        self.sym_table.popScope();
        return null;
    }

    fn anaMatch(self: *Analyzer, node: *ASTNode) SemanticError!?*TypeInfo {
        if (node.left) |match_expr| _ = try self.anaNode(match_expr);
        if (node.children) |cases| {
            for (cases.items) |case_node| {
                if (case_node.left) |pat| _ = try self.anaNode(pat);
                if (case_node.right) |body| {
                    if (body.node_type == ASTNodeType.MatchBody) {
                        try self.sym_table.pushScope();
                        if (body.left) |b| _ = try self.anaNode(b);
                        self.sym_table.popScope();
                    }
                }
            }
        }
        return null;
    }

    fn anaBinary(self: *Analyzer, node: *ASTNode) SemanticError!?*TypeInfo {
        const tok = node.token orelse return null;
        const op_type = tok.token_type;
        const left_type = if (node.left) |l| try self.anaNode(l) else null;
        const right_type = if (node.right) |r| try self.anaNode(r) else null;
        if (left_type == null or right_type == null) return null;
        const lt = left_type.?;
        const rt = right_type.?;

        switch (op_type) {
            TokenType.Plus, TokenType.Minus, TokenType.Star, TokenType.Slash, TokenType.Percent => {
                if (!lt.isNumeric() or !rt.isNumeric()) {
                    self.reportError(tok, "Arithmetic operator requires numeric operands.", .{});
                    return null;
                }
                return lt;
            },
            TokenType.EqualsEquals, TokenType.NotEquals => {
                if (!self.typesCompatible(lt, rt)) {
                    self.reportError(tok, "Cannot compare values of different types.", .{});
                    return null;
                }
                return self.allocType(.Bool);
            },
            TokenType.LessThan, TokenType.LessThanEquals, TokenType.GreaterThan, TokenType.GreaterThanEquals => {
                if (!lt.isNumeric() or !rt.isNumeric()) {
                    self.reportError(tok, "Comparison operator requires numeric operands.", .{});
                    return null;
                }
                return self.allocType(.Bool);
            },
            TokenType.AndAnd, TokenType.OrOr => {
                if (!lt.isBool() or !rt.isBool()) {
                    self.reportError(tok, "Logical operator requires boolean operands.", .{});
                    return null;
                }
                return lt;
            },
            TokenType.And, TokenType.Or, TokenType.Caret, TokenType.ShiftLeft, TokenType.ShiftRight => {
                if (!lt.isInteger() or !rt.isInteger()) {
                    self.reportError(tok, "Bitwise operator requires integer operands.", .{});
                    return null;
                }
                return lt;
            },
            else => return lt,
        }
    }

    fn anaUnary(self: *Analyzer, node: *ASTNode) SemanticError!?*TypeInfo {
        const tok = node.token orelse return null;
        const inner_type = if (node.left) |l| try self.anaNode(l) else null;
        if (inner_type == null) return null;

        if (std.mem.eql(u8, tok.value, "-")) {
            if (!inner_type.?.isNumeric()) {
                self.reportError(tok, "Unary minus requires numeric operand.", .{});
                return null;
            }
            return inner_type;
        }
        if (std.mem.eql(u8, tok.value, "!")) {
            if (!inner_type.?.canBeBool()) {
                self.reportError(tok, "Logical not requires boolean operand.", .{});
                return null;
            }
            return inner_type;
        }
        if (std.mem.eql(u8, tok.value, "&")) {
            const ptr_ti = self.allocType(.Pointer);
            ptr_ti.pointee_type = inner_type;
            return ptr_ti;
        }
        if (std.mem.eql(u8, tok.value, ".*")) {
            if (inner_type.?.category != TypeCategory.Pointer) {
                self.reportError(tok, "Dereference requires pointer operand.", .{});
                return null;
            }
            return inner_type.?.pointee_type;
        }
        return inner_type;
    }

    fn anaMemberAccess(self: *Analyzer, node: *ASTNode) SemanticError!?*TypeInfo {
        const left_type = if (node.left) |l| try self.anaNode(l) else return null;
        if (node.right) |right_node| {
            if (right_node.node_type == ASTNodeType.FunctionCall) {
                return try self.anaNode(right_node);
            }
            if (right_node.token) |rtok| {
                const field_name = rtok.value;
                if (left_type.?.category == TypeCategory.Struct or left_type.?.category == TypeCategory.Named) {
                    const type_name = left_type.?.name orelse return null;
                    if (self.sym_table.resolveGlobal(type_name)) |struct_sym| {
                        if (struct_sym.fields) |fields| {
                            if (fields.get(field_name)) |field_sym| return field_sym.resolved_type;
                            self.reportError(rtok, "Struct '{s}' has no field '{s}'.", .{ type_name, field_name });
                            return null;
                        }
                    }
                }
                if (left_type.?.category == TypeCategory.Enum) {
                    return left_type;
                }
            }
        }
        return left_type;
    }

    fn anaIdentifier(self: *Analyzer, node: *ASTNode) ?*TypeInfo {
        const tok = node.token orelse return null;
        const name = tok.value;

        if (self.undeclared_whitelist.contains(name)) {
            return self.allocType(.Any);
        }

        if (self.sym_table.resolve(name)) |sym| {
            if (sym.resolved_type) |rt| return rt;
            switch (sym.symbol_type) {
                SymbolType.Function => {
                    if (sym.return_type) |rt| return rt;
                    return self.allocType(.Function);
                },
                SymbolType.Struct => return namedType(self, name, .Struct),
                SymbolType.Enum => return namedType(self, name, .Enum),
                SymbolType.Union => return namedType(self, name, .Union),
                SymbolType.ErrorSet => return namedType(self, name, .ErrorSet),
                SymbolType.TypeAlias => {
                    if (sym.resolved_type) |rt| return rt;
                    return null;
                },
                else => return null,
            }
        }

        self.reportError(tok, "Use of undeclared identifier '{s}'.", .{name});
        return null;
    }

    fn anaFunctionCall(self: *Analyzer, node: *ASTNode) SemanticError!?*TypeInfo {
        const tok = node.token orelse return null;
        const name = tok.value;

        var arg_count: usize = 0;
        if (node.children) |children| arg_count = children.items.len;

        if (self.sym_table.resolve(name)) |sym| {
            if (sym.symbol_type == SymbolType.Function) {
                if (arg_count != sym.param_count) {
                    self.reportError(tok, "Function '{s}' expects {} argument(s) but got {}.", .{ name, sym.param_count, arg_count });
                }
                if (node.children) |children| {
                    for (children.items, 0..) |arg, i| {
                        if (arg.left) |arg_expr| _ = try self.anaNode(arg_expr);
                        _ = i;
                    }
                }
                if (sym.return_type) |rt| return rt;
            }
        } else if (!self.undeclared_whitelist.contains(name)) {
            self.reportError(tok, "Call to undeclared function '{s}'.", .{name});
        }

        if (node.children) |children| {
            for (children.items) |arg| {
                if (arg.left) |arg_expr| _ = try self.anaNode(arg_expr);
            }
        }
        return null;
    }

    fn typesCompatible(self: *Analyzer, expected: *const TypeInfo, actual: *const TypeInfo) bool {
        if (expected.category == TypeCategory.Any) return true;
        if (expected.category == actual.category) {
            if (expected.category == TypeCategory.Integer) return true;
            if (expected.category == TypeCategory.Float) return true;
            if (expected.category == TypeCategory.Pointer) {
                if (expected.pointee_type) |ep| {
                    if (actual.pointee_type) |ap| return self.typesCompatible(ep, ap);
                    return false;
                }
                return actual.pointee_type == null;
            }
            return true;
        }
        return false;
    }
};
