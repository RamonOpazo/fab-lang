//! Sorts: what a term is, read from its shape alone. A term is a node (`#A`,
//! `@`, a diagram name, `*`, `?`, `!`, a marker on a single edge) or edges
//! (everything else).

const Token = @import("../lex/Token.zig");
const Cst = @import("../parse/Cst.zig");

const Node = Cst.Node;

pub const Sort = enum { node, edges };

pub fn of(cst: *const Cst, node: Node.Index) Sort {
    return switch (cst.tag(node)) {
        .leaf => switch (cst.tokenTag(cst.mainToken(node))) {
            .node_id, .zone_id, .at, .star, .quid, .bang => .node,
            else => .edges,
        },
        .juxtafix => of(cst, cst.data(node).nodes[1]),
        // A trailing `/` changes the direction of an edge, not what a term is.
        .postfix => if (cst.tokenTag(cst.mainToken(node)) == .slash)
            of(cst, cst.data(node).node)
        else if (isPinchedEdge(cst, node)) .node else .edges,
        .prefix => if (isPinchedEdge(cst, node)) .node else .edges,
        .group => blk: {
            const inner = cst.children(node)[0];
            break :blk if (cst.tag(inner) == .items) .edges else of(cst, inner);
        },
        else => .edges,
    };
}

/// `f`, or a group of one that is: `(f)` is f.
pub fn isSingleEdge(cst: *const Cst, node: Node.Index) bool {
    return switch (cst.tag(node)) {
        .leaf => cst.tokenTag(cst.mainToken(node)) == .edge_id,
        .group => isSingleEdge(cst, cst.children(node)[0]),
        else => false,
    };
}

/// `+f`, `f+`, `f?`, `+(f)`: a marker on a single edge, which is a reference
/// to the node at that end.
pub fn isPinchedEdge(cst: *const Cst, node: Node.Index) bool {
    return switch (cst.tag(node)) {
        .prefix, .postfix => cst.tokenTag(cst.mainToken(node)) != .slash and isSingleEdge(cst, cst.data(node).node),
        else => false,
    };
}

pub fn isLeaf(cst: *const Cst, node: Node.Index, tag: Token.Tag) bool {
    return cst.tag(node) == .leaf and cst.tokenTag(cst.mainToken(node)) == tag;
}
