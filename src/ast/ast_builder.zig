// ast_builder.zig — Razen Phase 2
//
// This is the main thing that turns a flat list of tokens into a tree.
// It walks through the token list from Phase 1 and builds top-level AST nodes.
//
// What it can handle right now:
//   name : type = expr;          just a variable with an explicit type
//   name : type;                 variable with no initial value (zero init)
//   name := expr;                variable where the type gets figured out from the value
//   mut name : type = expr;      same but mutable
//   mut name := expr;            mutable + inferred type
//   const NAME : type = expr;    compile-time constant
//   const func name(…) -> T { }  a constant function
//
// Inside function bodies you can do:
//   ret expr                     return something
//   name = expr;                 assign to a variable
//   name += expr;  (etc.)        compound assignment
//   if cond { … } else { … }     if/else, no parens needed
//   loop { … }                   infinite loop until you break
//   break / skip                 get out of or skip a loop iteration
//   name(args…);                 call a function
//
// Functions look like:
//   func name(params) -> ret { body }
//   pub func …   (public version)
const std = @import("std");
const lexer = @import("../lexer/lexer.zig");
const token_mod = @import("../lexer/token.zig");
const node_mod = @import("node.zig");
const ast_data_mod = @import("ast_data.zig");
const ast_utils = @import("ast_utils.zig");
const tok_utils = @import("token_utils.zig");
const expr_mod = @import("expression.zig");
const errors = @import("errors.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Token = lexer.Token;
const TokenType = token_mod.TokenType;
const ASTNode = node_mod.ASTNode;
const ASTNodeType = node_mod.ASTNodeType;
const ASTData = ast_data_mod.ASTData;
const AstError = errors.AstError;
const print = std.debug.print;

// just a sanity cap so we never get stuck in an infinite loop
const MAX_LOOP: usize = 100_000;

// entry point:

pub fn buildAST(
    allocator: *Allocator,
    token_list: *const ArrayList(Token),
    source: []const u8,
) !*ArrayList(*ASTNode) {
    _ = source;

    print("\t{s}Formatting AST{s}\t\t\t", .{ lexer.GREY, lexer.RESET });

    const ast_nodes: *ArrayList(*ASTNode) = try allocator.*.create(ArrayList(*ASTNode));
    ast_nodes.* = try ArrayList(*ASTNode).initCapacity(allocator.*, 0);

    var ast_data = ASTData{
        .ast_nodes = ast_nodes,
        .token_list = token_list,
        .token_index = 0,
    };

    const count: usize = token_list.items.len;
    var loop_guard: usize = 0;

    while (ast_data.token_index < count) {
        loop_guard += 1;
        if (loop_guard >= MAX_LOOP) return AstError.Infinite_While_Loop;

        const before: usize = ast_data.token_index;

        processGlobalToken(allocator, &ast_data) catch |err| {
            print("{s}Error: {}{s}\n", .{ lexer.RED, err, lexer.RESET });
            if (ast_data.error_detail) |d|
                print("\t{s}Detail:{s}  {s}\n", .{ lexer.GREY, lexer.RESET, d });
            if (ast_data.error_token) |t|
                print("\t{s}Near:{s}    '{s}' ({})\n", .{ lexer.GREY, lexer.RESET, t.value, t.token_type });
            return err;
        };

        // if we didn't move forward, nudge past the stuck token
        if (before == ast_data.token_index) ast_data.token_index += 1;
    }

    print("{s}Done{s}\n", .{ lexer.CYAN, lexer.RESET });
    return ast_nodes;
}

// top-level token dispatcher:

fn processGlobalToken(allocator: *Allocator, d: *ASTData) AstError!void {
    d.error_function = "processGlobalToken";
    const tok: Token = try d.getToken();

    switch (tok.token_type) {
        // skip comment markers, they don't produce nodes
        TokenType.Comment, TokenType.EndComment => d.advance(),

        // pub func …
        TokenType.Pub => {
            d.advance();
            const nxt: Token = try d.getToken();
            if (nxt.token_type != TokenType.Func) {
                d.setError("Expected 'func' after 'pub'", nxt);
                return AstError.Unexpected_Type;
            }
            const n: *ASTNode = try parseFuncDecl(allocator, d, true);
            try d.ast_nodes.append(allocator.*, n);
        },

        // func …
        TokenType.Func => {
            const n: *ASTNode = try parseFuncDecl(allocator, d, false);
            try d.ast_nodes.append(allocator.*, n);
        },

        // const NAME : type = expr;  or  const func …
        TokenType.Const => {
            const n: *ASTNode = try parseConst(allocator, d);
            try d.ast_nodes.append(allocator.*, n);
        },

        // mut name : type = expr;   or   mut name := expr;
        TokenType.Mut => {
            const n: *ASTNode = try parseVarDecl(allocator, d, true);
            try d.ast_nodes.append(allocator.*, n);
        },

        // name : type = expr;   name := expr;   name = expr;   name(…)
        TokenType.Identifier => {
            const n: *ASTNode = try parseIdentifierStatement(allocator, d, false);
            try d.ast_nodes.append(allocator.*, n);
        },

        else => {
            // we don't know what this is at the top level, just skip it
            d.setError("Unrecognised token at top level", tok);
            d.advance();
        },
    }
}

// statement dispatcher (inside function bodies / blocks):

fn processStatement(allocator: *Allocator, d: *ASTData, body: *ASTNode) AstError!void {
    d.error_function = "processStatement";
    const tok: Token = try d.getToken();

    switch (tok.token_type) {
        TokenType.Comment, TokenType.EndComment => d.advance(),
        TokenType.RightBrace => return,

        TokenType.Ret => {
            const n: *ASTNode = try parseReturn(allocator, d);
            try ast_utils.appendChild(allocator, body, n);
        },
        TokenType.If => {
            const n: *ASTNode = try parseIf(allocator, d);
            try ast_utils.appendChild(allocator, body, n);
        },
        TokenType.Loop => {
            const n: *ASTNode = try parseLoop(allocator, d);
            try ast_utils.appendChild(allocator, body, n);
        },
        TokenType.Break => {
            const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            n.node_type = ASTNodeType.ReturnStatement;
            n.token = tok;
            d.advance();
            consumeSemi(d);
            try ast_utils.appendChild(allocator, body, n);
        },
        TokenType.Skip => {
            const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            n.node_type = ASTNodeType.ReturnStatement;
            n.token = tok;
            d.advance();
            consumeSemi(d);
            try ast_utils.appendChild(allocator, body, n);
        },
        TokenType.Const => {
            const n: *ASTNode = try parseConst(allocator, d);
            try ast_utils.appendChild(allocator, body, n);
        },
        TokenType.Mut => {
            const n: *ASTNode = try parseVarDecl(allocator, d, true);
            try ast_utils.appendChild(allocator, body, n);
        },
        TokenType.Identifier => {
            const n: *ASTNode = try parseIdentifierStatement(allocator, d, false);
            try ast_utils.appendChild(allocator, body, n);
        },
        else => {
            // don't know this token inside a body, just skip it
            d.advance();
        },
    }
}

// identifier-started statement: could be a decl, assignment, or plain expr:

// Figures out what to do when a statement starts with a name.
// Could be:
//   name : type = expr;     explicit declaration
//   name := expr;           inferred declaration
//   name = expr;            simple assignment
//   name += expr;  etc.     compound assignment
//   name(args…);            function call
fn parseIdentifierStatement(allocator: *Allocator, d: *ASTData, is_mut: bool) AstError!*ASTNode {
    const name_tok: Token = try d.getToken(); // we're sitting on the identifier
    const nxt = d.peekToken(1); // look one ahead to see what comes next

    if (nxt == null) {
        // nothing after the name, treat it as a bare expression
        d.advance();
        const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
        n.node_type = ASTNodeType.Identifier;
        n.token = name_tok;
        return n;
    }

    const nxt_tt = nxt.?.token_type;

    // name : type …  ->  explicit declaration
    if (nxt_tt == TokenType.Colon) {
        return try parseVarDecl(allocator, d, is_mut);
    }
    // name := expr   ->  inferred declaration
    if (nxt_tt == TokenType.ColonEquals) {
        return try parseVarDecl(allocator, d, is_mut);
    }
    // name = expr;  ->  name += expr;  etc.
    if (tok_utils.isAssignmentOperator(nxt_tt)) {
        return try parseAssignment(allocator, d);
    }
    // name(args…)  ->  function call
    if (nxt_tt == TokenType.LeftParen) {
        d.advance(); // consume name
        const node: *ASTNode = try parseCallNode(allocator, d, name_tok);
        consumeSemi(d);
        return node;
    }
    // anything else, try to parse it as a binary expression
    const expr = try expr_mod.parseBinaryExpr(allocator, d, 0);
    consumeSemi(d);
    if (expr) |e| return e;
    const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    n.node_type = ASTNodeType.Identifier;
    n.token = name_tok;
    return n;
}

// const declaration:

fn parseConst(allocator: *Allocator, d: *ASTData) AstError!*ASTNode {
    d.error_function = "parseConst";
    d.advance(); // eat the 'const' keyword

    const nxt: Token = try d.getToken();
    if (nxt.token_type == TokenType.Func) {
        // const func — just a function that's also marked const
        const n: *ASTNode = try parseFuncDecl(allocator, d, false);
        n.is_const = true;
        return n;
    }

    // const NAME : type = expr
    const n: *ASTNode = try parseVarDecl(allocator, d, false);
    n.node_type = ASTNodeType.ConstDeclaration;
    n.is_const = true;
    return n;
}

// variable declaration:

// Handles all the different ways you can declare a variable.
// When we get here, the current token might be 'mut' or the name itself.
fn parseVarDecl(allocator: *Allocator, d: *ASTData, caller_mut: bool) AstError!*ASTNode {
    d.error_function = "parseVarDecl";

    // if there's a 'mut' keyword here, consume it
    var is_mut = caller_mut;
    if (d.hasMore()) {
        const cur: Token = try d.getToken();
        if (cur.token_type == TokenType.Mut) {
            is_mut = true;
            d.advance();
        }
    }

    // grab the variable name
    const name_tok: Token = try d.getToken();
    if (name_tok.token_type != TokenType.Identifier) {
        d.setError("Expected variable name (identifier)", name_tok);
        return AstError.Unexpected_Type;
    }
    d.advance(); // move past the name

    // next should be either ':=' (inferred type) or ':' (explicit type)
    const sep: Token = try d.getToken();

    if (sep.token_type == TokenType.ColonEquals) {
        // name := expr
        d.advance(); // eat ':='
        return try finishInferred(allocator, d, name_tok, is_mut);
    }

    if (sep.token_type == TokenType.Colon) {
        // name : type [= expr]  or  name : type;
        d.advance(); // eat ':'
        return try finishExplicit(allocator, d, name_tok, is_mut, false);
    }

    d.setError("Expected ':' or ':=' in variable declaration", sep);
    return AstError.Unexpected_Type;
}

// finish up:  name := expr;
fn finishInferred(
    allocator: *Allocator,
    d: *ASTData,
    name_tok: Token,
    is_mut: bool,
) AstError!*ASTNode {
    const value = try expr_mod.parseBinaryExpr(allocator, d, 0);
    consumeSemi(d);

    const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    n.node_type = ASTNodeType.VarDeclaration;
    n.token = name_tok; // name goes in .token, no type node since it's inferred
    n.right = value;
    n.is_mut = is_mut;
    return n;
}

// finish up:  name : type [= expr] ;
fn finishExplicit(
    allocator: *Allocator,
    d: *ASTData,
    name_tok: Token,
    is_mut: bool,
    is_global: bool,
) AstError!*ASTNode {
    // the type keyword comes right after the ':'
    const type_tok: Token = try d.getToken();
    if (!tok_utils.isTypeToken(type_tok.token_type)) {
        d.setError("Expected type after ':' in declaration", type_tok);
        return AstError.Unexpected_Type;
    }
    d.advance(); // eat the type

    const type_node: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    type_node.node_type = ASTNodeType.VarType;
    type_node.token = type_tok;

    const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    n.node_type = ASTNodeType.VarDeclaration;
    n.token = name_tok; // name in .token
    n.left = type_node; // type in .left
    n.is_mut = is_mut;
    n.is_global = is_global;

    // an '= expr' part is optional, check for it
    if (d.hasMore()) {
        const eq_or_semi: Token = try d.getToken();
        if (eq_or_semi.token_type == TokenType.Equals) {
            d.advance(); // eat '='
            n.right = try expr_mod.parseBinaryExpr(allocator, d, 0);
            consumeSemi(d);
        } else if (eq_or_semi.token_type == TokenType.Semicolon) {
            d.advance(); // eat ';', no value was given
        }
        // if neither, just leave it — we're lenient about missing semicolons
    }

    return n;
}

// assignment  name = expr;   name += expr;  etc.:

fn parseAssignment(allocator: *Allocator, d: *ASTData) AstError!*ASTNode {
    d.error_function = "parseAssignment";

    const name_tok: Token = try d.getToken();
    d.advance(); // eat the name
    const op_tok: Token = try d.getToken();
    d.advance(); // eat the operator

    const value = try expr_mod.parseBinaryExpr(allocator, d, 0);
    consumeSemi(d);

    const id: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    id.node_type = ASTNodeType.Identifier;
    id.token = name_tok;

    const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    n.node_type = ASTNodeType.Assignment;
    n.token = op_tok; // the operator token is stored here
    n.left = id;
    n.right = value;
    return n;
}

// function declaration:

// Parses:  func name(params) -> ret_type { body }
// We get here with the current token sitting on 'func'.
fn parseFuncDecl(allocator: *Allocator, d: *ASTData, is_pub: bool) AstError!*ASTNode {
    d.error_function = "parseFuncDecl";
    d.advance(); // eat 'func'

    // function name
    const name_tok: Token = try d.getToken();
    if (name_tok.token_type != TokenType.Identifier) {
        d.setError("Expected function name after 'func'", name_tok);
        return AstError.Unexpected_Type;
    }
    d.advance(); // eat the name

    // we need a '(' next
    const lp: Token = try d.getToken();
    if (lp.token_type != TokenType.LeftParen) {
        d.setError("Expected '(' after function name", lp);
        return AstError.Unexpected_Type;
    }
    d.advance(); // eat '('

    // parse the parameter list
    const params: *ASTNode = try parseParams(allocator, d);

    // -> is optional (void functions might skip it)
    if (d.hasMore()) {
        const maybe_arrow: Token = try d.getToken();
        if (maybe_arrow.token_type == TokenType.Arrow) {
            d.advance();
        }
    }

    // return type
    const ret_node: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    ret_node.node_type = ASTNodeType.ReturnType;
    if (d.hasMore()) {
        const ret_tok: Token = try d.getToken();
        if (tok_utils.isTypeToken(ret_tok.token_type)) {
            ret_node.token = ret_tok;
            d.advance();
        }
    }

    // the function body
    const body: *ASTNode = try parseBlock(allocator, d);

    const func: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    func.node_type = ASTNodeType.FunctionDeclaration;
    func.token = name_tok;
    func.left = ret_node;
    func.middle = params;
    func.right = body;
    func.is_pub = is_pub;
    return func;
}

// parameter list    (  name: type, …  )   — '(' already consumed:

fn parseParams(allocator: *Allocator, d: *ASTData) AstError!*ASTNode {
    d.error_function = "parseParams";

    const params: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    params.node_type = ASTNodeType.Parameters;
    params.children = try ast_utils.createChildList(allocator);

    var guard: usize = 0;
    while (d.hasMore()) {
        guard += 1;
        if (guard >= MAX_LOOP) return AstError.Infinite_While_Loop;

        const cur: Token = try d.getToken();
        if (cur.token_type == TokenType.RightParen) {
            d.advance(); // eat ')'
            break;
        }

        // param name
        if (cur.token_type != TokenType.Identifier) {
            d.setError("Expected parameter name", cur);
            return AstError.Unexpected_Type;
        }
        d.advance(); // eat param name

        // ':'
        const colon: Token = try d.getToken();
        if (colon.token_type != TokenType.Colon) {
            d.setError("Expected ':' after parameter name", colon);
            return AstError.Unexpected_Type;
        }
        d.advance(); // eat ':'

        // parameter type
        const type_tok: Token = try d.getToken();
        if (!tok_utils.isTypeToken(type_tok.token_type)) {
            d.setError("Expected type in parameter", type_tok);
            return AstError.Unexpected_Type;
        }
        d.advance(); // eat the type

        const type_node: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
        type_node.node_type = ASTNodeType.VarType;
        type_node.token = type_tok;

        const param: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
        param.node_type = ASTNodeType.Parameter;
        param.token = cur; // the param name
        param.left = type_node;

        params.children.?.append(allocator.*, param) catch return AstError.Out_Of_Memory;

        // comma between params is optional
        if (d.hasMore()) {
            const maybe_comma: Token = try d.getToken();
            if (maybe_comma.token_type == TokenType.Comma) d.advance();
        }
    }

    return params;
}

// block   { statements… }

fn parseBlock(allocator: *Allocator, d: *ASTData) AstError!*ASTNode {
    d.error_function = "parseBlock";

    // eat the opening '{'
    if (d.hasMore()) {
        const b: Token = try d.getToken();
        if (b.token_type == TokenType.LeftBrace) d.advance();
    }

    const block: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    block.node_type = ASTNodeType.Block;

    var guard: usize = 0;
    while (d.hasMore()) {
        guard += 1;
        if (guard >= MAX_LOOP) return AstError.Infinite_While_Loop;

        const cur: Token = try d.getToken();
        if (cur.token_type == TokenType.RightBrace) {
            d.advance(); // eat '}'
            break;
        }

        try processStatement(allocator, d, block);
    }

    return block;
}

// function call (name already consumed, sitting on '(')

fn parseCallNode(allocator: *Allocator, d: *ASTData, name_tok: Token) AstError!*ASTNode {
    const call: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    call.node_type = ASTNodeType.FunctionCall;
    call.token = name_tok;
    call.children = try ast_utils.createChildList(allocator);

    d.advance(); // eat '('

    var guard: usize = 0;
    while (d.hasMore()) {
        guard += 1;
        if (guard >= MAX_LOOP) return AstError.Infinite_While_Loop;

        const cur: Token = try d.getToken();
        if (cur.token_type == TokenType.RightParen) {
            d.advance();
            break;
        }

        const arg_expr = try expr_mod.parseBinaryExpr(allocator, d, 0);
        if (arg_expr) |ae| {
            const arg: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            arg.node_type = ASTNodeType.Argument;
            arg.left = ae;
            call.children.?.append(allocator.*, arg) catch return AstError.Out_Of_Memory;
        }

        // optional comma between args
        if (d.hasMore()) {
            const mc: Token = try d.getToken();
            if (mc.token_type == TokenType.Comma) d.advance();
        }
    }

    return call;
}

//return statement    ret [expr]

fn parseReturn(allocator: *Allocator, d: *ASTData) AstError!*ASTNode {
    d.error_function = "parseReturn";
    const ret_tok: Token = try d.getToken();
    d.advance(); // eat 'ret'

    const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    n.node_type = ASTNodeType.ReturnStatement;
    n.token = ret_tok;

    // the return value is optional — 'ret' alone is valid
    if (d.hasMore()) {
        const nxt: Token = try d.getToken();
        if (nxt.token_type != TokenType.Semicolon and
            nxt.token_type != TokenType.RightBrace)
        {
            n.left = try expr_mod.parseBinaryExpr(allocator, d, 0);
        }
    }
    consumeSemi(d);
    return n;
}

// if / else

fn parseIf(allocator: *Allocator, d: *ASTData) AstError!*ASTNode {
    d.error_function = "parseIf";
    const if_tok: Token = try d.getToken();
    d.advance(); // eat 'if'

    // condition — note: Razen doesn't use parens around the condition
    const cond = try expr_mod.parseBinaryExpr(allocator, d, 0);

    const if_body: *ASTNode = try parseBlock(allocator, d);
    if_body.node_type = ASTNodeType.IfBody;

    const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    n.node_type = ASTNodeType.IfStatement;
    n.token = if_tok;
    n.left = cond;
    n.middle = if_body;

    // else is optional
    if (d.hasMore()) {
        const maybe_else: Token = try d.getToken();
        if (maybe_else.token_type == TokenType.Else) {
            d.advance();
            const else_body: *ASTNode = try parseBlock(allocator, d);
            else_body.node_type = ASTNodeType.ElseBody;
            n.right = else_body;
        }
    }

    return n;
}

// loop    loop { body }

fn parseLoop(allocator: *Allocator, d: *ASTData) AstError!*ASTNode {
    d.error_function = "parseLoop";
    const loop_tok: Token = try d.getToken();
    d.advance(); // eat 'loop'

    const body: *ASTNode = try parseBlock(allocator, d);
    body.node_type = ASTNodeType.LoopBody;

    const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    n.node_type = ASTNodeType.LoopStatement;
    n.token = loop_tok;
    n.left = body;
    return n;
}

// helper: eat a ';' if one is sitting there

fn consumeSemi(d: *ASTData) void {
    if (!d.hasMore()) return;
    const t = d.token_list.items[d.token_index];
    if (t.token_type == TokenType.Semicolon) d.advance();
}
