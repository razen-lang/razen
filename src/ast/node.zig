const std = @import("std");
const lexer = @import("../lexer/lexer.zig");
const Token = lexer.Token;

// Every kind of AST node Razen can produce.
pub const ASTNodeType = enum {
    Invalid,

    // ── values you write literally in code ────────────────────────────────
    IntegerLiteral,
    FloatLiteral,
    StringLiteral,
    CharLiteral,
    BoolLiteral,
    ArrayLiteral,
    ArrayType,

    // ── declarations ──────────────────────────────────────────────────────
    // name : type = expr;   or  name := expr;  or  mut name : type = expr;
    VarDeclaration,
    // const NAME : type = expr;
    ConstDeclaration,
    // type Name = type;
    TypeAliasDeclaration,
    // enum Name { ... }
    EnumDeclaration,
    EnumField,
    // struct Name { ... }
    StructDeclaration,
    StructField,
    // union Name { ... }
    UnionDeclaration,
    UnionField,
    // error Name { ... }
    ErrorDeclaration,
    ErrorField,
    // mod module;
    ModuleDeclaration,
    // use mod;
    UseDeclaration,
    // behave Trait { ... }
    BehaveDeclaration,
    // ext func ...
    ExtDeclaration,
    // @Annotation
    Annotation,

    // func name(params) -> ret_type { body }
    FunctionDeclaration,
    // a single function parameter  name: type
    Parameter,
    Parameters, // the whole list of parameters

    // ── type nodes ────────────────────────────────────────────────────────
    VarType, // holds the actual type keyword or identifier
    ReturnType,

    // ── expressions ───────────────────────────────────────────────────────
    BinaryExpression, // a + b, a == b, that kind of thing
    UnaryExpression, // -x, !x
    MemberAccess, // a.b — dot member access
    Identifier, // a name that refers to something
    BuiltinExpression, // @Builtin

    // ── statements ────────────────────────────────────────────────────────
    ReturnStatement, // ret expr
    Assignment, // name = expr  or  name += expr

    // ── block / body ──────────────────────────────────────────────────────
    Block, // { stmts… }

    // ── control flow ──────────────────────────────────────────────────────
    IfStatement, // if cond { … } else { … }
    IfBody,
    ElseBody,
    LoopStatement, // loop { … }
    LoopBody,
    MatchStatement, // match expr { ... }
    MatchCase,
    MatchBody,
    TryExpression, // try expr
    CatchExpression, // expr catch backup
    DeferStatement, // defer stmt

    // ── function calls ────────────────────────────────────────────────────
    FunctionCall, // name(args…)
    Argument, // one argument inside a call

    // ── comments ──────────────────────────────────────────────────────────
    Comment,
};

// One node in the Razen AST.
// Copies the token by value so we don't have to worry about lifetime.
pub const ASTNode = struct {
    node_type: ASTNodeType = ASTNodeType.Invalid,

    // the token that best represents this node (name, operator, literal, etc.)
    token: ?Token = null,

    // left child — usually: type in a declaration, left operand in a binary expr
    left: ?*ASTNode = null,
    // middle child — condition in if, params list in a function, etc.
    middle: ?*ASTNode = null,
    // right child — value in a declaration, right operand in a binary expr
    right: ?*ASTNode = null,
    // variable-length child list — function body statements, argument list, etc.
    children: ?*std.ArrayList(*ASTNode) = null,

    // ── flags ──────────────────────────────────────────────────────────────
    is_const: bool = false,
    is_mut: bool = false,
    is_global: bool = false,
    is_pub: bool = false,
    is_async: bool = false,
};
