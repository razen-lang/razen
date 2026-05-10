const token = @import("../lexer/token.zig");
const TokenType = token.TokenType;

// ── type classification ───────────────────────────────────────────────────────

// checks if a token is one of the primitive/built-in type keywords
pub fn isVarType(tt: TokenType) bool {
    return switch (tt) {
        TokenType.I1,
        TokenType.I2,
        TokenType.I4,
        TokenType.I8,
        TokenType.I16,
        TokenType.I32,
        TokenType.I64,
        TokenType.I128,
        TokenType.Isize,
        TokenType.Int,
        TokenType.U1,
        TokenType.U2,
        TokenType.U4,
        TokenType.U8,
        TokenType.U16,
        TokenType.U32,
        TokenType.U64,
        TokenType.U128,
        TokenType.Usize,
        TokenType.Uint,
        TokenType.F16,
        TokenType.F32,
        TokenType.F64,
        TokenType.F128,
        TokenType.Float,
        TokenType.Bool,
        TokenType.Char,
        TokenType.Void,
        TokenType.Noret,
        TokenType.Any,
        TokenType.Str,
        TokenType.String,
        => true,
        else => false,
    };
}

// true for any signed or unsigned integer type
pub fn isIntegerType(tt: TokenType) bool {
    return switch (tt) {
        TokenType.I1,
        TokenType.I2,
        TokenType.I4,
        TokenType.I8,
        TokenType.I16,
        TokenType.I32,
        TokenType.I64,
        TokenType.I128,
        TokenType.Isize,
        TokenType.Int,
        TokenType.U1,
        TokenType.U2,
        TokenType.U4,
        TokenType.U8,
        TokenType.U16,
        TokenType.U32,
        TokenType.U64,
        TokenType.U128,
        TokenType.Usize,
        TokenType.Uint,
        => true,
        else => false,
    };
}

// true for float types
pub fn isFloatType(tt: TokenType) bool {
    return switch (tt) {
        TokenType.F16, TokenType.F32, TokenType.F64, TokenType.F128, TokenType.Float => true,
        else => false,
    };
}

// true for any number type — int or float
pub fn isNumericType(tt: TokenType) bool {
    return isIntegerType(tt) or isFloatType(tt);
}

// a "type token" covers all built-in types AND user-defined type names (identifiers)
pub fn isTypeToken(tt: TokenType) bool {
    return isVarType(tt) or tt == TokenType.Identifier;
}

// ── literal / value helpers ───────────────────────────────────────────────────

pub fn isLiteral(tt: TokenType) bool {
    return switch (tt) {
        TokenType.IntegerValue,
        TokenType.DecimalValue,
        TokenType.StringValue,
        TokenType.CharValue,
        TokenType.True,
        TokenType.False,
        => true,
        else => false,
    };
}

pub fn isKeyword(tt: TokenType) bool {
    return switch (tt) {
        TokenType.Type,
        TokenType.Enum,
        TokenType.Union,
        TokenType.Error,
        TokenType.Struct,
        TokenType.Behave,
        TokenType.Ext,
        TokenType.Func,
        TokenType.Pub,
        TokenType.Mod,
        TokenType.Use,
        TokenType.Const,
        TokenType.Mut,
        TokenType.If,
        TokenType.Else,
        TokenType.Match,
        TokenType.Loop,
        TokenType.Ret,
        TokenType.Break,
        TokenType.Skip,
        TokenType.Try,
        TokenType.Catch,
        TokenType.Defer,
        TokenType.Test,
        TokenType.True,
        TokenType.False,
        TokenType.Async,
        => true,
        else => false,
    };
}

// ── operator helpers ──────────────────────────────────────────────────────────

// true for anything that can sit between two expressions as a binary operator
pub fn isBinaryOperator(tt: TokenType) bool {
    return switch (tt) {
        TokenType.Plus,
        TokenType.Minus,
        TokenType.Star,
        TokenType.Slash,
        TokenType.Percent,
        TokenType.EqualsEquals,
        TokenType.NotEquals,
        TokenType.LessThan,
        TokenType.LessThanEquals,
        TokenType.GreaterThan,
        TokenType.GreaterThanEquals,
        TokenType.AndAnd,
        TokenType.OrOr,
        TokenType.And,
        TokenType.Or,
        TokenType.Caret,
        TokenType.ShiftLeft,
        TokenType.ShiftRight,
        TokenType.Catch,
        TokenType.Dot, // member access  a.b
        => true,
        else => false,
    };
}

// true for assignment operators: =, +=, -=, *=, /=, %=
pub fn isAssignmentOperator(tt: TokenType) bool {
    return switch (tt) {
        TokenType.Equals,
        TokenType.PlusEquals,
        TokenType.MinusEquals,
        TokenType.StarEquals,
        TokenType.SlashEquals,
        TokenType.PercentEquals,
        => true,
        else => false,
    };
}

// ── operator precedence ───────────────────────────────────────────────────────
//
// Higher number = binds tighter.
//
//   1  ||
//   2  &&
//   3  == !=
//   4  < <= > >=
//   5  | ^
//   6  &
//   7  << >>
//   8  + -
//   9  * / %
//
pub fn getPrecedence(tt: TokenType) usize {
    return switch (tt) {
        TokenType.Catch => 1,
        TokenType.OrOr => 2,
        TokenType.AndAnd => 3,
        TokenType.EqualsEquals, TokenType.NotEquals => 4,
        TokenType.LessThan, TokenType.LessThanEquals, TokenType.GreaterThan, TokenType.GreaterThanEquals => 5,
        TokenType.Or => 6,
        TokenType.Caret => 6,
        TokenType.And => 7,
        TokenType.ShiftLeft, TokenType.ShiftRight => 8,
        TokenType.Plus, TokenType.Minus => 9,
        TokenType.Star, TokenType.Slash, TokenType.Percent => 10,
        TokenType.Dot => 12, // member access binds tightest of all binary ops
        else => 0,
    };
}
