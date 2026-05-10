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

        TokenType.At => {
            const annotation: *ASTNode = try expr_mod.parsePrimary(allocator, d) orelse return AstError.Unexpected_Type;
            // Now parse the next actual global token but attach this annotation
            if (d.hasMore()) {
                const sub_node = d.ast_nodes.items.len;
                try processGlobalToken(allocator, d);
                // The above call added exactly 1 node to ast_nodes. Let's pull it out and attach the annotation
                if (d.ast_nodes.items.len > sub_node) {
                    const parsed_n = d.ast_nodes.items[d.ast_nodes.items.len - 1];

                    // find a place to park the annotation. `right` is mostly open for Decls, or we can use `middle` depending on the node. Let's just steal the node and wrap it maybe? No, let's put it on parsed_n.middle or parsed_n.left. Wait, nodes don't have an `annotation` field. Let's just store it in parsed_n.middle or parsed_n.left if null!
                    if (parsed_n.node_type == ASTNodeType.BehaveDeclaration or parsed_n.node_type == ASTNodeType.StructDeclaration or parsed_n.node_type == ASTNodeType.FunctionDeclaration) {
                        parsed_n.middle = annotation;
                    }
                }
            }
        },

        // pub func …
        TokenType.Pub => {
            d.advance();
            const nxt: Token = try d.getToken();
            switch (nxt.token_type) {
                TokenType.Func => {
                    const n: *ASTNode = try parseFuncDecl(allocator, d, true);
                    try d.ast_nodes.append(allocator.*, n);
                },
                TokenType.Async => {
                    d.advance(); // eat 'async'
                    const n: *ASTNode = try parseFuncDecl(allocator, d, true);
                    n.is_async = true;
                    try d.ast_nodes.append(allocator.*, n);
                },
                TokenType.Struct => {
                    const n: *ASTNode = try parseStruct(allocator, d, true);
                    try d.ast_nodes.append(allocator.*, n);
                },
                TokenType.Enum => {
                    const n: *ASTNode = try parseEnum(allocator, d, true);
                    try d.ast_nodes.append(allocator.*, n);
                },
                TokenType.Union => {
                    const n: *ASTNode = try parseUnion(allocator, d, true);
                    try d.ast_nodes.append(allocator.*, n);
                },
                TokenType.Type => {
                    const n: *ASTNode = try parseTypeAlias(allocator, d, true);
                    try d.ast_nodes.append(allocator.*, n);
                },
                else => {
                    d.setError("Expected decl after 'pub'", nxt);
                    return AstError.Unexpected_Type;
                },
            }
        },

        TokenType.Struct => {
            const n: *ASTNode = try parseStruct(allocator, d, false);
            try d.ast_nodes.append(allocator.*, n);
        },
        TokenType.Enum => {
            const n: *ASTNode = try parseEnum(allocator, d, false);
            try d.ast_nodes.append(allocator.*, n);
        },
        TokenType.Union => {
            const n: *ASTNode = try parseUnion(allocator, d, false);
            try d.ast_nodes.append(allocator.*, n);
        },
        TokenType.Type => {
            const n: *ASTNode = try parseTypeAlias(allocator, d, false);
            try d.ast_nodes.append(allocator.*, n);
        },
        TokenType.Error => {
            const n: *ASTNode = try parseErrorMap(allocator, d);
            try d.ast_nodes.append(allocator.*, n);
        },
        TokenType.Mod => {
            const n: *ASTNode = try parseModule(allocator, d);
            try d.ast_nodes.append(allocator.*, n);
        },
        TokenType.Use => {
            const n: *ASTNode = try parseUse(allocator, d);
            try d.ast_nodes.append(allocator.*, n);
        },
        TokenType.Behave => {
            const n: *ASTNode = try parseBehave(allocator, d);
            try d.ast_nodes.append(allocator.*, n);
        },
        TokenType.Ext => {
            const n: *ASTNode = try parseExt(allocator, d);
            try d.ast_nodes.append(allocator.*, n);
        },

        // async func …
        TokenType.Async => {
            d.advance(); // eat 'async'
            const n: *ASTNode = try parseFuncDecl(allocator, d, false);
            n.is_async = true;
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
        TokenType.Match => {
            const n: *ASTNode = try parseMatch(allocator, d);
            try ast_utils.appendChild(allocator, body, n);
        },
        TokenType.Defer => {
            const n: *ASTNode = try parseDefer(allocator, d);
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
        TokenType.Try => {
            // try expr [catch |e| { ... }]
            const n: *ASTNode = try parseTryStatement(allocator, d);
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

// Variables and Constants (const mut, const func)
fn parseConst(allocator: *Allocator, d: *ASTData) AstError!*ASTNode {
    d.error_function = "parseConst";
    d.advance(); // eat 'const'

    if (!d.hasMore()) return AstError.Unexpected_Type;

    const nxt: Token = try d.getToken();
    if (nxt.token_type == TokenType.Func) {
        // const func — just a function that's also marked const
        const n: *ASTNode = try parseFuncDecl(allocator, d, false);
        n.is_const = true;
        return n;
    }

    var is_mut: bool = false;
    if (nxt.token_type == TokenType.Mut) {
        is_mut = true;
        d.advance(); // eat 'mut'
    }

    // const NAME : type = expr
    const n: *ASTNode = try parseVarDecl(allocator, d, is_mut);
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
    var value: ?*ASTNode = null;
    const peek = d.peekToken(0);
    if (peek != null and peek.?.token_type == TokenType.Try) {
        value = try parseTryStatement(allocator, d);
    } else {
        value = try expr_mod.parseBinaryExpr(allocator, d, 0);
        consumeSemi(d);
    }

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
    const type_node: *ASTNode = try parseTypeNode(allocator, d);

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
            const peek = d.peekToken(0);
            if (peek != null and peek.?.token_type == TokenType.Try) {
                n.right = try parseTryStatement(allocator, d);
            } else {
                n.right = try expr_mod.parseBinaryExpr(allocator, d, 0);
                consumeSemi(d);
            }
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
// The body `{ ... }` is optional — if there's no '{' after the return type
// we treat it as a forward/signature-only declaration (used by ext + behave).
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

    // return type — parse it if the next token isn't '{'
    const ret_node: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    ret_node.node_type = ASTNodeType.ReturnType;
    if (d.hasMore()) {
        const t1 = try d.getToken();
        if (t1.token_type != TokenType.LeftBrace) {
            ret_node.left = try parseTypeNode(allocator, d);
        }
    }

    // the function body — optional (a signature ends here if no '{')
    var body: ?*ASTNode = null;
    if (d.hasMore()) {
        const maybe_lb: Token = try d.getToken();
        if (maybe_lb.token_type == TokenType.LeftBrace) {
            body = try parseBlock(allocator, d);
        }
        // if no '{', this is a forward declaration — no body node
    }

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
        if (cur.token_type == TokenType.Comma) {
            d.advance();
            continue;
        }
        // skip stray commas or semicolons
        if (cur.token_type == TokenType.Semicolon) {
            d.advance();
            continue;
        }
        // variadic  ...
        if (cur.token_type == TokenType.DotDotDot) {
            d.advance();
            const p: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            p.node_type = ASTNodeType.Parameter;
            p.token = cur;
            params.children.?.append(allocator.*, p) catch return AstError.Out_Of_Memory;
            continue;
        }

        // optional `mut` or `const` prefix on parameter
        var param_is_mut = false;
        var param_is_const = false;
        var name_tok: Token = cur;

        if (cur.token_type == TokenType.Mut) {
            param_is_mut = true;
            d.advance();
            name_tok = try d.getToken();
        } else if (cur.token_type == TokenType.Const) {
            param_is_const = true;
            d.advance();
            name_tok = try d.getToken();
        }

        // param name must be an identifier
        if (name_tok.token_type != TokenType.Identifier) {
            d.setError("Expected parameter name", name_tok);
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
        const type_node: *ASTNode = try parseTypeNode(allocator, d);

        const param: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
        param.node_type = ASTNodeType.Parameter;
        param.token = name_tok;
        param.left = type_node;
        param.is_mut = param_is_mut;
        param.is_const = param_is_const;

        params.children.?.append(allocator.*, param) catch return AstError.Out_Of_Memory;

        // optional trailing comma
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

fn parseLoop(allocator: *Allocator, d: *ASTData) AstError!*ASTNode {
    d.error_function = "parseLoop";
    const tok: Token = try d.getToken();
    d.advance(); // eat 'loop'

    const loop_st: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    loop_st.node_type = ASTNodeType.LoopStatement;
    loop_st.token = tok;

    // Check if it's `loop { ... }` or `loop cond { ... }` or `loop obj |item| { ... }`
    const peek = d.peekToken(0);
    if (peek != null and peek.?.token_type != TokenType.LeftBrace) {
        // Protect |item| { so parseBinaryExpr doesn't eat | as bitwise OR
        var found_pipe = false;
        var pipe_idx: usize = 0;
        for (d.token_list.items[d.token_index..d.token_list.items.len], 0..) |t, i| {
            if (t.token_type == TokenType.LeftBrace) break;
            if (t.token_type == TokenType.Or) {
                const idx = d.token_index + i;
                if (idx + 3 < d.token_list.items.len) {
                    if (d.token_list.items[idx + 1].token_type == TokenType.Identifier and
                        d.token_list.items[idx + 2].token_type == TokenType.Or and
                        d.token_list.items[idx + 3].token_type == TokenType.LeftBrace)
                    {
                        found_pipe = true;
                        pipe_idx = idx;
                        break;
                    }
                }
            }
        }

        if (found_pipe) d.token_list.items[pipe_idx].token_type = TokenType.Semicolon;
        loop_st.left = try expr_mod.parseBinaryExpr(allocator, d, 0); // cond or obj
        if (found_pipe) d.token_list.items[pipe_idx].token_type = TokenType.Or;

        // Zig style iterator bounds: `|item|`
        const nx = d.peekToken(0);
        if (nx != null and nx.?.token_type == TokenType.Or) {
            d.advance(); // |
            const item: Token = try d.getToken(); // item
            if (item.token_type == TokenType.Identifier) {
                const item_n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
                item_n.node_type = ASTNodeType.Identifier;
                item_n.token = item;
                loop_st.middle = item_n;
                d.advance();

                // second |
                const nx2: Token = try d.getToken();
                if (nx2.token_type == TokenType.Or) d.advance();
            } else {
                d.advance();
            }
        }
    }

    const lb: Token = try d.getToken();
    if (lb.token_type != TokenType.LeftBrace) {
        d.setError("Expected '{' for loop body", lb);
        return AstError.Unexpected_Type;
    }

    // parse the block
    const b: *ASTNode = try parseBlock(allocator, d);

    // we map the block into a LoopBody node so the tree structure is clearer
    const body_node: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    body_node.node_type = ASTNodeType.LoopBody;
    body_node.children = b.children; // steal the block's children
    loop_st.right = body_node;

    return loop_st;
}

// parse: try expr [catch |e| { ... }]
// This can appear both as a statement and as part of a := declaration.
fn parseTryStatement(allocator: *Allocator, d: *ASTData) AstError!*ASTNode {
    d.error_function = "parseTryStatement";
    const try_tok: Token = try d.getToken();
    d.advance(); // eat 'try'

    const expr = try expr_mod.parseBinaryExpr(allocator, d, 0);

    const try_node: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    try_node.node_type = ASTNodeType.TryExpression;
    try_node.token = try_tok;
    try_node.left = expr;

    // optional catch
    if (d.hasMore()) {
        const maybe_catch: Token = try d.getToken();
        if (maybe_catch.token_type == TokenType.Catch) {
            d.advance(); // eat 'catch'

            // optional |e| capture
            if (d.hasMore()) {
                const pipe = try d.getToken();
                if (pipe.token_type == TokenType.Or) {
                    d.advance(); // eat |
                    const e_tok = try d.getToken();
                    d.advance(); // eat capture name
                    const pipe2 = try d.getToken();
                    if (pipe2.token_type == TokenType.Or) d.advance(); // eat |
                    _ = e_tok;
                }
            }

            // catch body: either { block } or a single expression
            const catch_node: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            catch_node.node_type = ASTNodeType.CatchExpression;
            catch_node.token = maybe_catch;

            if (d.hasMore()) {
                const peek: Token = try d.getToken();
                if (peek.token_type == TokenType.LeftBrace) {
                    catch_node.left = try parseBlock(allocator, d);
                } else {
                    catch_node.left = try expr_mod.parseBinaryExpr(allocator, d, 0);
                }
            }
            try_node.right = catch_node;
        }
    }

    consumeSemi(d);
    return try_node;
}

// helper: eat a ';' if one is sitting there
fn consumeSemi(d: *ASTData) void {
    if (!d.hasMore()) return;
    const t = d.token_list.items[d.token_index];
    if (t.token_type == TokenType.Semicolon) d.advance();
}

fn parseTypeNode(allocator: *Allocator, d: *ASTData) AstError!*ASTNode {
    const type_node: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    type_node.node_type = ASTNodeType.VarType;

    const tok = try d.getToken();
    d.advance(); // consume the first token of the type

    // ── modifiers that wrap another type ────────────────────────────────
    // * T   pointer
    // & T   reference (address-of in type position)
    // ! T   failable (anonymous error)
    // ? T   optional
    // mut   mutable modifier (in param lists like `mut a: @Self`)
    if (tok.token_type == TokenType.Star or
        tok.token_type == TokenType.And or
        tok.token_type == TokenType.ExclamationMark or
        tok.token_type == TokenType.QuestionMark)
    {
        const inner = try parseTypeNode(allocator, d);
        type_node.token = tok;
        type_node.left = inner;
        return type_node;
    }

    // mut in type position (param like `mut a: @Self` — mut already consumed by parseParams,
    // but handle if we ever hit it here)
    if (tok.token_type == TokenType.Mut) {
        const inner = try parseTypeNode(allocator, d);
        type_node.token = tok;
        type_node.is_mut = true;
        type_node.left = inner;
        return type_node;
    }

    // ── [ T ]  or  [ T ; N ]  ─────────────────────────────────────────
    if (tok.token_type == TokenType.LeftBracket) {
        const inner = try parseTypeNode(allocator, d);
        // optional size:  [T; N]
        if (d.hasMore()) {
            const nt = try d.getToken();
            if (nt.token_type == TokenType.Semicolon) {
                d.advance();
                const size_tok = try d.getToken();
                d.advance(); // consume the size literal
                const size_node: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
                size_node.node_type = ASTNodeType.IntegerLiteral;
                size_node.token = size_tok;
                type_node.middle = size_node;
            }
        }
        const rb = try d.getToken();
        if (rb.token_type == TokenType.RightBracket) d.advance();

        type_node.node_type = ASTNodeType.ArrayType;
        type_node.token = tok;
        type_node.left = inner;
        return type_node;
    }

    // ── vec[T]  map{K, V}  set{T} ─────────────────────────────────────
    if (tok.token_type == TokenType.Identifier and
        (std.mem.eql(u8, tok.value, "vec") or
            std.mem.eql(u8, tok.value, "map") or
            std.mem.eql(u8, tok.value, "set")))
    {
        const open = try d.getToken();
        if (open.token_type == TokenType.LeftBracket or open.token_type == TokenType.LeftBrace) d.advance();
        const inner = try parseTypeNode(allocator, d);
        type_node.left = inner;

        // map needs K and V
        const after = try d.getToken();
        if (after.token_type == TokenType.Comma) {
            d.advance(); // eat ','
            const inner2 = try parseTypeNode(allocator, d);
            type_node.middle = inner2;
        }

        const close = try d.getToken();
        if (close.token_type == TokenType.RightBracket or close.token_type == TokenType.RightBrace) d.advance();

        type_node.token = tok;
        return type_node;
    }

    // ── Error ! T  (named error union) ────────────────────────────────
    // e.g. FileError!str  — tok is an Identifier "FileError"
    if (tok.token_type == TokenType.Identifier) {
        // peek: is the next token '!'? then it's ErrorType!ValueType
        if (d.hasMore()) {
            const maybe_excl = try d.getToken();
            if (maybe_excl.token_type == TokenType.ExclamationMark) {
                d.advance(); // eat '!'
                const inner = try parseTypeNode(allocator, d);
                type_node.token = tok; // the error type name
                type_node.left = inner;
                return type_node;
            }
        }
        // plain identifier type name (user-defined type)
        type_node.token = tok;
        return type_node;
    }

    // ── error keyword without a name  ( !T bare anonymous error ) ─────
    if (tok.token_type == TokenType.Error) {
        const excl = try d.getToken();
        if (excl.token_type == TokenType.ExclamationMark) d.advance();
        const inner = try parseTypeNode(allocator, d);
        type_node.token = tok;
        type_node.left = inner;
        return type_node;
    }

    // ── @ builtins: @Self, @Type, @Generic(T) ─────────────────────────
    if (tok.token_type == TokenType.At) {
        const name_tok = try d.getToken();
        d.advance(); // eat the builtin name (Self, Type, Generic …)
        type_node.token = name_tok; // e.g. "Self"

        // @Generic(T) — consume the arg list
        if (d.hasMore()) {
            const lp = try d.getToken();
            if (lp.token_type == TokenType.LeftParen) {
                d.advance(); // eat '('
                var depth: usize = 1;
                var guard: usize = 0;
                while (d.hasMore() and depth > 0) {
                    guard += 1;
                    if (guard > 1000) break;
                    const t = try d.getToken();
                    d.advance();
                    if (t.token_type == TokenType.LeftParen) depth += 1;
                    if (t.token_type == TokenType.RightParen) depth -= 1;
                }
            }
        }
        return type_node;
    }

    // ── primitive/built-in type keywords ─────────────────────────────
    if (tok_utils.isVarType(tok.token_type)) {
        // peek for  !  to handle `void!T` style (unusual, but spec mentions it)
        if (d.hasMore()) {
            const maybe_excl = try d.getToken();
            if (maybe_excl.token_type == TokenType.ExclamationMark) {
                d.advance();
                const inner = try parseTypeNode(allocator, d);
                type_node.token = tok;
                type_node.left = inner;
                return type_node;
            }
        }
        type_node.token = tok;
        return type_node;
    }

    // ── DotDot / DotDotDot for variadic params ─────────────────────────
    if (tok.token_type == TokenType.DotDotDot) {
        type_node.token = tok;
        return type_node;
    }

    d.setError("Expected a type", tok);
    return AstError.Unexpected_Type;
}

// ── structs, enums, unions, type, error ────────────────────────────────

fn parseStruct(allocator: *Allocator, d: *ASTData, is_pub: bool) AstError!*ASTNode {
    d.error_function = "parseStruct";
    d.advance(); // eat 'struct'

    const name_tok: Token = try d.getToken();
    if (name_tok.token_type != TokenType.Identifier) {
        d.setError("Expected struct name", name_tok);
        return AstError.Unexpected_Type;
    }
    d.advance(); // eat name

    const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    n.node_type = ASTNodeType.StructDeclaration;
    n.token = name_tok;
    n.is_pub = is_pub;
    n.children = try ast_utils.createChildList(allocator);

    // Traits implementation: ~> TraitName
    if (d.hasMore()) {
        const maybe_tilde: Token = try d.getToken();
        if (maybe_tilde.token_type == TokenType.TildeArrow) {
            d.advance(); // eat ~>
            const trait_name: Token = try d.getToken();
            if (trait_name.token_type == TokenType.Identifier) {
                const trait_node: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
                trait_node.node_type = ASTNodeType.Identifier;
                trait_node.token = trait_name;
                n.left = trait_node; // attach trait implementation
                d.advance(); // eat trait name
            } else {
                d.setError("Expected trait name after ~>", trait_name);
                return AstError.Unexpected_Type;
            }

            // Multiple traits `~> TraitA, TraitB`
            while (d.hasMore()) {
                const comma: Token = try d.getToken();
                if (comma.token_type == TokenType.Comma) {
                    d.advance();
                    const nxt_trait: Token = try d.getToken();
                    if (nxt_trait.token_type == TokenType.Identifier) d.advance();
                    // we could chain these, but for now we just parse them out
                } else {
                    break;
                }
            }
        }
    }

    const lb: Token = try d.getToken();
    if (lb.token_type != TokenType.LeftBrace) {
        d.setError("Expected '{' for struct body", lb);
        return AstError.Unexpected_Type;
    }
    d.advance(); // eat '{'

    // read struct fields & functions
    var guard: usize = 0;
    while (d.hasMore()) {
        guard += 1;
        if (guard >= MAX_LOOP) return AstError.Infinite_While_Loop;
        const cur: Token = try d.getToken();
        if (cur.token_type == TokenType.RightBrace) {
            d.advance();
            break;
        }

        // a field: "name: type," or function "func ..." or just "methodName(p: *Struct) -> .."
        if (cur.token_type == TokenType.Func) {
            const m: *ASTNode = try parseFuncDecl(allocator, d, false);
            n.children.?.append(allocator.*, m) catch return AstError.Out_Of_Memory;
        } else if (cur.token_type == TokenType.Identifier) {
            const nxt = d.peekToken(1);
            if (nxt != null and nxt.?.token_type == TokenType.Colon) {
                // field:  name: type[,]
                d.advance(); // eat field name
                d.advance(); // eat ':'

                // use full type parser so [u8], *T, @Self all work
                const type_node: *ASTNode = try parseTypeNode(allocator, d);

                const field: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
                field.node_type = ASTNodeType.StructField;
                field.token = cur;
                field.left = type_node;

                // optional default value  = expr
                if (d.hasMore()) {
                    const maybe_eq: Token = try d.getToken();
                    if (maybe_eq.token_type == TokenType.Equals) {
                        d.advance();
                        field.right = try expr_mod.parseBinaryExpr(allocator, d, 0);
                    }
                }

                n.children.?.append(allocator.*, field) catch return AstError.Out_Of_Memory;
                if (d.hasMore()) {
                    const comma: Token = try d.getToken();
                    if (comma.token_type == TokenType.Comma) d.advance();
                }
            } else if (nxt != null and nxt.?.token_type == TokenType.LeftParen) {
                // inline method without `func` keyword: methodName(p: *Struct) -> ..
                d.token_list.items[d.token_index] = Token{ .token_type = TokenType.Func, .value = "func", .line = cur.line, .character = cur.character };
                const m: *ASTNode = try parseFuncDecl(allocator, d, false);
                n.children.?.append(allocator.*, m) catch return AstError.Out_Of_Memory;
            } else {
                d.advance();
            }
        } else {
            d.advance();
        }
    }
    return n;
}

fn parseEnum(allocator: *Allocator, d: *ASTData, is_pub: bool) AstError!*ASTNode {
    d.error_function = "parseEnum";
    d.advance(); // eat 'enum'

    const name_tok: Token = try d.getToken();
    if (name_tok.token_type != TokenType.Identifier) {
        return AstError.Unexpected_Type;
    }
    d.advance();

    const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    n.node_type = ASTNodeType.EnumDeclaration;
    n.token = name_tok;
    n.is_pub = is_pub;
    n.children = try ast_utils.createChildList(allocator);

    // optional backing type:  enum Flags: u8 { ... }
    if (d.hasMore()) {
        const maybe_colon: Token = try d.getToken();
        if (maybe_colon.token_type == TokenType.Colon) {
            d.advance(); // eat ':'
            n.left = try parseTypeNode(allocator, d); // store backing type on .left
        }
    }

    // Traits implementation: ~> TraitName
    if (d.hasMore()) {
        const maybe_tilde: Token = try d.getToken();
        if (maybe_tilde.token_type == TokenType.TildeArrow) {
            d.advance(); // eat ~>
            const trait_name: Token = try d.getToken();
            if (trait_name.token_type == TokenType.Identifier) {
                const trait_node: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
                trait_node.node_type = ASTNodeType.Identifier;
                trait_node.token = trait_name;
                n.left = trait_node; // attach trait implementation
                d.advance(); // eat trait name
            } else {
                d.setError("Expected trait name after ~>", trait_name);
                return AstError.Unexpected_Type;
            }

            // Multiple traits `~> TraitA, TraitB`
            while (d.hasMore()) {
                const comma: Token = try d.getToken();
                if (comma.token_type == TokenType.Comma) {
                    d.advance();
                    const nxt_trait: Token = try d.getToken();
                    if (nxt_trait.token_type == TokenType.Identifier) d.advance();
                    // we could chain these, but for now we just parse them out
                } else {
                    break;
                }
            }
        }
    }

    const lb: Token = try d.getToken();
    if (lb.token_type != TokenType.LeftBrace) return AstError.Unexpected_Type;
    d.advance(); // {

    var guard: usize = 0;
    while (d.hasMore()) {
        guard += 1;
        if (guard >= MAX_LOOP) return AstError.Infinite_While_Loop;
        const cur: Token = try d.getToken();
        if (cur.token_type == TokenType.RightBrace) {
            d.advance();
            break;
        }

        if (cur.token_type == TokenType.Func) {
            const m: *ASTNode = try parseFuncDecl(allocator, d, false);
            n.children.?.append(allocator.*, m) catch return AstError.Out_Of_Memory;
        } else if (cur.token_type == TokenType.Identifier) {
            const field: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            field.node_type = ASTNodeType.EnumField;
            field.token = cur;
            d.advance();

            const nxt = d.peekToken(0);
            if (nxt != null and nxt.?.token_type == TokenType.Equals) {
                d.advance(); // =
                const c_expr = try expr_mod.parseBinaryExpr(allocator, d, 0);
                field.right = c_expr;
            } else if (nxt != null and nxt.?.token_type == TokenType.LeftParen and nxt.?.value[0] == '(') {
                // fallback for some patterns
                d.token_index -= 1;
                const m: *ASTNode = try parseFuncDecl(allocator, d, false);
                n.children.?.append(allocator.*, m) catch return AstError.Out_Of_Memory;
            }

            n.children.?.append(allocator.*, field) catch return AstError.Out_Of_Memory;
            const comma: Token = try d.getToken();
            if (comma.token_type == TokenType.Comma) d.advance();
        } else {
            d.advance();
        }
    }
    return n;
}

fn parseUnion(allocator: *Allocator, d: *ASTData, is_pub: bool) AstError!*ASTNode {
    d.error_function = "parseUnion";
    d.advance(); // eat 'union'

    const name_tok: Token = try d.getToken();
    if (name_tok.token_type != TokenType.Identifier) {
        return AstError.Unexpected_Type;
    }
    d.advance();

    const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    n.node_type = ASTNodeType.UnionDeclaration;
    n.token = name_tok;
    n.is_pub = is_pub;
    n.children = try ast_utils.createChildList(allocator);

    const lb: Token = try d.getToken();
    if (lb.token_type != TokenType.LeftBrace) return AstError.Unexpected_Type;
    d.advance(); // {

    var guard: usize = 0;
    while (d.hasMore()) {
        guard += 1;
        if (guard >= MAX_LOOP) return AstError.Infinite_While_Loop;
        const cur: Token = try d.getToken();
        if (cur.token_type == TokenType.RightBrace) {
            d.advance();
            break;
        }

        if (cur.token_type == TokenType.Identifier) {
            const field: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            field.node_type = ASTNodeType.UnionField;
            field.token = cur;
            d.advance();

            const nxt = d.peekToken(0);
            if (nxt != null and nxt.?.token_type == TokenType.LeftParen) {
                // tuple-style variant: Name(Type) — e.g. Code(i32)
                d.advance(); // eat '('
                const tp_n: *ASTNode = try parseTypeNode(allocator, d);
                field.left = tp_n;
                if (d.hasMore()) {
                    const rp: Token = try d.getToken();
                    if (rp.token_type == TokenType.RightParen) d.advance();
                }
            } else if (nxt != null and nxt.?.token_type == TokenType.Colon) {
                // record-style variant: Name: Type  (C-union style)
                d.advance(); // eat ':'
                field.left = try parseTypeNode(allocator, d);
            } else if (nxt != null and nxt.?.token_type == TokenType.LeftBrace) {
                // struct-variant: Name { field: Type, ... }
                d.advance(); // eat '{'
                field.children = try ast_utils.createChildList(allocator);
                var sg: usize = 0;
                while (d.hasMore()) {
                    sg += 1;
                    if (sg >= MAX_LOOP) break;
                    const sc: Token = try d.getToken();
                    if (sc.token_type == TokenType.RightBrace) {
                        d.advance();
                        break;
                    }
                    if (sc.token_type == TokenType.Comma) {
                        d.advance();
                        continue;
                    }
                    if (sc.token_type == TokenType.Identifier) {
                        const peek2 = d.peekToken(1);
                        if (peek2 != null and peek2.?.token_type == TokenType.Colon) {
                            d.advance(); // name
                            d.advance(); // ':'
                            const ft = try parseTypeNode(allocator, d);
                            const sf: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
                            sf.node_type = ASTNodeType.StructField;
                            sf.token = sc;
                            sf.left = ft;
                            field.children.?.append(allocator.*, sf) catch return AstError.Out_Of_Memory;
                            if (d.hasMore()) {
                                const c2 = try d.getToken();
                                if (c2.token_type == TokenType.Comma) d.advance();
                            }
                        } else {
                            d.advance();
                        }
                    } else {
                        d.advance();
                    }
                }
            }

            n.children.?.append(allocator.*, field) catch return AstError.Out_Of_Memory;
            if (d.hasMore()) {
                const comma: Token = try d.getToken();
                if (comma.token_type == TokenType.Comma) d.advance();
            }
        } else if (cur.token_type == TokenType.Func) {
            const m: *ASTNode = try parseFuncDecl(allocator, d, false);
            n.children.?.append(allocator.*, m) catch return AstError.Out_Of_Memory;
        } else {
            d.advance();
        }
    }
    return n;
}

fn parseErrorMap(allocator: *Allocator, d: *ASTData) AstError!*ASTNode {
    d.error_function = "parseErrorMap";
    d.advance(); // eat 'error'
    const name_tok: Token = try d.getToken();
    d.advance();
    const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    n.node_type = ASTNodeType.ErrorDeclaration;
    n.token = name_tok;
    n.children = try ast_utils.createChildList(allocator);

    const lb: Token = try d.getToken();
    if (lb.token_type == TokenType.LeftBrace) d.advance();

    var guard: usize = 0;
    while (d.hasMore()) {
        guard += 1;
        if (guard >= MAX_LOOP) return AstError.Infinite_While_Loop;
        const cur: Token = try d.getToken();
        if (cur.token_type == TokenType.RightBrace) {
            d.advance();
            break;
        }
        if (cur.token_type == TokenType.Identifier) {
            const err_field: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            err_field.node_type = ASTNodeType.ErrorField;
            err_field.token = cur;
            n.children.?.append(allocator.*, err_field) catch return AstError.Out_Of_Memory;
            d.advance();
            const comma: Token = try d.getToken();
            if (comma.token_type == TokenType.Comma) d.advance();
        } else {
            d.advance();
        }
    }
    return n;
}

fn parseTypeAlias(allocator: *Allocator, d: *ASTData, is_pub: bool) AstError!*ASTNode {
    d.error_function = "parseTypeAlias";
    d.advance(); // eat 'type'
    const name_tok: Token = try d.getToken();
    d.advance(); // eat name
    const eq: Token = try d.getToken();
    if (eq.token_type == TokenType.Equals) d.advance();
    const tp: Token = try d.getToken();
    d.advance(); // eat type

    const tn: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    tn.node_type = ASTNodeType.VarType;
    tn.token = tp;

    const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    n.node_type = ASTNodeType.TypeAliasDeclaration;
    n.token = name_tok;
    n.left = tn;
    n.is_pub = is_pub;
    return n;
}

fn parseModule(allocator: *Allocator, d: *ASTData) AstError!*ASTNode {
    d.error_function = "parseModule";
    d.advance(); // mod
    const name_tok: Token = try d.getToken();
    d.advance(); // name
    consumeSemi(d);

    const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    n.node_type = ASTNodeType.ModuleDeclaration;
    n.token = name_tok;
    return n;
}

fn parseUse(allocator: *Allocator, d: *ASTData) AstError!*ASTNode {
    d.error_function = "parseUse";
    d.advance(); // eat 'use'

    // Build the full dotted path:  std . io  =>  "std.io"
    // The lexer produces Identifier and Dot tokens separately.
    var full_path = std.ArrayList(u8).initCapacity(allocator.*, 32) catch return AstError.Out_Of_Memory;
    var guard: usize = 0;
    while (d.hasMore()) {
        guard += 1;
        if (guard >= MAX_LOOP) break;
        const cur: Token = try d.getToken();
        // stop at anything that can't be part of a path
        if (cur.token_type == TokenType.Semicolon or
            cur.token_type == TokenType.RightBrace or
            tok_utils.isKeyword(cur.token_type))
        {
            break;
        }
        if (cur.token_type == TokenType.Dot) {
            full_path.append(allocator.*, '.') catch return AstError.Out_Of_Memory;
            d.advance();
            continue;
        }
        if (cur.token_type == TokenType.Identifier) {
            full_path.appendSlice(allocator.*, cur.value) catch return AstError.Out_Of_Memory;
            d.advance();
            continue;
        }
        break; // anything else terminates the path
    }
    consumeSemi(d);

    const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    n.node_type = ASTNodeType.UseDeclaration;
    const final_path = full_path.toOwnedSlice(allocator.*) catch return AstError.Out_Of_Memory;
    n.token = Token{ .token_type = TokenType.Identifier, .value = final_path, .line = 0, .character = 0 };
    return n;
}

fn parseBehave(allocator: *Allocator, d: *ASTData) AstError!*ASTNode {
    d.error_function = "parseBehave";
    d.advance(); // eat 'behave'
    const name_tok: Token = try d.getToken();
    d.advance();

    const n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    n.node_type = ASTNodeType.BehaveDeclaration;
    n.token = name_tok;
    n.children = try ast_utils.createChildList(allocator);

    const lb: Token = try d.getToken();
    if (lb.token_type == TokenType.LeftBrace) d.advance();

    var guard: usize = 0;
    while (d.hasMore()) {
        guard += 1;
        if (guard >= MAX_LOOP) return AstError.Infinite_While_Loop;
        const cur: Token = try d.getToken();
        if (cur.token_type == TokenType.RightBrace) {
            d.advance();
            break;
        }

        if (cur.token_type == TokenType.Func) {
            const m: *ASTNode = try parseFuncDecl(allocator, d, false);
            n.children.?.append(allocator.*, m) catch return AstError.Out_Of_Memory;
        } else if (cur.token_type == TokenType.Identifier and std.mem.eql(u8, cur.value, "needs")) {
            d.advance(); // needs
            const field_name: Token = try d.getToken();
            d.advance();
            const col: Token = try d.getToken();
            if (col.token_type == TokenType.Colon) d.advance();
            const type_tok: Token = try d.getToken();
            d.advance();

            const req_n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            req_n.node_type = ASTNodeType.StructField;
            req_n.token = field_name;
            const t_n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            t_n.node_type = ASTNodeType.VarType;
            t_n.token = type_tok;
            req_n.left = t_n;
            n.children.?.append(allocator.*, req_n) catch return AstError.Out_Of_Memory;
        } else if (cur.token_type == TokenType.Identifier) {
            const nx = d.peekToken(0);
            if (nx != null and nx.?.token_type == TokenType.LeftParen) {
                _ = try d.getToken();
                d.token_list.items[d.token_index - 1] = Token{ .token_type = TokenType.Func, .value = "func", .line = cur.line, .character = cur.character };
                d.token_index -= 1; // rewind
                const m: *ASTNode = try parseFuncDecl(allocator, d, false);
                n.children.?.append(allocator.*, m) catch return AstError.Out_Of_Memory;
            } else {
                d.advance();
            }
        } else {
            d.advance();
        }
    }
    return n;
}

fn parseExt(allocator: *Allocator, d: *ASTData) AstError!*ASTNode {
    d.error_function = "parseExt";
    d.advance(); // ext
    const fn_tok: Token = try d.getToken();
    if (fn_tok.token_type == TokenType.Func) {
        const m: *ASTNode = try parseFuncDecl(allocator, d, false);
        m.node_type = ASTNodeType.ExtDeclaration;
        return m;
    }
    d.setError("Expected func after ext", fn_tok);
    return AstError.Unexpected_Type;
}

// ── defer, try, catch, match ──────────────────────────────────────────

fn parseDefer(allocator: *Allocator, d: *ASTData) AstError!*ASTNode {
    d.error_function = "parseDefer";
    const tok: Token = try d.getToken();
    d.advance(); // eat defer

    const stmt: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    stmt.node_type = ASTNodeType.DeferStatement;
    stmt.token = tok;

    const s2: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    s2.node_type = ASTNodeType.Block;
    s2.children = try ast_utils.createChildList(allocator);

    // just treat the rest of the line or `{}` block as a statement to defer
    const peek: Token = try d.getToken();
    if (peek.token_type == TokenType.LeftBrace) {
        stmt.left = try parseBlock(allocator, d);
    } else {
        try processStatement(allocator, d, s2);
        stmt.left = s2;
    }
    return stmt;
}

fn parseMatch(allocator: *Allocator, d: *ASTData) AstError!*ASTNode {
    d.error_function = "parseMatch";
    const tok: Token = try d.getToken();
    d.advance(); // match

    const expr = try expr_mod.parseBinaryExpr(allocator, d, 0);

    const match_node: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
    match_node.node_type = ASTNodeType.MatchStatement;
    match_node.token = tok;
    match_node.left = expr;
    match_node.children = try ast_utils.createChildList(allocator);

    const lb: Token = try d.getToken();
    if (lb.token_type == TokenType.LeftBrace) d.advance();

    var guard: usize = 0;
    while (d.hasMore()) {
        guard += 1;
        if (guard >= MAX_LOOP) return AstError.Infinite_While_Loop;
        const cur: Token = try d.getToken();
        if (cur.token_type == TokenType.RightBrace) {
            d.advance();
            break;
        }

        // Pattern => Body
        const case_node: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
        case_node.node_type = ASTNodeType.MatchCase;

        // This could be Enum.Item or Number or anything!
        // We'll read expressions up to =>
        if (cur.token_type == TokenType.Else) {
            case_node.token = cur;
            d.advance();
        } else {
            const c_expr = try expr_mod.parseBinaryExpr(allocator, d, 0);
            case_node.left = c_expr;
        }

        const arr: Token = try d.getToken();
        if (arr.token_type == TokenType.Arrow or std.mem.eql(u8, arr.value, "=>")) {
            d.advance(); // =>
        } else if (arr.token_type == TokenType.Equals and d.peekToken(1) != null and d.peekToken(1).?.token_type == TokenType.GreaterThan) {
            d.advance();
            d.advance(); // = > handled
        }

        const b_peek: Token = try d.getToken();
        const body_n: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
        body_n.node_type = ASTNodeType.MatchBody;
        if (b_peek.token_type == TokenType.LeftBrace) {
            body_n.left = try parseBlock(allocator, d);
        } else {
            const blk: *ASTNode = try ast_utils.createDefaultAstNode(allocator);
            blk.node_type = ASTNodeType.Block;
            blk.children = try ast_utils.createChildList(allocator);
            try processStatement(allocator, d, blk);
            body_n.left = blk;
        }
        case_node.right = body_n;

        match_node.children.?.append(allocator.*, case_node) catch return AstError.Out_Of_Memory;

        const comma: Token = try d.getToken();
        if (comma.token_type == TokenType.Comma) {
            d.advance();
        }
    }

    return match_node;
}
