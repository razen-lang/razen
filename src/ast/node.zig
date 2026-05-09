const std = @import("std");
const lexer = @import("../lexer/lexer.zig");
const Token = lexer.Token;

/// All the kinds of AST nodes Razen can produce.
pub const ASTNodeType = enum {
    Invalid,

    // ── Literals ──────────────────────────────────────────────────────────
    IntegerLiteral,
    FloatLiteral,
    StringLiteral,
    CharLiteral,
    BoolLiteral,

    // ── Declarations ──────────────────────────────────────────────────────
    /// `name : type = expr;`  or  `name := expr;`  or  `mut name : type = expr;`
    VarDeclaration,
    /// `const NAME : type = expr;`
    ConstDeclaration,
    /// `func name(params) -> ret_type { body }`
    FunctionDeclaration,
    /// A single function parameter  `name: type`
    Parameter,
    Parameters, // list of Parameter nodes

    // ── Type nodes ────────────────────────────────────────────────────────
    VarType, // holds the token for a type keyword / identifier
    ReturnType,

    // ── Expressions ───────────────────────────────────────────────────────
    BinaryExpression, // a + b, a == b, …
    UnaryExpression, // -x, !x
    Identifier, // a named reference

    // ── Statements ────────────────────────────────────────────────────────
    ReturnStatement, // `ret expr`
    Assignment, // `name = expr` / `name += expr`

    // ── Block / body ──────────────────────────────────────────────────────
    Block, // { stmts… }

    // ── Control flow ──────────────────────────────────────────────────────
    IfStatement, // if cond { … } else { … }
    IfBody,
    ElseBody,
    LoopStatement, // loop { … }
    LoopBody,

    // ── Function call ─────────────────────────────────────────────────────
    FunctionCall, // name(args…)
    Argument, // single argument inside a call

    // ── Comments ──────────────────────────────────────────────────────────
    Comment,
};

/// A single node in the Razen AST.
/// Uses value semantics where possible (token is copied).
pub const ASTNode = struct {
    node_type: ASTNodeType = ASTNodeType.Invalid,

    /// The token that best represents this node (name, operator, literal…)
    token: ?Token = null,

    /// Left child (e.g. type in declaration, left operand in binary expr)
    left: ?*ASTNode = null,
    /// Middle child (e.g. condition in if, params list)
    middle: ?*ASTNode = null,
    /// Right child (e.g. value in declaration, right operand in binary expr)
    right: ?*ASTNode = null,
    /// Child list (e.g. function body statements, argument list)
    children: ?*std.ArrayList(*ASTNode) = null,

    // ── Flags ─────────────────────────────────────────────────────────────
    is_const: bool = false,
    is_mut: bool = false,
    is_global: bool = false,
    is_pub: bool = false,
};
