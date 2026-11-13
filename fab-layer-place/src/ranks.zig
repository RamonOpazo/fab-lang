//! Spans that disagree (layout.md §5; plan step α5): whether a diagram's
//! stated spans admit ranks, before any placement.
//!
//! A stated span is an equality, rank(target) − rank(source) = span
//! (negative against the flow), contracted by a union-find with an offset
//! per element. Every other edge spans at least 1, except the back edges a
//! depth-first search picks in source order, which close cycles no span
//! states. Ranks exist iff the equalities agree and the inequalities, over
//! the classes, have no positive cycle (Bellman–Ford): in
//! `+(f g h, m n)+` with m and n spanning 1, A and D are one class two ranks
//! apart, and f g h must climb three.

const std = @import("std");

/// An edge as the check reads it: its ends, any numbering, and its stated
/// span, if any.
pub const Edge = struct { source: u32, target: u32, span: ?i64 };

/// The stated edge where the spans disagree, and another stated edge they
/// disagree with, by index in the edges given.
pub const Conflict = struct { at: u32, related: ?u32 };

pub fn check(gpa: std.mem.Allocator, edges: []const Edge) error{OutOfMemory}!?Conflict {
    var c: Checker = .{ .gpa = gpa, .edges = edges };
    defer c.deinit();
    return c.run();
}

