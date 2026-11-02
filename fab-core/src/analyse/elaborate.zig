//! Elaboration (rule 3 on): turns the terms of a declaration into elements of
//! the union-find, whose classes become the IR's nodes, and into edges.
//!
//! Runs after rules 0–2, so every term it meets is well typed or has failed.
//! It reports only what needs names: edges declared twice, references, and
//! cycles that don't close. A failed term, a join that rule 2 rejected, and a
//! term with a name error become holes, so the path stays connected and
//! nothing glued to them reports again.
//!
//! Each term elaborates to its ports: the elements on its left and on its
//! right, as its interface counts them.

const std = @import("std");
const Cst = @import("../parse/Cst.zig");
const Ir = @import("Ir.zig");
const Analyser = @import("Analyser.zig");
const sort = @import("sort.zig");

const Node = Cst.Node;
const TokenIndex = Cst.TokenIndex;
const Elem = u32;

const Ports = struct {
    left: []const Elem,
    right: []const Elem,

    fn both(elems: []const Elem) Ports {
        return .{ .left = elems, .right = elems };
    }
};

/// What an edge name stands for in a declaration.
pub const Binding = union(enum) {
    edge: struct { index: Ir.EdgeIndex, dom: Elem, cod: Elem, token: TokenIndex },
    /// The edge was declared in a failed term.
    hole: Elem,
};

/// The items of a declaration's first level.
pub fn items(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    switch (cst.tag(node)) {
        .items => for (cst.children(node)) |item| try items(a, item),
        .block => {
            const inner = cst.children(node)[0];
            try items(a, if (cst.tag(inner) == .levels) cst.children(inner)[0] else inner);
        },
        else => _ = try term(a, node),
    }
}

fn term(a: *Analyser, node: Node.Index) error{OutOfMemory}!Ports {
    if (a.failed.isSet(@backingInt(node))) return failedTerm(a, node);
    const cst = a.cst;
    return switch (cst.tag(node)) {
        .leaf => leaf(a, node),
        // Another diagram's node or edge: a stand-in until rule 6.
        .juxtafix => one(a, try a.uf.add(@backingInt(a.zone()), null, .{})),
        .group => group(a, cst.children(node)[0]),
        .o_chain => openChain(a, node),
        .c_chain => closedChain(a, node),
        .prefix, .postfix => marker(a, node),
        else => failedTerm(a, node),
    };
}

fn one(a: *Analyser, elem: Elem) error{OutOfMemory}!Ports {
    const elems = try a.arena.allocator().alloc(Elem, 1);
    elems[0] = elem;
    return .both(elems);
}

fn leaf(a: *Analyser, node: Node.Index) error{OutOfMemory}!Ports {
    const cst = a.cst;
    const token = cst.mainToken(node);
    const text = cst.tokenText(token);
    return switch (cst.tokenTag(token)) {
        .edge_id => declareEdge(a, token),
        .node_id => one(a, try named(a, text, .{ .name = text, .name_token = token })),
        // A diagram name as a node: a named stand-in until rule 6.
        .zone_id => one(a, try named(a, text, .{ .name = text, .name_token = token })),
        .at => one(a, try named(a, "@", .{ .own = true, .name_token = token })),
        .star => one(a, try a.uf.add(@backingInt(a.zone()), null, .{ .kind = .null_node })),
        .quid => one(a, try a.uf.add(@backingInt(a.zone()), null, .{ .kind = .choice, .kind_token = token })),
        .bang => one(a, try a.uf.add(@backingInt(a.zone()), null, .{ .kind = .parallel, .kind_token = token })),
        else => failedTerm(a, node),
    };
}

/// A bare edge name declares the edge: two fresh ends. Declared again, it is
/// a hole, and the first declaration keeps its shape; inside the same chain,
/// outside `f/f`, it is a self-reference; inside a pinch, a pinch of declared
/// edges. A name a failed term declared is quiet.
fn declareEdge(a: *Analyser, token: TokenIndex) error{OutOfMemory}!Ports {
    const text = a.cst.tokenText(token);
    const gop = try a.scope.edges.getOrPut(a.arena.allocator(), text);
    if (gop.found_existing) {
        switch (gop.value_ptr.*) {
            .edge => |first| {
                const in_chain = if (a.scope.chain) |c| first.token >= c[0] and first.token <= c[1] else false;
                try a.errors.append(a.gpa, .{
                    .tag = if (in_chain)
                        .self_reference_outside_loop
                    else if (a.scope.pinches > 0)
                        .pinch_of_declared_edges
                    else
                        .edge_declared_twice,
                    .token = token,
                    .related = first.token,
                });
            },
            .hole => {},
        }
        return one(a, try hole(a));
    }

    const index = try a.builder.addEdge(.{
        .name = try a.builder.addString(text),
        .source = undefined,
        .target = undefined,
        .directed = true,
        .zone = a.zone(),
    });
    const dom = try a.uf.add(@backingInt(a.zone()), .{ .edge = index, .side = .dom }, .{});
    const cod = try a.uf.add(@backingInt(a.zone()), .{ .edge = index, .side = .cod }, .{});
    try a.edge_ends.append(a.arena.allocator(), .{ dom, cod });
    gop.value_ptr.* = .{ .edge = .{ .index = index, .dom = dom, .cod = cod, .token = token } };

    const ends = try a.arena.allocator().alloc(Elem, 2);
    ends[0] = dom;
    ends[1] = cod;
    return .{ .left = ends[0..1], .right = ends[1..2] };
}

