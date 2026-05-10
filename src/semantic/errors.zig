const std = @import("std");

pub const SemanticError = error{
    UndeclaredVariable,
    AlreadyDeclared,
    ImmutableAssignment,
    ArgumentCountMismatch,
    InternalError,
    OutOfMemory,
};