const Checker = struct {
    gpa: std.mem.Allocator,
    edges: []const Edge,
    /// Nodes by their first appearance.
    ids: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    parent: std.ArrayList(u32) = .empty,
    /// rank(x) − rank(parent[x]).
    offset: std.ArrayList(i64) = .empty,

    fn deinit(c: *Checker) void {
        c.ids.deinit(c.gpa);
        c.parent.deinit(c.gpa);
        c.offset.deinit(c.gpa);
    }

    fn id(c: *Checker, node: u32) error{OutOfMemory}!u32 {
        const gop = try c.ids.getOrPut(c.gpa, node);
        if (!gop.found_existing) {
            gop.value_ptr.* = @intCast(c.parent.items.len);
            try c.parent.append(c.gpa, gop.value_ptr.*);
            try c.offset.append(c.gpa, 0);
        }
        return gop.value_ptr.*;
    }

    /// x's class, and rank(x) − rank(class).
    /// Iterative, so a long chain needs no deep stack: the root and x's
    /// offset first, then the path pointed at the root.
    fn find(c: *Checker, x: u32) struct { root: u32, offset: i64 } {
        const parent = c.parent.items;
        const offset = c.offset.items;
        var root = x;
        var total: i64 = 0;
        while (parent[root] != root) : (root = parent[root]) total += offset[root];
        var at = x;
        var rest = total;
        while (parent[at] != at) {
            const next = parent[at];
            const own = offset[at];
            parent[at] = root;
            offset[at] = rest;
            rest -= own;
            at = next;
        }
        return .{ .root = root, .offset = total };
    }

    fn run(c: *Checker) error{OutOfMemory}!?Conflict {
        const n = c.edges.len;
        const source = try c.gpa.alloc(u32, n);
        defer c.gpa.free(source);
        const target = try c.gpa.alloc(u32, n);
        defer c.gpa.free(target);
        for (c.edges, source, target) |e, *s, *t| {
            s.* = try c.id(e.source);
            t.* = try c.id(e.target);
        }

        // 1. The equalities.
        for (c.edges, source, target, 0..) |e, s, t, i| {
            const span = e.span orelse continue;
            const a = c.find(s);
            const b = c.find(t);
            if (a.root == b.root) {
                if (b.offset - a.offset != span) return .{ .at = @intCast(i), .related = c.lastStated(a.root, source, i) };
                continue;
            }
            c.parent.items[b.root] = a.root;
            c.offset.items[b.root] = a.offset + span - b.offset;
        }

        // 2. Back edges among the unstated, by a depth-first search in
        // source order over every edge, each oriented along the flow.
        const back = try c.backEdges(source, target);
        defer c.gpa.free(back);

        // 3. The inequalities over the classes: R(t) − R(s) ≥ 1 + o(s) − o(t).
        const Arc = struct { from: u32, to: u32, weight: i64 };
        var arcs: std.ArrayList(Arc) = .empty;
        defer arcs.deinit(c.gpa);
        for (c.edges, source, target, back) |e, s, t, is_back| {
            if (e.span != null or is_back) continue;
            const a = c.find(s);
            const b = c.find(t);
            const weight = 1 + a.offset - b.offset;
            if (a.root == b.root) {
                if (weight > 0) return c.inClasses(&.{a.root}, source);
                continue;
            }
            try arcs.append(c.gpa, .{ .from = a.root, .to = b.root, .weight = weight });
        }

        // Longest paths; a relaxation after |V| rounds is a positive cycle.
        const v = c.parent.items.len;
        const dist = try c.gpa.alloc(i64, v);
        defer c.gpa.free(dist);
        @memset(dist, 0);
        const pred = try c.gpa.alloc(u32, v);
        defer c.gpa.free(pred);
        for (pred, 0..) |*p, i| p.* = @intCast(i);
        var round: usize = 0;
        while (round <= v) : (round += 1) {
            var changed: ?u32 = null;
            for (arcs.items) |arc| if (dist[arc.from] + arc.weight > dist[arc.to]) {
                dist[arc.to] = dist[arc.from] + arc.weight;
                pred[arc.to] = arc.from;
                changed = arc.to;
            };
            const last = changed orelse return null;
            if (round < v) continue;
            // Walk back onto the cycle, then round it.
            var on = last;
            for (0..v) |_| on = pred[on];
            var cycle: std.ArrayList(u32) = .empty;
            defer cycle.deinit(c.gpa);
            var at = on;
            while (true) {
                try cycle.append(c.gpa, at);
                at = pred[at];
                if (at == on) break;
            }
            return c.inClasses(cycle.items, source);
        }
        return null;
    }

    /// The last stated edge before `before` whose class is `root`.
    fn lastStated(c: *Checker, root: u32, source: []const u32, before: usize) ?u32 {
        var i = before;
        while (i > 0) {
            i -= 1;
            if (c.edges[i].span != null and c.find(source[i]).root == root) return @intCast(i);
        }
        return null;
    }

    /// The disagreement inside `classes`: at their last stated edge, related
    /// to their first.
    fn inClasses(c: *Checker, classes: []const u32, source: []const u32) ?Conflict {
        var first: ?u32 = null;
        var last: ?u32 = null;
        for (c.edges, source, 0..) |e, s, i| {
            if (e.span == null) continue;
            if (std.mem.indexOfScalar(u32, classes, c.find(s).root) == null) continue;
            if (first == null) first = @intCast(i);
            last = @intCast(i);
        }
        const at = last orelse return null;
        return .{ .at = at, .related = if (first.? != at) first else null };
    }

    /// Which unstated edges close a cycle, found depth first: nodes in order
    /// of appearance, each node's edges in source order.
    fn backEdges(c: *Checker, source: []const u32, target: []const u32) error{OutOfMemory}![]bool {
        const n = c.edges.len;
        const v = c.parent.items.len;
        const back = try c.gpa.alloc(bool, n);
        errdefer c.gpa.free(back);
        @memset(back, false);

        // Edges by their tail, along the flow: a span against it runs back.
        const tail = try c.gpa.alloc(u32, n);
        defer c.gpa.free(tail);
        const head = try c.gpa.alloc(u32, n);
        defer c.gpa.free(head);
        const start = try c.gpa.alloc(u32, v + 1);
        defer c.gpa.free(start);
        @memset(start, 0);
        for (c.edges, source, target, tail, head) |e, s, t, *tl, *hd| {
            const against = if (e.span) |x| x < 0 else false;
            tl.* = if (against) t else s;
            hd.* = if (against) s else t;
            start[tl.* + 1] += 1;
        }
        for (1..v + 1) |i| start[i] += start[i - 1];
        const order = try c.gpa.alloc(u32, n);
        defer c.gpa.free(order);
        const fill = try c.gpa.dupe(u32, start[0..v]);
        defer c.gpa.free(fill);
        for (tail, 0..) |tl, i| {
            order[fill[tl]] = @intCast(i);
            fill[tl] += 1;
        }

        const State = enum(u8) { unseen, open, done };
        const state = try c.gpa.alloc(State, v);
        defer c.gpa.free(state);
        @memset(state, .unseen);
        const Frame = struct { node: u32, next: u32 };
        var stack: std.ArrayList(Frame) = .empty;
        defer stack.deinit(c.gpa);
        for (0..v) |root| {
            if (state[root] != .unseen) continue;
            state[root] = .open;
            try stack.append(c.gpa, .{ .node = @intCast(root), .next = start[root] });
            while (stack.items.len > 0) {
                const top = &stack.items[stack.items.len - 1];
                if (top.next == start[top.node + 1]) {
                    state[top.node] = .done;
                    _ = stack.pop();
                    continue;
                }
                const e = order[top.next];
                top.next += 1;
                switch (state[head[e]]) {
                    .open => if (c.edges[e].span == null) {
                        back[e] = true;
                    },
                    .unseen => {
                        state[head[e]] = .open;
                        try stack.append(c.gpa, .{ .node = head[e], .next = start[head[e]] });
                    },
                    .done => {},
                }
            }
        }
        return back;
    }
};

