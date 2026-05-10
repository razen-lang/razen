const std = @import("std");

pub const ConvertError = error{
    Out_Of_Memory,
    No_AST_Nodes,
    Node_Is_Null,
    Invalid_Node_Type,
    Invalid_Var_Type,
    Invalid_Return_Type,
    Unimplemented_Node_Type,
    Internal_Error,
    Index_Out_Of_Range,
};
