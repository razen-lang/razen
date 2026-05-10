const std = @import("std");
const node_mod = @import("../../ast/node.zig");
const convert_data = @import("../convert_data.zig");
const errors = @import("../errors.zig");
const lexer = @import("../../lexer/lexer.zig");

const c_function = @import("c_function.zig");
const c_struct = @import("c_struct.zig");
const c_enums = @import("c_enums.zig");
const c_unions = @import("c_unions.zig");

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

    // Bug 4+7: initialise new ConvertData fields
    var data = ConvertData{
        .ast_nodes = ast_nodes,
        .generated_code = &generated_code,
        .var_types = std.StringHashMap([]const u8).init(allocator.*),
        .deferred_stmts = std.ArrayList(*ASTNode).initCapacity(allocator.*, 0) catch return ConvertError.Out_Of_Memory,
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
    const stdbool = "#include <stdbool.h>\n";
    const razen_core = "#include \"razen_core.h\"\n\n";

    try data.appendCode(allocator, stdint);
    try data.appendCode(allocator, stdbool);
    try data.appendCode(allocator, razen_core);
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
        ASTNodeType.StructDeclaration => try c_struct.processStruct(allocator, data, node.?),
        ASTNodeType.BehaveDeclaration => try c_struct.processBehave(allocator, data, node.?),
        ASTNodeType.EnumDeclaration => try c_enums.processEnum(allocator, data, node.?),
        ASTNodeType.ErrorDeclaration => try c_enums.processErrorDecl(allocator, data, node.?),
        ASTNodeType.UnionDeclaration => try c_unions.processUnion(allocator, data, node.?),
        // Bug 6: ExtDeclaration is now handled properly in processFunctionDeclaration
        ASTNodeType.ExtDeclaration => try c_function.processFunctionDeclaration(allocator, data, node.?),
        ASTNodeType.ModuleDeclaration => {
            // C doesn't have modules, we'll emit a comment
            try data.appendCodeFmt(allocator, "// Module {s}\n", .{node.?.token.?.value});
        },
        ASTNodeType.UseDeclaration => {
            // use std.io -> #include <std.io.h>
            // In a real compiler we'd resolve headers, here we just emit what it says
            const path = node.?.token.?.value;
            try data.appendCodeFmt(allocator, "#include \"{s}.h\"\n", .{path});
        },
        ASTNodeType.TypeAliasDeclaration => {
            // type Flags = u32
            if (node.?.left != null) {
                const c_utils = @import("c_utils.zig");
                const base_type = c_utils.nodeToCType(allocator, node.?.left.?) catch "void";
                try data.appendCodeFmt(allocator, "typedef {s} {s};\n", .{ base_type, node.?.token.?.value });
            }
        },
        else => {
            // @TODO implementation for other globals
        },
    }
}
