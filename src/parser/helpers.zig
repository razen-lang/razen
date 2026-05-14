const token = @import("../lexer/token.zig");
const lexer = @import("../lexer/lexer.zig");
const TokenType = token.TokenType;
const twoSlicesAreTheSame = lexer.twoSlicesAreTheSame;

// maps a raw text slice to its corresponding TokenType
// works by checking the text against every known keyword, operator, type name, etc.
// if nothing matches, it falls through to number detection and then defaults to Identifier
pub fn getTokenType(source: []const u8) TokenType {

    // built-in types
    if (twoSlicesAreTheSame(source, token.I1)) return TokenType.I1;
    if (twoSlicesAreTheSame(source, token.I2)) return TokenType.I2;
    if (twoSlicesAreTheSame(source, token.I4)) return TokenType.I4;
    if (twoSlicesAreTheSame(source, token.I8)) return TokenType.I8;
    if (twoSlicesAreTheSame(source, token.I16)) return TokenType.I16;
    if (twoSlicesAreTheSame(source, token.I32)) return TokenType.I32;
    if (twoSlicesAreTheSame(source, token.I64)) return TokenType.I64;
    if (twoSlicesAreTheSame(source, token.I128)) return TokenType.I128;
    if (twoSlicesAreTheSame(source, token.ISIZE)) return TokenType.Isize;
    if (twoSlicesAreTheSame(source, token.INT)) return TokenType.Int;
    if (twoSlicesAreTheSame(source, token.U1)) return TokenType.U1;
    if (twoSlicesAreTheSame(source, token.U2)) return TokenType.U2;
    if (twoSlicesAreTheSame(source, token.U4)) return TokenType.U4;
    if (twoSlicesAreTheSame(source, token.U8)) return TokenType.U8;
    if (twoSlicesAreTheSame(source, token.U16)) return TokenType.U16;
    if (twoSlicesAreTheSame(source, token.U32)) return TokenType.U32;
    if (twoSlicesAreTheSame(source, token.U64)) return TokenType.U64;
    if (twoSlicesAreTheSame(source, token.U128)) return TokenType.U128;
    if (twoSlicesAreTheSame(source, token.USIZE)) return TokenType.Usize;
    if (twoSlicesAreTheSame(source, token.UINT)) return TokenType.Uint;
    if (twoSlicesAreTheSame(source, token.F16)) return TokenType.F16;
    if (twoSlicesAreTheSame(source, token.F32)) return TokenType.F32;
    if (twoSlicesAreTheSame(source, token.F64)) return TokenType.F64;
    if (twoSlicesAreTheSame(source, token.F128)) return TokenType.F128;
    if (twoSlicesAreTheSame(source, token.FLOAT)) return TokenType.Float;
    if (twoSlicesAreTheSame(source, token.BOOL)) return TokenType.Bool;
    if (twoSlicesAreTheSame(source, token.CHAR)) return TokenType.Char;
    if (twoSlicesAreTheSame(source, token.VOID)) return TokenType.Void;
    if (twoSlicesAreTheSame(source, token.NORET)) return TokenType.Noret;
    if (twoSlicesAreTheSame(source, token.ANY)) return TokenType.Any;
    if (twoSlicesAreTheSame(source, token.STR)) return TokenType.Str;
    if (twoSlicesAreTheSame(source, token.STRING)) return TokenType.String;

    //keywords
    if (twoSlicesAreTheSame(source, token.TYPE)) return TokenType.Type;
    if (twoSlicesAreTheSame(source, token.ENUM)) return TokenType.Enum;
    if (twoSlicesAreTheSame(source, token.UNION)) return TokenType.Union;
    if (twoSlicesAreTheSame(source, token.ERROR)) return TokenType.Error;
    if (twoSlicesAreTheSame(source, token.STRUCT)) return TokenType.Struct;
    if (twoSlicesAreTheSame(source, token.BEHAVE)) return TokenType.Behave;
    if (twoSlicesAreTheSame(source, token.EXT)) return TokenType.Ext;
    if (twoSlicesAreTheSame(source, token.FUNC)) return TokenType.Func;
    if (twoSlicesAreTheSame(source, token.PUB)) return TokenType.Pub;
    if (twoSlicesAreTheSame(source, token.MOD)) return TokenType.Mod;
    if (twoSlicesAreTheSame(source, token.USE)) return TokenType.Use;
    if (twoSlicesAreTheSame(source, token.CONST)) return TokenType.Const;
    if (twoSlicesAreTheSame(source, token.MUT)) return TokenType.Mut;
    if (twoSlicesAreTheSame(source, token.IF)) return TokenType.If;
    if (twoSlicesAreTheSame(source, token.ELSE)) return TokenType.Else;
    if (twoSlicesAreTheSame(source, token.MATCH)) return TokenType.Match;
    if (twoSlicesAreTheSame(source, token.LOOP)) return TokenType.Loop;
    if (twoSlicesAreTheSame(source, token.RET)) return TokenType.Ret;
    if (twoSlicesAreTheSame(source, token.BREAK)) return TokenType.Break;
    if (twoSlicesAreTheSame(source, token.SKIP)) return TokenType.Skip;
    if (twoSlicesAreTheSame(source, token.TRY)) return TokenType.Try;
    if (twoSlicesAreTheSame(source, token.CATCH)) return TokenType.Catch;
    if (twoSlicesAreTheSame(source, token.DEFER)) return TokenType.Defer;
    if (twoSlicesAreTheSame(source, token.TEST)) return TokenType.Test;
    if (twoSlicesAreTheSame(source, token.TRUE)) return TokenType.True;
    if (twoSlicesAreTheSame(source, token.FALSE)) return TokenType.False;
    if (twoSlicesAreTheSame(source, token.ASYNC)) return TokenType.Async;
    if (twoSlicesAreTheSame(source, token.NEEDS)) return TokenType.Needs;

    // operators
    if (twoSlicesAreTheSame(source, token.EQUALS)) return TokenType.Equals;
    if (twoSlicesAreTheSame(source, token.COLON_EQUALS)) return TokenType.ColonEquals;
    if (twoSlicesAreTheSame(source, token.PLUS_EQUALS)) return TokenType.PlusEquals;
    if (twoSlicesAreTheSame(source, token.MINUS_EQUALS)) return TokenType.MinusEquals;
    if (twoSlicesAreTheSame(source, token.STAR_EQUALS)) return TokenType.StarEquals;
    if (twoSlicesAreTheSame(source, token.SLASH_EQUALS)) return TokenType.SlashEquals;
    if (twoSlicesAreTheSame(source, token.PERCENT_EQUALS)) return TokenType.PercentEquals;
    if (twoSlicesAreTheSame(source, token.PLUS)) return TokenType.Plus;
    if (twoSlicesAreTheSame(source, token.MINUS)) return TokenType.Minus;
    if (twoSlicesAreTheSame(source, token.STAR)) return TokenType.Star;
    if (twoSlicesAreTheSame(source, token.SLASH)) return TokenType.Slash;
    if (twoSlicesAreTheSame(source, token.PERCENT)) return TokenType.Percent;
    if (twoSlicesAreTheSame(source, token.EQUALS_EQUALS)) return TokenType.EqualsEquals;
    if (twoSlicesAreTheSame(source, token.NOT_EQUALS)) return TokenType.NotEquals;
    if (twoSlicesAreTheSame(source, token.LESS_THAN)) return TokenType.LessThan;
    if (twoSlicesAreTheSame(source, token.LESS_THAN_EQUALS)) return TokenType.LessThanEquals;
    if (twoSlicesAreTheSame(source, token.GREATER_THAN)) return TokenType.GreaterThan;
    if (twoSlicesAreTheSame(source, token.GREATER_THAN_EQUALS)) return TokenType.GreaterThanEquals;
    if (twoSlicesAreTheSame(source, token.EXPLAINATION_MARK)) return TokenType.ExclamationMark;
    if (twoSlicesAreTheSame(source, token.AND_AND)) return TokenType.AndAnd;
    if (twoSlicesAreTheSame(source, token.OR_OR)) return TokenType.OrOr;
    if (twoSlicesAreTheSame(source, token.AND)) return TokenType.And;
    if (twoSlicesAreTheSame(source, token.OR)) return TokenType.Or;
    if (twoSlicesAreTheSame(source, token.CARET)) return TokenType.Caret;
    if (twoSlicesAreTheSame(source, token.TILDE)) return TokenType.Tilde;
    if (twoSlicesAreTheSame(source, token.SHIFT_LEFT)) return TokenType.ShiftLeft;
    if (twoSlicesAreTheSame(source, token.SHIFT_RIGHT)) return TokenType.ShiftRight;
    if (twoSlicesAreTheSame(source, token.DOT)) return TokenType.Dot;
    if (twoSlicesAreTheSame(source, token.COMMA)) return TokenType.Comma;
    if (twoSlicesAreTheSame(source, token.SEMICOLON)) return TokenType.Semicolon;
    if (twoSlicesAreTheSame(source, token.COLON)) return TokenType.Colon;
    if (twoSlicesAreTheSame(source, token.QUESTION_MARK)) return TokenType.QuestionMark;
    if (twoSlicesAreTheSame(source, token.LEFT_PAREN)) return TokenType.LeftParen;
    if (twoSlicesAreTheSame(source, token.RIGHT_PAREN)) return TokenType.RightParen;
    if (twoSlicesAreTheSame(source, token.LEFT_BRACE)) return TokenType.LeftBrace;
    if (twoSlicesAreTheSame(source, token.RIGHT_BRACE)) return TokenType.RightBrace;
    if (twoSlicesAreTheSame(source, token.LEFT_BRACKET)) return TokenType.LeftBracket;
    if (twoSlicesAreTheSame(source, token.RIGHT_BRACKET)) return TokenType.RightBracket;
    if (twoSlicesAreTheSame(source, token.ARROW)) return TokenType.Arrow;
    if (twoSlicesAreTheSame(source, token.BIG_ARROW)) return TokenType.BigArrow;
    if (twoSlicesAreTheSame(source, token.TILDE_ARROW)) return TokenType.TildeArrow;
    if (twoSlicesAreTheSame(source, token.DOT_DOT_DOT)) return TokenType.DotDotDot;
    if (twoSlicesAreTheSame(source, token.DOT_DOT)) return TokenType.DotDot;
    if (twoSlicesAreTheSame(source, token.DOT_DOT_EQUALS)) return TokenType.DotDotEquals;
    if (twoSlicesAreTheSame(source, token.AT)) return TokenType.At;

    // number literals
    if (isInteger(source)) return TokenType.IntegerValue;
    if (isDecimal(source)) return TokenType.DecimalValue;

    // string / char value (already surrounded by quotes at this point)
    if (lexer.contains(source, '"')) return TokenType.StringValue;
    if (lexer.contains(source, '\'')) return TokenType.CharValue;

    // nothing else matched, must be a user-defined name
    return TokenType.Identifier;
}

