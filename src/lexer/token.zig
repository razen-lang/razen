pub const TokenType = enum {
    Identifier,
    IntegerValue,
    DecimalValue,
    CharValue,
    StringValue,
    /// Types
    I1, // i1
    I2, // i2
    I4, // i4
    I8, // i8
    I16, // i16
    I32, // i32
    I64, // i64
    I128, // i128
    Isize, // isize
    Int, // int = i32
    U1, // u1
    U2, // u2
    U4, // u4
    U8, // u8
    U16, // u16
    U32, // u32
    U64, // u64
    U128, // u128
    Usize, // usize
    Uint, // uint = u32
    F16, // f16
    F32, // f32
    F64, // f64
    F128, // f128
    Float, // float = f32
    Bool, // bool
    Char, // char
    Void, // void (returns nothing)
    Noret, // noret (short for no return, like diverging functions)
    Any, // any (can hold any type of value)
    Str, // str (stacked string slice)
    String, // string (heap allocated string)
    /// Keywords
    Type, // type
    Enum, // enum
    Union, // union
    Error, // error
    Struct, // struct
    Behave, // behave (used for traits/interfaces)
    Ext, // ext (short for extern)
    Func, // func
    Pub, // pub (public visibility marker)
    Mod, // mod (module declaration)
    Use, // use (importing a module)
    Const, // const (immutable bindings)
    Mut, // mut (mutable bindings)
    If, // if
    Else, // else
    Match, // match (pattern matching)
    Loop, // loop (infinite or targeted loops)
    Ret, // ret (shorthand for return)
    Break, // break
    Skip, // skip (shorthand for continue)
    Try, // try
    Catch, // catch
    Defer, // defer
    Test, // test
    True, // true
    False, // false
    /// Operators and seperators : Symbols
    Comment, // comment
    EndComment, // end comment
    Equals, // =
    ColonEquals, // :=
    PlusEquals, // +=
    MinusEquals, // -=
    StarEquals, // *=
    SlashEquals, // /=
    PercentEquals, // %=
    Plus, // +
    Minus, // -
    Star, // *
    Slash, // /
    Percent, // %
    EqualsEquals, // ==
    NotEquals, // !=
    LessThan, // <
    LessThanEquals, // <=
    GreaterThan, // >
    GreaterThanEquals, // >=
    ExclamationMark, // !
    AndAnd, // &&
    OrOr, // ||
    And, // &
    Or, // |
    Caret, // ^
    Tilde, // ~
    ShiftLeft, // <<
    ShiftRight, // >>
    Dot, // .
    Comma, // ,
    Semicolon, // ;
    Colon, // :
    QuestionMark, // ?
    LeftParen, // (
    RightParen, // )
    LeftBrace, // {
    RightBrace, // }
    LeftBracket, // [
    RightBracket, // ]
    Arrow, // ->
    BigArrow, // =>
    TildeArrow, // ~>
    DotDotDot, // ...
    DotDot, // ..
    DotDotEquals, // ..=
    At, // @
    NA, //invalid type
    EOF, // End of file
};

pub const OPERATORS = [_]u8{ '=', '+', '-', '*', '/', '%', '!', '&', '|', '^', '~', '<', '>', '?', '@', ':' };
pub const SEPERATORS = [_]u8{ ';', '(', ')', '{', '}', '[', ']', ',', '.', '\n', '\r', '\t', '\\' };

// Types
pub const I1 = "i1";
pub const I2 = "i2";
pub const I4 = "i4";
pub const I8 = "i8";
pub const I16 = "i16";
pub const I32 = "i32";
pub const I64 = "i64";
pub const I128 = "i128";
pub const ISIZE = "isize";
pub const INT = "int";
pub const U1 = "u1";
pub const U2 = "u2";
pub const U4 = "u4";
pub const U8 = "u8";
pub const U16 = "u16";
pub const U32 = "u32";
pub const U64 = "u64";
pub const U128 = "u128";
pub const USIZE = "usize";
pub const UINT = "uint";
pub const F16 = "f16";
pub const F32 = "f32";
pub const F64 = "f64";
pub const F128 = "f128";
pub const FLOAT = "float";
pub const BOOL = "bool";
pub const CHAR = "char";
pub const VOID = "void";
pub const NORET = "noret";
pub const ANY = "any";
pub const STR = "str";
pub const STRING = "string";

// Keywords
pub const TYPE = "type";
pub const ENUM = "enum";
pub const UNION = "union";
pub const ERROR = "error";
pub const STRUCT = "struct";
pub const BEHAVE = "behave";
pub const EXT = "ext";
pub const FUNC = "func";
pub const PUB = "pub";
pub const MOD = "mod";
pub const USE = "use";
pub const CONST = "const";
pub const MUT = "mut";
pub const IF = "if";
pub const ELSE = "else";
pub const MATCH = "match";
pub const LOOP = "loop";
pub const RET = "ret";
pub const BREAK = "break";
pub const SKIP = "skip";
pub const TRY = "try";
pub const CATCH = "catch";
pub const DEFER = "defer";
pub const TEST = "test";
pub const TRUE = "true";
pub const FALSE = "false";

// Operators
pub const EQUALS = "=";
pub const COLON_EQUALS = ":=";
pub const PLUS_EQUALS = "+=";
pub const MINUS_EQUALS = "-=";
pub const STAR_EQUALS = "*=";
pub const SLASH_EQUALS = "/=";
pub const PERCENT_EQUALS = "%=";
pub const PLUS = "+";
pub const MINUS = "-";
pub const STAR = "*";
pub const SLASH = "/";
pub const PERCENT = "%";
pub const EQUALS_EQUALS = "==";
pub const NOT_EQUALS = "!=";
pub const LESS_THAN = "<";
pub const LESS_THAN_EQUALS = "<=";
pub const GREATER_THAN = ">";
pub const GREATER_THAN_EQUALS = ">=";
pub const EXPLAINATION_MARK = "!";
pub const AND_AND = "&&";
pub const OR_OR = "||";
pub const AND = "&";
pub const OR = "|";
pub const CARET = "^";
pub const TILDE = "~";
pub const SHIFT_LEFT = "<<";
pub const SHIFT_RIGHT = ">>";
pub const DOT = ".";
pub const COMMA = ",";
pub const SEMICOLON = ";";
pub const COLON = ":";
pub const QUESTION_MARK = "?";
pub const LEFT_PAREN = "(";
pub const RIGHT_PAREN = ")";
pub const LEFT_BRACE = "{";
pub const RIGHT_BRACE = "}";
pub const LEFT_BRACKET = "[";
pub const RIGHT_BRACKET = "]";
pub const ARROW = "->";
pub const BIG_ARROW = "=>";
pub const TILDE_ARROW = "~>";
pub const DOT_DOT_DOT = "...";
pub const DOT_DOT = "..";
pub const DOT_DOT_EQUALS = "..=";
pub const AT = "@";
