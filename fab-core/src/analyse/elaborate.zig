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

/// What a name stands for in a declaration, at its level.
pub const Name = struct {
    level: u32,
    is: union(enum) {
        /// A named node or `@`, at level 0.
        node: Elem,
        /// An edge, at level 1, or a cell above it.
        generator: Generator,
        /// Declared in a failed term: what refers to it stays quiet. At level
        /// 1, the hole it is bound to; above, nothing.
        hole: ?Elem,
    },
};

/// An edge or a cell: a generator of the polygraph, with a side on each end.
pub const Generator = struct {
    /// The IR edge at level 1, the IR cell above.
    index: u32,
    /// At level 1, the union-find elements of its two ends, from which the
    /// nodes are derived. Above, unused: the IR cell holds its sides.
    left: u32 = 0,
    right: u32 = 0,
    /// Where it is declared.
    token: TokenIndex,
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

/// A term's ports. The errors waiting for this term mark what it became:
/// its hole, or the node on its marked side.
fn term(a: *Analyser, node: Node.Index) error{OutOfMemory}!Ports {
    const p = try portsOf(a, node);
    const marked = if (a.cst.tag(node) == .postfix) p.right else p.left;
    const other = if (a.cst.tag(node) == .postfix) p.left else p.right;
    if (marked.len > 0) {
        a.settle(&a.pending, node, marked[0]);
    } else if (other.len > 0) a.settle(&a.pending, node, other[0]);
    return p;
}

fn portsOf(a: *Analyser, node: Node.Index) error{OutOfMemory}!Ports {
    if (a.failed.isSet(@backingInt(node))) return failedTerm(a, node);
    const cst = a.cst;
    return switch (cst.tag(node)) {
        .leaf => leaf(a, node),
        .juxtafix => one(a, try crossReference(a, node)),
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
        // A named node is plain: it meets no kind.
        .node_id => one(a, try named(a, text, .{ .name = text, .name_token = token, .kind = .plain, .kind_token = token })),
        // A diagram name as a node: its own node.
        .zone_id => one(a, try own(a, token)),
        .at => one(a, try named(a, "@", .{ .own = true, .name_token = token, .kind = .plain, .kind_token = token })),
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
    const gop = try a.scope.table.getOrPut(a.arena.allocator(), text);
    if (gop.found_existing) {
        const h = try hole(a);
        switch (gop.value_ptr.is) {
            .generator => |first| {
                const in_chain = if (a.scope.chain) |c| first.token >= c[0] and first.token <= c[1] else false;
                try a.errors.append(a.gpa, .{
                    .subject = .{ .elem = h },
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
            .hole, .node => {},
        }
        return one(a, h);
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
    gop.value_ptr.* = .{ .level = 1, .is = .{ .generator = .{ .index = @backingInt(index), .left = dom, .right = cod, .token = token } } };

    const ends = try a.arena.allocator().alloc(Elem, 2);
    ends[0] = dom;
    ends[1] = cod;
    return .{ .left = ends[0..1], .right = ends[1..2] };
}

// ---------------------------------------------------------------------------
// Other diagrams (rule 6)

/// A diagram declared before this one, by the token of its name. Its own
/// declaration is not before it: it names its own node with `@`.
fn diagram(a: *Analyser, token: TokenIndex) ?Analyser.Zone {
    const zone = a.zones.get(a.cst.tokenText(token)) orelse return null;
    return if (zone.index == a.zone()) null else zone;
}

/// `A` as a node: A's own node. A broken diagram's error is said already.
fn own(a: *Analyser, token: TokenIndex) error{OutOfMemory}!Elem {
    const zone = diagram(a, token) orelse return failHole(a, .diagram_not_declared, token);
    if (zone.broken) return hole(a);
    const at = zone.table.get("@") orelse return failHole(a, .diagram_without_own_node, token);
    return nodeOf(a, at);
}

/// `A.+f`, `A.f+`, `A.#X`, `A.@`: a node of another diagram, shared. It
/// stays A's: the oldest element of a class is A's own.
fn crossReference(a: *Analyser, node: Node.Index) error{OutOfMemory}!Elem {
    const cst = a.cst;
    const left, const right_ = cst.data(node).nodes;
    const right = sort.ofOne(cst, right_);
    const zone_token = cst.mainToken(left);
    if (sort.isLeaf(cst, right, .at)) return own(a, zone_token);
    const zone = diagram(a, zone_token) orelse return failHole(a, .diagram_not_declared, zone_token);
    if (zone.broken) return hole(a);

    if (sort.isLeaf(cst, right, .node_id)) {
        const token = cst.mainToken(right);
        const name = zone.table.get(cst.tokenText(token)) orelse return failHole(a, .undeclared_name_in_diagram, token);
        return nodeOf(a, name);
    }
    // Another shape was reported by rule 1, or by the kind after it.
    if (!sort.isPinchedEdge(a, right)) return hole(a);
    const name = cst.mainToken(singleEdge(cst, cst.data(right).node));
    const edge = zone.table.get(cst.tokenText(name)) orelse return failHole(a, .undeclared_name_in_diagram, name);
    return endOf(a, edge, if (cst.tag(right) == .prefix) .dom else .cod, name);
}

/// A named node, `@`, or a diagram name: one element per name in a
/// declaration, made on first use. A name only a failed term held is made
/// here, as if first used.
fn named(a: *Analyser, key: []const u8, class: @import("UnionFind.zig").Class) error{OutOfMemory}!Elem {
    const gop = try a.scope.table.getOrPut(a.arena.allocator(), key);
    if (!gop.found_existing or gop.value_ptr.is == .hole) gop.value_ptr.* = .{ .level = 0, .is = .{ .node = try a.uf.add(@backingInt(a.zone()), null, class) } };
    return gop.value_ptr.is.node;
}

/// A named node of another diagram, or the hole of the failed term that
/// alone held it: what refers to it stays quiet.
fn nodeOf(a: *Analyser, name: Name) error{OutOfMemory}!Elem {
    return switch (name.is) {
        .node => |e| e,
        .hole => |h| h orelse hole(a),
        .generator => unreachable,
    };
}

fn hole(a: *Analyser) error{OutOfMemory}!Elem {
    return a.uf.add(@backingInt(a.zone()), null, .{ .hole = true });
}

/// Reports an error, and makes the hole it marks.
fn failHole(a: *Analyser, tag: Analyser.Error.Tag, token: TokenIndex) error{OutOfMemory}!Elem {
    const h = try hole(a);
    try a.failOn(tag, token, .{ .elem = h });
    return h;
}

/// A failed term is one hole. The edges declared inside it are bound to the
/// hole, so references to them stay quiet; so are the named nodes only it
/// holds, until a later term makes them, so the levels above stay quiet.
fn failedTerm(a: *Analyser, node: Node.Index) error{OutOfMemory}!Ports {
    const cst = a.cst;
    const h = try hole(a);
    var t = cst.firstToken(node);
    while (t <= cst.lastToken(node)) : (t += 1) {
        const key, const level: u32 = switch (cst.tokenTag(t)) {
            .edge_id => .{ cst.tokenText(t), 1 },
            .node_id => .{ cst.tokenText(t), 0 },
            .at => .{ "@", 0 },
            else => continue,
        };
        const gop = try a.scope.table.getOrPut(a.arena.allocator(), key);
        if (!gop.found_existing) gop.value_ptr.* = .{ .level = level, .is = .{ .hole = h } };
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
        try space(a, prev.right, next.left, a.cst.firstToken(step), step);
        prev = next;
    }
    return .{ .left = first.left, .right = prev.right };
}

/// One to one is a glue. Anything else was reported by rule 2, and becomes a
/// hole holding both sides.
/// The errors about the space, waiting under `step`, mark the node it makes.
fn space(a: *Analyser, left: []const Elem, right: []const Elem, token: TokenIndex, step: Node.Index) error{OutOfMemory}!void {
    if (left.len == 1 and right.len == 1) {
        try glue(a, left[0], right[0], token);
        a.settle(&a.pending_joins, step, left[0]);
    } else a.settle(&a.pending_joins, step, try holeOf(a, &.{ left, right }));
}

fn holeOf(a: *Analyser, sides: []const []const Elem) error{OutOfMemory}!Elem {
    const h = try hole(a);
    for (sides) |side| for (side) |e| try glue(a, h, e, null);
    return h;
}

/// Merges two classes where they meet, at `token` (rule 5). A node has at
/// most one name and kinds that agree; on a conflict the error is reported
/// there, and the classes merge anyway, keeping the older's name and kind.
/// A glue with no token can't conflict: one side is a hole, or fresh.
fn glue(a: *Analyser, x: Elem, y: Elem, token: ?TokenIndex) error{OutOfMemory}!void {
    const conflict = try a.uf.unite(x, y) orelse return;
    if (token) |t| {
        const tag: Analyser.Error.Tag = switch (conflict.tag) {
            .different_kinds => .kinds_disagree,
            .two_names => .two_names_for_one_node,
            .sealed_end => .reference_to_null_node,
            // Classes stand for outer cells from plan step 7.
            .two_outer_edges => unreachable,
        };
        try a.errors.append(a.gpa, .{ .tag = tag, .token = t, .related = conflict.related, .subject = .{ .elem = x } });
    }
    try a.uf.force(x, y);
}

/// `+t`, `t+`, `t?`, `t!`, and a trailing `/`. On a single edge, `+` and its
/// kinds are references to an end.
fn marker(a: *Analyser, node: Node.Index) error{OutOfMemory}!Ports {
    const cst = a.cst;
    const main = cst.mainToken(node);
    const operand = cst.data(node).node;
    const tag = cst.tokenTag(main);

    if (tag == .slash) {
        const first = a.builder.edges.len;
        const p = try term(a, operand);
        undirect(a, first);
        return p;
    }
    if (sort.isPinchedEdge(a, node)) return one(a, try reference(a, node, if (cst.tag(node) == .prefix) .dom else .cod));

    // A pinch with several branches declares them.
    a.scope.pinches += 1;
    const p = try term(a, operand);
    a.scope.pinches -= 1;
    if (cst.tag(node) == .prefix) return .{ .left = try pinch(a, p.left, null, main), .right = p.right };
    const kind: ?Ir.Node.Kind = switch (tag) {
        .quid => .choice,
        .bang => .parallel,
        else => null,
    };
    return .{ .left = p.left, .right = try pinch(a, p.right, kind, main) };
}

/// Merges one side into the first branch's element. A kind is an element of
/// its own, glued in like any other, so it meets what is there.
fn pinch(a: *Analyser, side: []const Elem, kind: ?Ir.Node.Kind, token: TokenIndex) error{OutOfMemory}![]const Elem {
    const first = if (side.len > 0) side[0] else try a.uf.add(@backingInt(a.zone()), null, .{});
    for (side[@min(1, side.len)..]) |e| try glue(a, first, e, token);
    if (kind) |k| try glue(a, first, try a.uf.add(@backingInt(a.zone()), null, .{ .kind = k, .kind_token = token }), token);
    return (try one(a, first)).left;
}

/// The node at one end of a declared edge. An edge not declared yet is a
/// hole: a forward reference if the declaration names it later, else not
/// declared.
fn reference(a: *Analyser, node: Node.Index, side: Ir.End.Side) error{OutOfMemory}!Elem {
    const cst = a.cst;
    const name = cst.tokenText(cst.mainToken(singleEdge(cst, cst.data(node).node)));
    const edge = a.scope.table.get(name) orelse {
        const later = for (cst.lastToken(node) + 1..a.scope.end + 1) |t| {
            const i: TokenIndex = @intCast(t);
            if (cst.tokenTag(i) == .edge_id and std.mem.eql(u8, cst.tokenText(i), name)) break true;
        } else false;
        return failHole(a, if (later) .forward_reference else .reference_not_declared, cst.mainToken(singleEdge(cst, cst.data(node).node)));
    };
    return endOf(a, edge, side, cst.mainToken(singleEdge(cst, cst.data(node).node)));
}

/// One end of an edge. A null node is private to the one end it holds
/// (rule 5), so a reference to it is an error at the edge's name. A cell has
/// no ends at level 1.
fn endOf(a: *Analyser, edge: Name, side: Ir.End.Side, name: TokenIndex) error{OutOfMemory}!Elem {
    if (edge.level != 1) return failHole(a, .undeclared_name_in_diagram, name);
    const elem = switch (edge.is) {
        .generator => |e| if (side == .dom) e.left else e.right,
        .hole => |h| return h.?,
        .node => unreachable,
    };
    const class = a.uf.class(elem);
    if (class.sealed and !class.hole) {
        return failHole(a, .reference_to_null_node, name);
    }
    return elem;
}

fn singleEdge(cst: *const Cst, node: Node.Index) Node.Index {
    return if (cst.tag(node) == .group) singleEdge(cst, cst.children(node)[0]) else node;
}

/// Marks the edges a chain declared, from `first` on, undirected: in a
/// chain every edge is new, since a reference is a node (`+f`, `f+`).
fn undirect(a: *Analyser, first: usize) void {
    for (a.builder.edges.items(.directed)[first..]) |*directed| directed.* = false;
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
    if (try selfAttachment(a, node)) return failedTerm(a, node);
    if (isLoop(cst, links)) {
        const p = try term(a, links[0]);
        try glue(a, p.right[0], p.left[0], null);
        return .{ .left = p.left, .right = &.{} };
    }

    // A trailing `/` belongs to the whole chain, and undirects its edges:
    // `#A/f/#B/` is undirected f, `f/g/` an undirected cycle.
    const trailing = cst.tag(links[last]) == .postfix and cst.tokenTag(cst.mainToken(links[last])) == .slash;
    const ports = try a.arena.allocator().alloc(Ports, links.len);
    const first_edge = a.builder.edges.len;
    var edges: usize = 0;
    for (links, ports, 0..) |link, *p, i| {
        const l = if (i == last and trailing) cst.data(link).node else link;
        p.* = try term(a, l);
        if (sort.of(a, l) == .edges) edges += 1;
    }
    for (ports[0..last], ports[1..], links[0..last]) |left, right, link| try slash(a, left.right, right.left, cst.lastToken(link) + 1);
    if (edges > 1) {
        const end = if (trailing) cst.data(links[last]).node else links[last];
        if (sort.of(a, end) == .node and !closes(a, ports[last].right, ports[0].left)) {
            try a.failOn(.cycle_does_not_close, cst.firstToken(links[last]), .{ .elem = ports[last].right[0] });
        } else try slash(a, ports[last].right, ports[0].left, cst.lastToken(links[last - 1]) + 1);
    }

    for (links, ports, 0..) |link, p, i| {
        const l = if (i == last and trailing) cst.data(link).node else link;
        if (sort.isLeaf(cst, l, .star)) (try a.uf.edit(p.left[0])).sealed = true;
    }
    if (trailing) undirect(a, first_edge);

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
fn selfAttachment(a: *Analyser, chain: Node.Index) error{OutOfMemory}!bool {
    const cst = a.cst;
    const links = cst.children(chain);
    const at = for (links, 0..) |link, i| {
        if (sort.of(a, link) == .edges) break i;
    } else return false;
    const edge = links[at];
    if (!sort.isLeaf(cst, edge, .edge_id)) return false;
    const name = cst.tokenText(cst.mainToken(edge));
    if (a.scope.table.contains(name)) return false;
    for (links[at + 1 ..]) |link| {
        if (sort.of(a, link) == .edges) return false;
        if (!sort.isPinchedEdge(a, link)) continue;
        if (!std.mem.eql(u8, cst.tokenText(cst.mainToken(singleEdge(cst, cst.data(link).node))), name)) continue;
        const to_start = cst.tag(link) == .prefix;
        try a.failAt(if (to_start) .redundant_self_attachment else .vacuous_self_attachment, cst.mainToken(singleEdge(cst, cst.data(link).node)), chain);
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
fn slash(a: *Analyser, left: []const Elem, right: []const Elem, token: TokenIndex) error{OutOfMemory}!void {
    if (left.len == 1 and right.len >= 1) {
        for (right) |e| try glue(a, left[0], e, token);
    } else if (right.len == 1 and left.len >= 1) {
        for (left) |e| try glue(a, e, right[0], token);
    } else _ = try holeOf(a, &.{ left, right });
}

// ---------------------------------------------------------------------------
// The graph

/// A cell goes between parallel cells (plan steps 7c, 7d): its two sides
/// leave the same place and reach the same place. It is judged on the final
/// graph, since a later diagram can merge nodes, and a cell that fails it
/// stays drawn, marked. A hole says nothing more.
fn parallel(a: *Analyser) error{OutOfMemory}!void {
    const cells = a.builder.cells.slice();
    for (0..cells.len) |i| {
        const below = cells.items(.level)[i] - 1;
        const s = boundary(a, cells.items(.source)[i], below);
        const t = boundary(a, cells.items(.target)[i], below);
        if (isHole(a, s.ends[0]) or isHole(a, s.ends[1]) or isHole(a, t.ends[0]) or isHole(a, t.ends[1])) continue;
        if (std.meta.eql(s.ends, t.ends)) continue;
        // An undirected side may be read either way.
        if ((!s.directed or !t.directed) and std.meta.eql(s.ends, [2]Ir.Cell.Side{ t.ends[1], t.ends[0] })) continue;
        try a.errors.append(a.gpa, .{ .tag = .cells_not_parallel, .token = a.cell_tokens.items[i], .subject = .{ .cell = @intCast(i) } });
    }
}

/// Where a side of a cell starts and ends, one level below the side's place
/// at `level`. A side of that level has its own; a lower one stands for its
/// identity there, which starts and ends on itself, an identity standing for
/// itself at every level below (`f/α/#A` is α : f ⇒ 1_A).
fn boundary(a: *Analyser, side: Ir.Cell.Side, level: u32) struct { ends: [2]Ir.Cell.Side, directed: bool } {
    const level_of: u32 = switch (side) {
        .node => 0,
        .edge => 1,
        .cell => |c| a.builder.cells.items(.level)[@backingInt(c)],
    };
    if (level_of < level) return .{ .ends = .{ side, side }, .directed = true };
    return switch (side) {
        .node => unreachable,
        .edge => |e| blk: {
            const edge = a.builder.edges.get(@backingInt(e));
            break :blk .{ .ends = .{ .{ .node = edge.source }, .{ .node = edge.target } }, .directed = edge.directed };
        },
        .cell => |c| blk: {
            const cell = a.builder.cells.get(@backingInt(c));
            break :blk .{ .ends = .{ cell.source, cell.target }, .directed = cell.directed };
        },
    };
}

/// A hole among the ends: a node that failed.
fn isHole(a: *Analyser, side: Ir.Cell.Side) bool {
    return side == .node and a.builder.nodes.items(.kind)[@backingInt(side.node)] == .hole;
}

/// Every class becomes a node, in the order of its oldest element, and every
/// edge goes from the class of its start to the class of its end. A node's
/// zone is its oldest element's: the diagram that created it.
pub fn graph(a: *Analyser) error{OutOfMemory}!void {
    const uf = &a.uf;
    const node_of = try a.arena.allocator().alloc(Ir.NodeIndex, uf.len());
    a.node_of = node_of;
    for (0..uf.len()) |i| {
        const e: Elem = @intCast(i);
        if (uf.find(e) != e) continue;
        const class = uf.class(e);
        const zone: Ir.ZoneIndex = @fromBackingInt(uf.zone_of.items[e]);
        node_of[e] = try a.builder.addNode(.{
            .kind = if (class.hole) .hole else class.kind orelse .plain,
            .name = if (class.name) |name| try a.builder.addString(name) else null,
            .zone = zone,
            .canonical = null,
        });
        if (class.own) a.builder.zones.items(.own)[@backingInt(zone)] = node_of[e];
    }

    // Canonical references (rule 7): a name is opted into, so a named node
    // is its name; any other node is the first end that created it, in
    // reading order, which is the order elements are made in.
    const canonical = a.builder.nodes.items(.canonical);
    for (uf.end_of.items, 0..) |end_, i| {
        const end = end_ orelse continue;
        const root = uf.find(@intCast(i));
        const node = @backingInt(node_of[root]);
        if (canonical[node] == null and !uf.class(root).named()) canonical[node] = end;
    }
    const sources = a.builder.edges.items(.source);
    const targets = a.builder.edges.items(.target);
    for (a.edge_ends.items, sources, targets) |ends, *source, *target| {
        source.* = node_of[uf.find(ends[0])];
        target.* = node_of[uf.find(ends[1])];
    }

    // A node side was its element until now.
    for (a.builder.cells.items(.source), a.builder.cells.items(.target)) |*source, *target| {
        for ([_]*Ir.Cell.Side{ source, target }) |side| {
            if (side.* == .node) side.* = .{ .node = node_of[uf.find(@backingInt(side.node))] };
        }
    }
    try parallel(a);

    // Issues: every error with a subject marks it, warnings and unsupported
    // included; renderers read the severity from the diagnostic.
    for (a.errors.items, 0..) |err, i| {
        const subject = err.subject orelse continue;
        try a.builder.addIssue(.{ .err = .{ .analysis = @intCast(i) }, .subject = switch (subject) {
            .elem => |e| .{ .node = node_of[uf.find(e)] },
            .edge => |e| .{ .edge = @fromBackingInt(e) },
            .cell => |c| .{ .cell = @fromBackingInt(c) },
            .zone => |z| .{ .zone = @fromBackingInt(z) },
        } });
    }
}