// checks if a character is a recognised operator starter
pub fn isOperator(char: u8) bool {
    const LENGTH: usize = token.OPERATORS.len;
    for (0..LENGTH) |i| {
        if (char == token.OPERATORS[i]) {
            return true;
        }
    }
    return false;
}

// checks if a character is a separator (brackets, punctuation, whitespace control chars)
pub fn isSeparator(char: u8) bool {
    const LENGTH: usize = token.SEPERATORS.len;
    for (0..LENGTH) |i| {
        if (char == token.SEPERATORS[i]) {
            return true;
        }
    }
    return false;
}

// returns true if the whole slice looks like an integer (optionally negative)
pub fn isInteger(source: []const u8) bool {
    const LENGTH: usize = source.len;

    for (0..LENGTH) |i| {
        const char: u8 = source[i];
        if (source[i] == '-') {
            // a leading minus is fine, but not mid-number
            if (i != 0) {
                return false;
            }
            continue;
        }
        if (isDigit(char) == false) {
            return false;
        }
    }
    return true;
}

// returns true if the slice looks like a decimal number (optionally negative, has a dot)
pub fn isDecimal(source: []const u8) bool {
    const LENGTH: usize = source.len;

    for (0..LENGTH) |i| {
        const char: u8 = source[i];
        if (source[i] == '-') {
            if (i != 0) {
                return false;
            }
            continue;
        }
        if (source[i] == '.') {
            continue; // dots are allowed in decimals
        }
        if (isDigit(char) == false) {
            return false;
        }
    }
    return true;
}

// true for a-z, A-Z, 0-9
pub fn isLetterOrDigit(char: u8) bool {
    switch (char) {
        'a'...'z', 'A'...'Z', '0'...'9' => return true,
        else => return false,
    }
}

// true for 0-9
pub fn isDigit(char: u8) bool {
    switch (char) {
        '0'...'9' => return true,
        else => return false,
    }
}