/// A named node, `@`, or a diagram name: one element per name in a
/// declaration, made on first use.
fn named(a: *Analyser, key: []const u8, class: @import("UnionFind.zig").Class) error{OutOfMemory}!Elem {
    const gop = try a.scope.names.getOrPut(a.arena.allocator(), key);
    if (!gop.found_existing) gop.value_ptr.* = try a.uf.add(@backingInt(a.zone()), null, class);
    return gop.value_ptr.*;
}

fn hole(a: *Analyser) error{OutOfMemory}!Elem {
    return a.uf.add(@backingInt(a.zone()), null, .{ .hole = true });
}

/// A failed term is one hole. The edges declared inside it are bound to the
/// hole, so references to them stay quiet.
fn failedTerm(a: *Analyser, node: Node.Index) error{OutOfMemory}!Ports {
    const cst = a.cst;
    const h = try hole(a);
    var t = cst.firstToken(node);
    while (t <= cst.lastToken(node)) : (t += 1) {
        if (cst.tokenTag(t) != .edge_id) continue;
        const gop = try a.scope.edges.getOrPut(a.arena.allocator(), cst.tokenText(t));
        if (!gop.found_existing) gop.value_ptr.* = .{ .hole = h };
    }
    return one(a, h);
}

/// `(s, t)`: the ports of the branches, side by side.
fn group(a: *Analyser, inner: Node.Index) error{OutOfMemory}!Ports {
    const cst = a.cst;
    if (cst.tag(inner) != .items) return term(a, inner);
    var left: std.ArrayList(Elem) = .empty;
    var right: std.ArrayList(Elem) = .empty;
    for (cst.children(inner)) |item| {
        const p = try term(a, item);
        try left.appendSlice(a.arena.allocator(), p.left);
        try right.appendSlice(a.arena.allocator(), p.right);
    }
    return .{ .left = left.items, .right = right.items };
}

/// `s t …`: each space joins one to one.
fn openChain(a: *Analyser, node: Node.Index) error{OutOfMemory}!Ports {
    const steps = a.cst.children(node);
    const first = try term(a, steps[0]);
    var prev = first;
    for (steps[1..]) |step| {
        const next = try term(a, step);
        try space(a, prev.right, next.left);
        prev = next;
    }
    return .{ .left = first.left, .right = prev.right };
}

/// One to one is a glue. Anything else was reported by rule 2, and becomes a
/// hole holding both sides.
fn space(a: *Analyser, left: []const Elem, right: []const Elem) error{OutOfMemory}!void {
    if (left.len == 1 and right.len == 1) return glue(a, left[0], right[0]);
    try holeOf(a, &.{ left, right });
}

fn holeOf(a: *Analyser, sides: []const []const Elem) error{OutOfMemory}!void {
    const h = try hole(a);
    for (sides) |side| for (side) |e| try glue(a, h, e);
}

/// Merges two classes. A conflict is rule 5's to report; until then the
/// classes merge anyway.
fn glue(a: *Analyser, x: Elem, y: Elem) error{OutOfMemory}!void {
    if (try a.uf.unite(x, y) != null) try a.uf.force(x, y);
}

