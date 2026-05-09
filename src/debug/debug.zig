const std = @import("std");
const lexer = @import("../lexer/lexer.zig");
const node_mod = @import("../ast/node.zig");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const Token = lexer.Token;
const ASTNode = node_mod.ASTNode;
const ASTNodeType = node_mod.ASTNodeType;

// pull the colours in with shorter names so the print calls aren't so noisy
const RST = lexer.RESET;
const GREY = lexer.GREY;
const ORANGE = lexer.ORANGE;
const CYAN = lexer.CYAN;
const CREAM = lexer.CREAM;
const GREEN = lexer.GREEN;
const LGREEN = lexer.LIGHT_GREEN;
const PEACH = lexer.PEACH;
const MAGENTA = lexer.MAGENTA;
const BLUE = lexer.BLUE;
const RED = lexer.RED;
const YELLOW = lexer.YELLOW;

// ── token list printer ────────────────────────────────────────────────────────

pub fn printTokens(token_list: *ArrayList(Token)) void {
    const n = token_list.items.len;
    print("{s}Tokens{s} ({d})\n", .{ CYAN, RST, n });

    if (n == 0) {
        print("  {s}(none){s}\n", .{ GREY, RST });
        return;
    }

    for (token_list.items, 0..) |tok, i| {
        print(
            "  {s}[{d:>3}]{s}  {s}Type:{s} {s}{s}{s}  {s}Value:{s} {s}'{s}'{s}  {s}Line:{s} {d}\n",
            .{
                GREY,  i,                           RST,
                GREY,  RST, CREAM, @tagName(tok.token_type), RST,
                GREY,  RST, ORANGE, tok.value,      RST,
                GREY,  RST, tok.line,
            },
        );
    }
    print("\n", .{});
}

// ── AST printer ───────────────────────────────────────────────────────────────

pub fn printAST(ast_nodes: *ArrayList(*ASTNode)) void {
    const n = ast_nodes.items.len;
    print("{s}AST{s} ({d} top-level node{s})\n", .{
        CYAN, RST, n, if (n == 1) @as([]const u8, "") else "s",
    });

    if (n == 0) {
        print("  {s}(empty){s}\n", .{ GREY, RST });
    } else {
        for (ast_nodes.items) |node| {
            print("  ", .{}); // top-level nodes get one level of indent
            printNode(node, 1);
        }
    }
    print("\n", .{});
}

// ── recursive node tree printer ───────────────────────────────────────────────

pub fn printNode(n: *const ASTNode, depth: usize) void {
    // node type coloured by what kind it is
    print("{s}{s}{s}", .{ nodeColour(n.node_type), @tagName(n.node_type), RST });

    // if the node has a token (name, operator, literal…) print it too
    if (n.token) |tok| {
        if (tok.value.len > 0) {
            print("  {s}{s}{s}", .{ ORANGE, tok.value, RST });
        }
    }

    // flags on the same line, shown in muted grey
    if (n.is_pub)    print("  {s}pub{s}",    .{ GREY, RST });
    if (n.is_const)  print("  {s}const{s}",  .{ GREY, RST });
    if (n.is_mut)    print("  {s}mut{s}",    .{ GREY, RST });
    if (n.is_global) print("  {s}global{s}", .{ GREY, RST });

    print("\n", .{});

    // print children
    if (n.left)   |l| { printChild(depth, "left",  l); }
    if (n.middle) |m| { printChild(depth, "mid",   m); }
    if (n.right)  |r| { printChild(depth, "right", r); }

    if (n.children) |list| {
        for (list.*.items) |child| {
            printChild(depth, "item", child);
        }
    }
}

fn printChild(depth: usize, label: []const u8, child: *const ASTNode) void {
    // indent by 2 spaces per depth level
    var i: usize = 0;
    while (i < depth) : (i += 1) print("  ", .{});

    print("{s}└─ {s}:{s} ", .{ GREY, label, RST });
    printNode(child, depth + 1);
}

// pick a colour based on the node category so the tree is easier to read at a glance
fn nodeColour(nt: ASTNodeType) []const u8 {
    return switch (nt) {
        .FunctionDeclaration              => LGREEN,
        .VarDeclaration, .ConstDeclaration => GREEN,
        .ReturnStatement                  => CYAN,
        .IfStatement, .LoopStatement      => MAGENTA,
        .BinaryExpression, .UnaryExpression => YELLOW,
        .IntegerLiteral, .FloatLiteral,
        .BoolLiteral, .CharLiteral,
        .StringLiteral                    => ORANGE,
        .Identifier                       => PEACH,
        .FunctionCall                     => BLUE,
        .Parameter, .Parameters           => CREAM,
        .Assignment                       => YELLOW,
        .Block, .IfBody, .ElseBody,
        .LoopBody                         => GREY,
        .VarType, .ReturnType             => GREY,
        else                              => RST,
    };
}
