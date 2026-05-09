const token = @import("../lexer/token.zig");
const TokenType = token.TokenType;

// ─────────────────────────────────────────────────────────────────────────────
// Type classification helpers
// ─────────────────────────────────────────────────────────────────────────────

/// True for any primitive / built-in type keyword.
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

/// True for integer-family types (signed + unsigned).
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

/// True for float-family types.
pub fn isFloatType(tt: TokenType) bool {
    return switch (tt) {
        TokenType.F16, TokenType.F32, TokenType.F64, TokenType.F128, TokenType.Float => true,
        else => false,
    };
}

/// True for any numeric type (int or float).
pub fn isNumericType(tt: TokenType) bool {
    return isIntegerType(tt) or isFloatType(tt);
}

/// A "type token" is a primitive type keyword OR an Identifier (custom type).
pub fn isTypeToken(tt: TokenType) bool {
    return isVarType(tt) or tt == TokenType.Identifier;
}

// ─────────────────────────────────────────────────────────────────────────────
// Literal / value helpers
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Operator helpers
// ─────────────────────────────────────────────────────────────────────────────

/// True for every token that can appear as a binary infix operator.
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
        => true,
        else => false,
    };
}

/// True for compound-assignment operators: +=, -=, *=, /=, %=
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

// ─────────────────────────────────────────────────────────────────────────────
// Precedence  (higher = tighter binding)
// ─────────────────────────────────────────────────────────────────────────────
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
        TokenType.OrOr => 1,
        TokenType.AndAnd => 2,
        TokenType.EqualsEquals, TokenType.NotEquals => 3,
        TokenType.LessThan, TokenType.LessThanEquals, TokenType.GreaterThan, TokenType.GreaterThanEquals => 4,
        TokenType.Or => 5,
        TokenType.Caret => 5,
        TokenType.And => 6,
        TokenType.ShiftLeft, TokenType.ShiftRight => 7,
        TokenType.Plus, TokenType.Minus => 8,
        TokenType.Star, TokenType.Slash, TokenType.Percent => 9,
        else => 0,
    };
}
