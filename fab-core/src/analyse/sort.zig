//! Sorts: what a term is. A term is a node (`#A`, `@`, a diagram name, `*`,
//! `?`, `!`, a marker on a single edge) or edges (everything else).
//!
//! At level 1 the shape alone says which. Above it, a lowercase name is read
//! from the diagram's table: a cell of the level below is a side, which
//! stands where a named node stands at level 1, and any other is a cell of
//! this level, an edge one dimension up (spec, Levels).

const Token = @import("../lex/Token.zig");
const Cst = @import("../parse/Cst.zig");
const Analyser = @import("Analyser.zig");

const Node = Cst.Node;

pub const Sort = enum { node, edges };

pub fn of(a: *const Analyser, node: Node.Index) Sort {
    const cst = a.cst;
    return switch (cst.tag(node)) {
        .leaf => switch (cst.tokenTag(cst.mainToken(node))) {
            .node_id, .zone_id, .at, .star, .quid, .bang => .node,
            .edge_id => if (isSide(a, cst.mainToken(node))) .node else .edges,
            else => .edges,
        },
        .juxtafix => of(a, cst.data(node).nodes[1]),
        // A trailing `/` changes the direction of an edge, not what a term is.
        .postfix => if (cst.tokenTag(cst.mainToken(node)) == .slash)
            of(a, cst.data(node).node)
        else if (isPinchedEdge(a, node)) .node else .edges,
        .prefix => if (isPinchedEdge(a, node)) .node else .edges,
        .group => blk: {
            const inner = cst.children(node)[0];
            break :blk if (cst.tag(inner) == .items) .edges else of(a, inner);
        },
        else => .edges,
    };
}

/// `f`, or a group of one that is: `(f)` is f.
pub fn isSingleEdge(a: *const Analyser, node: Node.Index) bool {
    const cst = a.cst;
    return switch (cst.tag(node)) {
        .leaf => cst.tokenTag(cst.mainToken(node)) == .edge_id and !isSide(a, cst.mainToken(node)),
        .group => isSingleEdge(a, cst.children(node)[0]),
        else => false,
    };
}

/// `+f`, `f+`, `f?`, `+(f)`: a marker on a single edge, which is a reference
/// to the node at that end.
pub fn isPinchedEdge(a: *const Analyser, node: Node.Index) bool {
    const cst = a.cst;
    return switch (cst.tag(node)) {
        .prefix, .postfix => cst.tokenTag(cst.mainToken(node)) != .slash and isSingleEdge(a, cst.data(node).node),
        else => false,
    };
}

/// Above level 1, a name of the level just below: a side.
pub fn isSide(a: *const Analyser, token: Cst.TokenIndex) bool {
    if (a.scope.level == 1) return false;
    const name = a.scope.table.get(a.cst.tokenText(token)) orelse return false;
    return name.level + 1 == a.scope.level;
}

pub fn isLeaf(cst: *const Cst, node: Node.Index, tag: Token.Tag) bool {
    return cst.tag(node) == .leaf and cst.tokenTag(cst.mainToken(node)) == tag;
}

/// A group of one is its item.
pub fn ofOne(cst: *const Cst, node: Node.Index) Node.Index {
    if (cst.tag(node) != .group) return node;
    const inner = cst.children(node)[0];
    return if (cst.tag(inner) == .items) node else ofOne(cst, inner);
}
