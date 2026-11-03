//! Interfaces (rule 2): every term has a left side and a right side, each
//! holding what a neighbour can attach to. A space joins exactly one to
//! exactly one.
//!
//! Runs after rules 0–1, so it meets only terms whose sorts are right. A
//! failed term is a hole: its sides are unknown, and the spaces beside it
//! report nothing.

const Cst = @import("../parse/Cst.zig");
const Analyser = @import("Analyser.zig");
const sort = @import("sort.zig");

const Node = Cst.Node;
const TokenIndex = Cst.TokenIndex;

pub const Side = struct {
    /// Free edge ends.
    ends: u32 = 0,
    /// Nodes that ends already sit on: a pinch, a node attached with `/`.
    nodes: u32 = 0,
    /// A branch of a group exposes nothing on this side, and was skipped.
    skipped: bool = false,

    pub fn total(side: Side) u32 {
        return side.ends + side.nodes;
    }
};

pub const Type = union(enum) {
    /// A lone node: `#A`, `@`, `*`, `+f`. It never stands beside a space.
    node,
    /// A side is null when a failed term makes it unknown.
    sides: struct { left: ?Side, right: ?Side },

    fn left(t: Type) ?Side {
        return switch (t) {
            .node => null,
            .sides => |s| s.left,
        };
    }

    fn right(t: Type) ?Side {
        return switch (t) {
            .node => null,
            .sides => |s| s.right,
        };
    }

    fn isHole(t: Type) bool {
        return t == .sides and (t.sides.left == null or t.sides.right == null);
    }
};

const hole: Type = .{ .sides = .{ .left = null, .right = null } };
const edge: Type = .{ .sides = .{ .left = one_end, .right = one_end } };
const one_end: Side = .{ .ends = 1 };
const one_node: Side = .{ .nodes = 1 };
const nothing: Side = .{};

/// The items of a declaration's first level.
pub fn items(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    switch (cst.tag(node)) {
        .items => for (cst.children(node)) |item| try items(a, item),
        .block => {
            const inner = cst.children(node)[0];
            try items(a, if (cst.tag(inner) == .levels) cst.children(inner)[0] else inner);
        },
        else => _ = try of(a, node),
    }
}

/// A term's type, checking the spaces inside it.
fn of(a: *Analyser, node: Node.Index) error{OutOfMemory}!Type {
    if (a.failed.isSet(@backingInt(node))) return hole;
    const cst = a.cst;
    return switch (cst.tag(node)) {
        .leaf, .juxtafix => if (sort.of(a, node) == .node) .node else edge,
        .group => group(a, cst.children(node)[0]),
        .o_chain => openChain(a, node),
        .c_chain => closedChain(a, node),
        .prefix, .postfix => marker(a, node),
        else => hole,
    };
}

/// `(s, t)`: the sides of the branches, side by side. A branch with nothing
/// on a side (a stop, a cycle's right, a lone node) is skipped there.
fn group(a: *Analyser, inner: Node.Index) error{OutOfMemory}!Type {
    const cst = a.cst;
    if (cst.tag(inner) != .items) return of(a, inner);
    var left: ?Side = nothing;
    var right: ?Side = nothing;
    for (cst.children(inner)) |item| {
        const t = try of(a, item);
        left = add(left, if (t == .node) nothing else t.left());
        right = add(right, if (t == .node) nothing else t.right());
    }
    return .{ .sides = .{ .left = left, .right = right } };
}

fn add(sum: ?Side, side: ?Side) ?Side {
    const s = sum orelse return null;
    const b = side orelse return null;
    return .{
        .ends = s.ends + b.ends,
        .nodes = s.nodes + b.nodes,
        .skipped = s.skipped or b.skipped or b.total() == 0,
    };
}

/// `s t …`: the left of the first step, the right of the last, and one
/// space between each two.
fn openChain(a: *Analyser, node: Node.Index) error{OutOfMemory}!Type {
    const steps = a.cst.children(node);
    const first = try of(a, steps[0]);
    var prev = first;
    for (steps[1..]) |step| {
        const next = try of(a, step);
        try space(a, prev.right(), next.left(), step);
        prev = next;
    }
    return .{ .sides = .{ .left = first.left(), .right = prev.right() } };
}

/// A space joins one to one. Reported at the step after it, since a space
/// has no token of its own.
fn space(a: *Analyser, left: ?Side, right: ?Side, after: Node.Index) error{OutOfMemory}!void {
    const l = left orelse return;
    const r = right orelse return;
    const token = a.cst.firstToken(after);
    if (l.total() == 0 or r.total() == 0) return a.failJoin(.nothing_to_join, token, after);
    if (l.total() > 1 or r.total() > 1) return a.failJoin(.ends_dont_match, token, after);
    if (l.skipped or r.skipped) try a.failJoin(.space_reaches_one_branch, token, after);
}