test "stated spans agree, or not" {
    const gpa = std.testing.allocator;
    // +(f g h, m n)+: A=0, B=1, C=2, D=3, X=4; f g h then m n.
    const f: Edge = .{ .source = 0, .target = 1, .span = null };
    const g: Edge = .{ .source = 1, .target = 2, .span = null };
    const h: Edge = .{ .source = 2, .target = 3, .span = null };
    const m: Edge = .{ .source = 0, .target = 4, .span = null };
    const n: Edge = .{ .source = 4, .target = 3, .span = null };
    try std.testing.expectEqual(@as(?Conflict, null), try check(gpa, &.{ f, g, h, m, n }));
    var m1 = m;
    m1.span = 1;
    var n1 = n;
    n1.span = 1;
    try std.testing.expectEqual(@as(?Conflict, Conflict{ .at = 4, .related = 3 }), try check(gpa, &.{ f, g, h, m1, n1 }));
    var n2 = n;
    n2.span = 2;
    try std.testing.expectEqual(@as(?Conflict, null), try check(gpa, &.{ f, g, h, m1, n2 }));
    // Equalities alone: f g h all stated, against m n.
    var f1 = f;
    f1.span = 1;
    var g1 = g;
    g1.span = 1;
    var h1 = h;
    h1.span = 1;
    try std.testing.expectEqual(@as(?Conflict, null), try check(gpa, &.{ f1, g1, h1, m1, n2 }));
    try std.testing.expectEqual(@as(?Conflict, Conflict{ .at = 4, .related = 3 }), try check(gpa, &.{ f1, g1, h1, m1, n1 }));
    // A cycle no span states is a back edge; a stated loop is not.
    const back: Edge = .{ .source = 3, .target = 0, .span = null };
    try std.testing.expectEqual(@as(?Conflict, null), try check(gpa, &.{ f, g, h, back }));
    try std.testing.expectEqual(@as(?Conflict, Conflict{ .at = 0, .related = null }), try check(gpa, &.{.{ .source = 0, .target = 0, .span = 1 }}));
    // Against the flow: f two ranks on, g the same two back.
    try std.testing.expectEqual(@as(?Conflict, null), try check(gpa, &.{
        .{ .source = 0, .target = 1, .span = 2 },
        .{ .source = 1, .target = 0, .span = -2 },
    }));
}
