const std = @import("std");
const node = @import("node.zig");
const errors = @import("errors.zig");
const ASTNode = node.ASTNode;
const ASTNodeType = node.ASTNodeType;
const AstError = errors.AstError;
const Allocator = std.mem.Allocator;

/// Allocate a new ASTNode with every field zeroed / null.
pub fn createDefaultAstNode(allocator: *Allocator) AstError!*ASTNode {
    const n: *ASTNode = allocator.*.create(ASTNode) catch {
        return AstError.Out_Of_Memory;
    };
    n.node_type = ASTNodeType.Invalid;
    n.token = null;
    n.left = null;
    n.middle = null;
    n.right = null;
    n.children = null;
    n.is_const = false;
    n.is_mut = false;
    n.is_global = false;
    n.is_pub = false;
    return n;
}

/// Allocate a new ASTNode with a specific type and token pre-set.
pub fn createAstNode(
    allocator: *Allocator,
    node_type: ASTNodeType,
) AstError!*ASTNode {
    const n: *ASTNode = try createDefaultAstNode(allocator);
    n.node_type = node_type;
    return n;
}

/// Allocate a new ArrayList(*ASTNode) on the heap (arena-friendly).
pub fn createChildList(allocator: *Allocator) AstError!*std.ArrayList(*ASTNode) {
    const list = allocator.*.create(std.ArrayList(*ASTNode)) catch {
        return AstError.Out_Of_Memory;
    };
    list.* = try std.ArrayList(*ASTNode).initCapacity(allocator.*, 0);
    return list;
}

/// Append a child to a node's children list, creating it lazily if needed.
pub fn appendChild(
    allocator: *Allocator,
    parent: *ASTNode,
    child: *ASTNode,
) AstError!void {
    if (parent.children == null) {
        parent.children = try createChildList(allocator);
    }
    parent.children.?.*.append(allocator.*, child) catch {
        return AstError.Out_Of_Memory;
    };
}
