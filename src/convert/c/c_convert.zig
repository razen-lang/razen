const std = @import("std");
const node_mod = @import("../../ast/node.zig");
const convert_data = @import("../convert_data.zig");
const errors = @import("../errors.zig");
const lexer = @import("../../lexer/lexer.zig");

const c_function = @import("c_function.zig");

const print = std.debug.print;
const ASTNode = node_mod.ASTNode;
const ASTNodeType = node_mod.ASTNodeType;
const ConvertData = convert_data.ConvertData;
const ConvertError = errors.ConvertError;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringBuilder = convert_data.StringBuilder;

pub fn convert(allocator: *Allocator, ast_nodes: *ArrayList(*ASTNode), source: []const u8) ConvertError![]u8 {
    _ = source;
    print("\t{s}Converting AST to C{s}\t\t\t", .{ lexer.GREY, lexer.RESET });

    var generated_code = StringBuilder.init(allocator.*) catch return ConvertError.Out_Of_Memory;

    var data = ConvertData{
        .ast_nodes = ast_nodes,
        .generated_code = &generated_code,
    };

    data.error_function = "convert";

    if (ast_nodes.items.len == 0) {
        return ConvertError.No_AST_Nodes;
    }

    try writeIncludes(allocator, &data);

    while (data.node_index < ast_nodes.items.len) {
        const pre_index = data.node_index;
        
        try processGlobalNode(allocator, &data);

        // Nudge forward if we didn't advance
        if (pre_index == data.node_index) {
            data.node_index += 1;
        }
    }

    print("{s}Done{s}\n", .{ lexer.CYAN, lexer.RESET });

    const generated_output = generated_code.toOwnedSlice(allocator) catch return ConvertError.Out_Of_Memory;
    return generated_output;
}

fn writeIncludes(allocator: *Allocator, data: *ConvertData) ConvertError!void {
    const stdint = "#include <stdint.h>\n";
    const stdbool = "#include <stdbool.h>\n\n";

    try data.appendCode(allocator, stdint);
    try data.appendCode(allocator, stdbool);
}

fn processGlobalNode(allocator: *Allocator, data: *ConvertData) ConvertError!void {
    data.error_function = "processGlobalNode";

    const node = data.getNode();
    if (node == null) return ConvertError.Node_Is_Null;

    switch (node.?.node_type) {
        ASTNodeType.FunctionDeclaration => try c_function.processFunctionDeclaration(allocator, data, node.?),
        ASTNodeType.ConstDeclaration, ASTNodeType.VarDeclaration => {
            const c_declaration = @import("c_declaration.zig");
            try c_declaration.processDeclaration(allocator, data, node.?, true, false);
        },
        else => {
            // @TODO implementation for globals
        }
    }
}
