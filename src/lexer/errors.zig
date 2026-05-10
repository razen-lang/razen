// errors the lexer can produce while scanning the source
pub const ParseError = error{
    Code_Length_Is_Zero, // someone passed us an empty string
    Unterminated_String, // hit end of file before finding the closing "
    Unexpected_Value, // something turned up that we didn't expect
    Unterminated_Char, // char literal wasn't closed with a '
};

// internal-only — used when converting a signed index to usize
const UsizeConversionError = error{
    OutOfRange, // value was negative, can't cast to usize
};