/// `+t`, `t+`, `t?`, `t!`, and a trailing `/`. On a single edge, `+` and its
/// kinds are references to an end.
fn marker(a: *Analyser, node: Node.Index) error{OutOfMemory}!Ports {
    const cst = a.cst;
    const main = cst.mainToken(node);
    const operand = cst.data(node).node;
    const tag = cst.tokenTag(main);

    if (tag == .slash) {
        const p = try term(a, operand);
        undirect(a, operand);
        return p;
    }
    if (sort.isPinchedEdge(cst, node)) return one(a, try reference(a, node, if (cst.tag(node) == .prefix) .dom else .cod));

    // A pinch with several branches declares them.
    a.scope.pinches += 1;
    const p = try term(a, operand);
    a.scope.pinches -= 1;
    if (cst.tag(node) == .prefix) return .{ .left = try pinch(a, p.left, null), .right = p.right };
    const kind: ?Ir.Node.Kind = switch (tag) {
        .quid => .choice,
        .bang => .parallel,
        else => null,
    };
    return .{ .left = p.left, .right = try pinch(a, p.right, if (kind) |k| .{ k, main } else null) };
}

/// Merges one side into the first branch's element, and gives it a kind.
fn pinch(a: *Analyser, side: []const Elem, kind: ?struct { Ir.Node.Kind, TokenIndex }) error{OutOfMemory}![]const Elem {
    const first = if (side.len > 0) side[0] else try a.uf.add(@backingInt(a.zone()), null, .{});
    for (side[@min(1, side.len)..]) |e| try glue(a, first, e);
    if (kind) |k| {
        const class = try a.uf.edit(first);
        if (class.kind == null) {
            class.kind = k[0];
            class.kind_token = k[1];
        }
    }
    return (try one(a, first)).left;
}

/// The node at one end of a declared edge. An edge not declared yet is a
/// hole: a forward reference if the declaration names it later, else not
/// declared.
fn reference(a: *Analyser, node: Node.Index, side: Ir.End.Side) error{OutOfMemory}!Elem {
    const cst = a.cst;
    const name = cst.tokenText(cst.mainToken(singleEdge(cst, cst.data(node).node)));
    const binding = a.scope.edges.get(name) orelse {
        const later = for (cst.lastToken(node) + 1..a.scope.end + 1) |t| {
            const i: TokenIndex = @intCast(t);
            if (cst.tokenTag(i) == .edge_id and std.mem.eql(u8, cst.tokenText(i), name)) break true;
        } else false;
        try a.fail(if (later) .forward_reference else .reference_not_declared, cst.mainToken(singleEdge(cst, cst.data(node).node)));
        return hole(a);
    };
    return switch (binding) {
        .edge => |e| if (side == .dom) e.dom else e.cod,
        .hole => |h| h,
    };
}

fn singleEdge(cst: *const Cst, node: Node.Index) Node.Index {
    return if (cst.tag(node) == .group) singleEdge(cst, cst.children(node)[0]) else node;
}

/// Marks a single edge undirected. Anything else waits for its error (5.3b).
fn undirect(a: *Analyser, node: Node.Index) void {
    const cst = a.cst;
    if (!sort.isSingleEdge(cst, node)) return;
    const name = cst.tokenText(cst.mainToken(singleEdge(cst, node)));
    switch (a.scope.edges.get(name) orelse return) {
        .edge => |e| a.builder.edges.items(.directed)[@backingInt(e.index)] = false,
        .hole => {},
    }
}

/// `a/b/…`. One edge attaches to what is beside it, distributing over a
/// group; two or more close a cycle on its start. A `*` is sealed once glued,
/// and exposes nothing.
fn closedChain(a: *Analyser, node: Node.Index) error{OutOfMemory}!Ports {
    const cst = a.cst;
    // The outermost chain's span, for self-references.
    const outer = a.scope.chain == null;
    if (outer) a.scope.chain = .{ cst.firstToken(node), cst.lastToken(node) };
    defer if (outer) {
        a.scope.chain = null;
    };

    const links = cst.children(node);
    const last = links.len - 1;
    if (try selfAttachment(a, links)) return failedTerm(a, node);
    if (isLoop(cst, links)) {
        const p = try term(a, links[0]);
        try glue(a, p.right[0], p.left[0]);
        return .{ .left = p.left, .right = &.{} };
    }

    // A trailing `/` belongs to the whole chain: `#A/f/#B/` is undirected f.
    const trailing = cst.tag(links[last]) == .postfix and cst.tokenTag(cst.mainToken(links[last])) == .slash;
    const ports = try a.arena.allocator().alloc(Ports, links.len);
    var edges: usize = 0;
    var edge: Node.Index = undefined;
    for (links, ports, 0..) |link, *p, i| {
        const l = if (i == last and trailing) cst.data(link).node else link;
        p.* = try term(a, l);
        if (sort.of(cst, l) == .edges) {
            edges += 1;
            edge = l;
        }
    }
    for (ports[0..last], ports[1..]) |left, right| try slash(a, left.right, right.left);
    if (edges > 1) {
        const end = if (trailing) cst.data(links[last]).node else links[last];
        if (sort.of(cst, end) == .node and !closes(a, ports[last].right, ports[0].left)) {
            try a.fail(.cycle_does_not_close, cst.firstToken(links[last]));
        } else try slash(a, ports[last].right, ports[0].left);
    }

    for (links, ports, 0..) |link, p, i| {
        const l = if (i == last and trailing) cst.data(link).node else link;
        if (sort.isLeaf(cst, l, .star)) (try a.uf.edit(p.left[0])).sealed = true;
    }
    if (trailing and edges == 1) undirect(a, edge);

    if (edges > 1) return .{ .left = ports[0].left, .right = &.{} };
    return .{
        .left = if (sort.isLeaf(cst, links[0], .star)) &.{} else ports[0].left,
        .right = if (sort.isLeaf(cst, links[last], .star)) &.{} else ports[last].right,
    };
}