/// `+t`, `t+`, `t?`, `t!`: one pinched node on the marker's side. A pinched
/// single edge is a node. A trailing `/` stands on a single edge only.
fn marker(a: *Analyser, node: Node.Index) error{OutOfMemory}!Type {
    const cst = a.cst;
    if (isTrailingSlash(cst, node)) {
        if (sort.isSingleEdge(a, cst.data(node).node)) return of(a, cst.data(node).node);
        try a.failTerm(.undirected_not_one_edge, node, cst.mainToken(node));
        return hole;
    }
    if (sort.of(a, node) == .node) return .node;
    const t = try of(a, cst.data(node).node);
    // A marker on a node failed in rule 1.
    if (t == .node) return hole;
    const prefix = cst.tag(node) == .prefix;
    if (!try pinchCount(a, node, if (prefix) t.left() else t.right())) return hole;
    return if (prefix)
        .{ .sides = .{ .left = one_node, .right = t.right() } }
    else
        .{ .sides = .{ .left = t.left(), .right = one_node } };
}

/// A pinch merges several into one. Nothing to merge is an error; one is a
/// pinch that does nothing, and warns.
fn pinchCount(a: *Analyser, node: Node.Index, side: ?Side) error{OutOfMemory}!bool {
    const s = side orelse return true;
    const token = a.cst.mainToken(node);
    switch (s.total()) {
        0 => {
            try a.failTerm(.pinch_of_nothing, node, token);
            return false;
        },
        1 => try a.failAt(.pinch_of_one_end, token, node),
        else => {},
    }
    return true;
}

/// `a/b/…`. One edge exposes what is beside it: a node, nothing beside `*`,
/// or its own side. Two or more close a cycle, which exposes its start on the
/// left and nothing on the right. The side beside `*` is exactly one free
/// end. Between edges, a `/` glues one to several: never nothing, never
/// several to several. A trailing `/` belongs to the chain, and needs it to
/// be one single edge.
fn closedChain(a: *Analyser, node: Node.Index) error{OutOfMemory}!Type {
    const cst = a.cst;
    const all = cst.children(node);
    const last = all.len - 1;
    const trailing = isTrailingSlash(cst, all[last]);

    var edges: usize = 0;
    var single = false;
    for (all, 0..) |link, i| {
        const l = unwrap(cst, link, i == last and trailing);
        if (sort.of(a, l) == .edges) {
            edges += 1;
            single = sort.isSingleEdge(a, l);
        }
    }
    if (trailing and !(edges == 1 and single)) {
        try a.failTerm(.undirected_not_one_edge, node, cst.mainToken(all[last]));
        return hole;
    }

    var unknown = false;
    var first: Type = undefined;
    var prev: Type = undefined;
    for (all, 0..) |link_, i| {
        const link = unwrap(cst, link_, i == last and trailing);
        const t = try of(a, link);
        if (t.isHole()) unknown = true;
        if (i == 0) {
            first = t;
        } else {
            const before = unwrap(cst, all[i - 1], false);
            if (isFreeStar(a, before) and !try nullEnd(a, t.left(), before)) unknown = true;
            if (isFreeStar(a, link) and !try nullEnd(a, prev.right(), link)) unknown = true;
            if (!try slash(a, node, prev, t, cst.lastToken(all[i - 1]) + 1)) return hole;
        }
        prev = t;
    }
    if (edges > 1 and !try slash(a, node, prev, first, cst.lastToken(all[last - 1]) + 1)) return hole;
    if (unknown or edges == 0) return hole;
    if (edges > 1) return .{ .sides = .{ .left = one_node, .right = nothing } };
    return .{ .sides = .{
        .left = end(a, all[0], first.left()),
        .right = end(a, unwrap(cst, all[last], trailing), prev.right()),
    } };
}

/// A `/` between two edge terms glues one to one or more; a node beside it
/// has no sides to count. Reports and fails the chain if not.
fn slash(a: *Analyser, chain: Node.Index, left: Type, right: Type, token: TokenIndex) error{OutOfMemory}!bool {
    const l = left.right() orelse return true;
    const r = right.left() orelse return true;
    if (l.total() == 0 or r.total() == 0) {
        try a.failTerm(.nothing_to_join, chain, token);
    } else if (l.total() > 1 and r.total() > 1) {
        try a.failTerm(.slash_between_groups, chain, token);
    } else return true;
    return false;
}

fn isTrailingSlash(cst: *const Cst, node: Node.Index) bool {
    return cst.tag(node) == .postfix and cst.tokenTag(cst.mainToken(node)) == .slash;
}

/// The last link without its trailing `/`.
fn unwrap(cst: *const Cst, link: Node.Index, trailing: bool) Node.Index {
    return if (trailing) cst.data(link).node else link;
}

/// What a one-edge chain exposes at one end: nothing beside `*`, the node
/// written there, or the side of its edge.
fn end(a: *Analyser, link: Node.Index, side: ?Side) ?Side {
    if (sort.isLeaf(a.cst, link, .star)) return nothing;
    if (sort.of(a, link) == .node) return one_node;
    return side;
}

fn isFreeStar(a: *Analyser, link: Node.Index) bool {
    return sort.isLeaf(a.cst, link, .star) and !a.failed.isSet(@backingInt(link));
}

/// Whether the side beside a `*` is exactly one free end; reports it if not.
fn nullEnd(a: *Analyser, side: ?Side, star: Node.Index) error{OutOfMemory}!bool {
    const s = side orelse return true;
    if (s.ends == 1 and s.nodes == 0) return true;
    try a.failTerm(.null_not_on_one_end, star, a.cst.mainToken(star));
    return false;
}