/// A cycle that ends on a node must end on its start: the same class
/// already. A hole closes anything.
fn closes(a: *Analyser, end: []const Elem, start: []const Elem) bool {
    if (end.len != 1 or start.len != 1) return true;
    if (a.uf.class(end[0]).hole or a.uf.class(start[0]).hole) return true;
    return a.uf.find(end[0]) == a.uf.find(start[0]);
}

/// `f/+f` and `f/f+`: a chain whose one edge is declared here, then a
/// reference to that edge. To its other end it is `f/f`; to the same end it
/// glues the end to itself.
fn selfAttachment(a: *Analyser, links: []const Node.Index) error{OutOfMemory}!bool {
    const cst = a.cst;
    const at = for (links, 0..) |link, i| {
        if (sort.of(cst, link) == .edges) break i;
    } else return false;
    const edge = links[at];
    if (!sort.isLeaf(cst, edge, .edge_id)) return false;
    const name = cst.tokenText(cst.mainToken(edge));
    if (a.scope.edges.contains(name)) return false;
    for (links[at + 1 ..]) |link| {
        if (sort.of(cst, link) == .edges) return false;
        if (!sort.isPinchedEdge(cst, link)) continue;
        if (!std.mem.eql(u8, cst.tokenText(cst.mainToken(singleEdge(cst, cst.data(link).node))), name)) continue;
        const to_start = cst.tag(link) == .prefix;
        try a.fail(if (to_start) .redundant_self_attachment else .vacuous_self_attachment, cst.mainToken(singleEdge(cst, cst.data(link).node)));
        return true;
    }
    return false;
}

/// `f/f`: the second f is the first, not a new edge.
fn isLoop(cst: *const Cst, links: []const Node.Index) bool {
    return links.len == 2 and sort.isLeaf(cst, links[0], .edge_id) and sort.isLeaf(cst, links[1], .edge_id) and
        std.mem.eql(u8, cst.tokenText(cst.mainToken(links[0])), cst.tokenText(cst.mainToken(links[1])));
}

/// One side of a `/` is one element, glued to every element on the other.
/// Anything else is an error of its own (5.3b), and a hole.
fn slash(a: *Analyser, left: []const Elem, right: []const Elem) error{OutOfMemory}!void {
    if (left.len == 1 and right.len >= 1) {
        for (right) |e| try glue(a, left[0], e);
    } else if (right.len == 1 and left.len >= 1) {
        for (left) |e| try glue(a, e, right[0]);
    } else try holeOf(a, &.{ left, right });
}

// ---------------------------------------------------------------------------
// The graph

/// Every class becomes a node, in the order of its oldest element, and every
/// edge goes from the class of its start to the class of its end.
pub fn graph(a: *Analyser) error{OutOfMemory}!void {
    const uf = &a.uf;
    const node_of = try a.arena.allocator().alloc(Ir.NodeIndex, uf.len());
    for (0..uf.len()) |i| {
        const e: Elem = @intCast(i);
        if (uf.find(e) != e) continue;
        const class = uf.class(e);
        const zone: Ir.ZoneIndex = @fromBackingInt(uf.zone_of.items[e]);
        node_of[e] = try a.builder.addNode(.{
            .kind = if (class.hole) .hole else class.kind orelse .plain,
            .name = if (class.name) |name| try a.builder.addString(name) else null,
            .zone = zone,
            .canonical = uf.end_of.items[e],
        });
        if (class.own) a.builder.zones.items(.own)[@backingInt(zone)] = node_of[e];
    }
    const sources = a.builder.edges.items(.source);
    const targets = a.builder.edges.items(.target);
    for (a.edge_ends.items, sources, targets) |ends, *source, *target| {
        source.* = node_of[uf.find(ends[0])];
        target.* = node_of[uf.find(ends[1])];
    }
}
