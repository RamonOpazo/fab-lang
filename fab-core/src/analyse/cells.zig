//! Elaboration above level 1 (plan steps 7b, 7d): the cells of level k,
//! between named cells of lower levels (spec, Levels; statements.md §16). A
//! side of a level below k−1 stands for its identity; `parallel` reads it.
//!
//! Level k is level 1 one dimension up, with one difference: every side is
//! named. Nothing glues ends later, since there are no pinches and no
//! references above level 1, so no union-find is needed: each end of a cell
//! is settled inside its own term. An end is a slot of its cell, which is
//! open, holds a side, or has failed; attaching is a meeting of two ports.
//!
//! Runs after rules 0–2 at this level, so every term it meets is well typed
//! or has failed. A cell with a failed end is left out of the IR, and its
//! name is a hole: what uses it as a side stays quiet.

const std = @import("std");
const Cst = @import("../parse/Cst.zig");
const Ir = @import("Ir.zig");
const Analyser = @import("Analyser.zig");
const sort = @import("sort.zig");

const Node = Cst.Node;
const TokenIndex = Cst.TokenIndex;

/// A named cell of a lower level. A node is its union-find element until
/// the graph is built, which makes it a node (`elaborate.graph`).
const Side = Ir.Cell.Side;

/// What a term exposes on one side.
const Port = union(enum) {
    side: Side,
    /// One end of a cell of this level.
    slot: Slot,
    /// Part of a failed term: it meets anything, quietly.
    failed,
};

const Slot = struct { cell: u32, end: enum { left, right } };

/// What a slot holds.
const Value = union(enum) { open, side: Side, failed };

/// A cell of this level, until the level ends.
const Cell = struct {
    token: TokenIndex,
    left: Value = .open,
    right: Value = .open,
    directed: bool = true,
};

const Ports = struct {
    left: []const Port,
    right: []const Port,

    fn both(ports: []const Port) Ports {
        return .{ .left = ports, .right = ports };
    }
};

const Level = struct {
    a: *Analyser,
    cells: std.ArrayList(Cell) = .empty,
    /// Errors that mark a cell of this level, by its place in `cells`.
    marks: std.ArrayList(struct { err: u32, cell: u32 }) = .empty,

    fn arena(l: *Level) std.mem.Allocator {
        return l.a.arena.allocator();
    }
};

/// Elaborates a level above the first, then adds its cells to the IR. Each
/// item settles the ends of the cells it declares.
pub fn level(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    var l: Level = .{ .a = a };
    try items(&l, node);

    // A cell is drawn when both its ends hold a side; the level above reads
    // its name as a side, or as a hole.
    const k = a.scope.level;
    const index = try l.arena().alloc(?u32, l.cells.items.len);
    for (l.cells.items, index) |cell, *i| {
        const entry = a.scope.table.getPtr(a.cst.tokenText(cell.token)).?;
        if (cell.left != .side or cell.right != .side) {
            i.* = null;
            entry.* = .{ .level = k, .is = .{ .hole = null } };
            continue;
        }
        const c = try a.builder.addCell(.{
            .name = try a.builder.addString(a.cst.tokenText(cell.token)),
            .level = k,
            .source = cell.left.side,
            .target = cell.right.side,
            .directed = cell.directed,
            .zone = a.zone(),
        });
        try a.cell_tokens.append(l.arena(), cell.token);
        i.* = @backingInt(c);
        entry.* = .{ .level = k, .is = .{ .generator = .{ .index = i.*.?, .token = cell.token } } };
    }
    // A cell left out leaves its error on the diagram.
    for (l.marks.items) |m| {
        if (index[m.cell]) |c| a.errors.items[m.err].subject = .{ .cell = c };
    }
}

fn items(l: *Level, node: Node.Index) error{OutOfMemory}!void {
    const cst = l.a.cst;
    switch (cst.tag(node)) {
        .items => for (cst.children(node)) |item| try items(l, item),
        .block => try items(l, cst.children(node)[0]),
        else => {
            const first = l.cells.items.len;
            _ = try term(l, node);
            // Nothing attaches to an item from outside: an end still open is
            // a side nobody named.
            for (l.cells.items[first..]) |*cell| {
                if (cell.left != .open and cell.right != .open) continue;
                try l.a.fail(.unnamed_side, cell.token);
                if (cell.left == .open) cell.left = .failed;
                if (cell.right == .open) cell.right = .failed;
            }
        },
    }
}

fn term(l: *Level, node: Node.Index) error{OutOfMemory}!Ports {
    const a = l.a;
    if (a.failed.isSet(@backingInt(node))) return failedTerm(l, node);
    const cst = a.cst;
    return switch (cst.tag(node)) {
        .leaf => leaf(l, node),
        .group => group(l, cst.children(node)[0]),
        .o_chain => openChain(l, node),
        .c_chain => closedChain(l, node),
        .postfix => undirected(l, cst.data(node).node),
        // Pinches, other diagrams and the rest failed in rule 1.
        else => failedTerm(l, node),
    };
}

/// A trailing `/` on a single cell, `α/`: a cell is its own way back. Rule 2
/// failed it on anything else.
fn undirected(l: *Level, node: Node.Index) error{OutOfMemory}!Ports {
    const first = l.cells.items.len;
    const p = try term(l, node);
    undirect(l, first);
    return p;
}

/// The cells a term declared, from `first` on, are undirected. A name
/// declared twice declares nothing, and keeps its first direction.
fn undirect(l: *Level, first: usize) void {
    for (l.cells.items[first..]) |*cell| cell.directed = false;
}

fn one(l: *Level, port: Port) error{OutOfMemory}!Ports {
    const ports = try l.arena().alloc(Port, 1);
    ports[0] = port;
    return .both(ports);
}

/// A side, or a new cell with two open ends. A name of this level declared
/// again is a cell declared twice; a hole is quiet. Named nodes and `@` are
/// sides of level 0, which rule 1 found in the table.
fn leaf(l: *Level, node: Node.Index) error{OutOfMemory}!Ports {
    const a = l.a;
    const cst = a.cst;
    const token = cst.mainToken(node);
    const text = switch (cst.tokenTag(token)) {
        .edge_id, .node_id => cst.tokenText(token),
        .at => "@",
        else => return failedTerm(l, node),
    };
    if (cst.tokenTag(token) != .edge_id or sort.isSide(a, token)) {
        const name = a.scope.table.get(text).?;
        return one(l, switch (name.is) {
            .node => |e| .{ .side = .{ .node = @fromBackingInt(e) } },
            .generator => |g| .{ .side = if (name.level == 1) .{ .edge = @fromBackingInt(g.index) } else .{ .cell = @fromBackingInt(g.index) } },
            .hole => .failed,
        });
    }

    const gop = try a.scope.table.getOrPut(l.arena(), text);
    if (gop.found_existing) {
        switch (gop.value_ptr.is) {
            .generator => |first| try a.errors.append(a.gpa, .{ .tag = .edge_declared_twice, .token = token, .related = first.token }),
            .hole, .node => {},
        }
        return one(l, .failed);
    }
    const i: u32 = @intCast(l.cells.items.len);
    try l.cells.append(l.arena(), .{ .token = token });
    gop.value_ptr.* = .{ .level = a.scope.level, .is = .{ .generator = .{ .index = i, .token = token } } };

    const ports = try l.arena().alloc(Port, 2);
    ports[0] = .{ .slot = .{ .cell = i, .end = .left } };
    ports[1] = .{ .slot = .{ .cell = i, .end = .right } };
    return .{ .left = ports[0..1], .right = ports[1..2] };
}

/// A failed term: the new names in it are holes, and it meets anything.
fn failedTerm(l: *Level, node: Node.Index) error{OutOfMemory}!Ports {
    const a = l.a;
    const cst = a.cst;
    for (cst.firstToken(node)..cst.lastToken(node) + 1) |t| {
        const token: TokenIndex = @intCast(t);
        if (cst.tokenTag(token) != .edge_id) continue;
        const gop = try a.scope.table.getOrPut(l.arena(), cst.tokenText(token));
        if (!gop.found_existing) gop.value_ptr.* = .{ .level = a.scope.level, .is = .{ .hole = null } };
    }
    return one(l, .failed);
}

/// `(s, t)`: the ports of the branches, side by side.
fn group(l: *Level, inner: Node.Index) error{OutOfMemory}!Ports {
    const cst = l.a.cst;
    if (cst.tag(inner) != .items) return term(l, inner);
    var left: std.ArrayList(Port) = .empty;
    var right: std.ArrayList(Port) = .empty;
    for (cst.children(inner)) |item| {
        const p = try term(l, item);
        try left.appendSlice(l.arena(), p.left);
        try right.appendSlice(l.arena(), p.right);
    }
    return .{ .left = left.items, .right = right.items };
}

/// `s t …`: each space meets one with one. An error at a space marks the
/// first cell of the step after it.
fn openChain(l: *Level, node: Node.Index) error{OutOfMemory}!Ports {
    const cst = l.a.cst;
    const steps = cst.children(node);
    const first = try term(l, steps[0]);
    var prev = first;
    for (steps[1..]) |step| {
        const cell: u32 = @intCast(l.cells.items.len);
        const next = try term(l, step);
        const mark: ?u32 = if (l.cells.items.len > cell) cell else null;
        if (prev.right.len == 1 and next.left.len == 1) {
            try meet(l, prev.right[0], next.left[0], cst.firstToken(step), mark);
        } else {
            // Rule 2 reported it.
            failAll(l, prev.right);
            failAll(l, next.left);
        }
        prev = next;
    }
    return .{ .left = first.left, .right = prev.right };
}

/// `a/b/…`. One cell attaches to the sides beside it, distributing over a
/// group; two or more close a cycle on its start.
fn closedChain(l: *Level, node: Node.Index) error{OutOfMemory}!Ports {
    const a = l.a;
    const cst = a.cst;
    const links = cst.children(node);
    const last = links.len - 1;

    // A trailing `/` belongs to the whole chain, and undirects its cells:
    // `f/α/g/` is undirected α, `α/β/` an undirected cycle.
    const trailing = cst.tag(links[last]) == .postfix and cst.tokenTag(cst.mainToken(links[last])) == .slash;
    const ports = try l.arena().alloc(Ports, links.len);
    const first = l.cells.items.len;
    var cells: usize = 0;
    for (links, ports, 0..) |link, *p, i| {
        const one_link = if (i == last and trailing) cst.data(link).node else link;
        p.* = try term(l, one_link);
        if (sort.of(a, one_link) == .edges) cells += 1;
    }
    if (trailing) undirect(l, first);
    // `α/α`: a cell from its own target to its own source.
    if (links.len == 2 and cells == 2 and isSame(cst, links[0], links[1])) {
        try slash(l, ports[0].right, ports[0].left, cst.lastToken(links[0]) + 1);
        return .{ .left = ports[0].left, .right = &.{} };
    }
    for (ports[0..last], ports[1..], links[0..last]) |left, right, link| try slash(l, left.right, right.left, cst.lastToken(link) + 1);
    if (cells > 1) {
        const token = cst.lastToken(links[last - 1]) + 1;
        const end = if (trailing) cst.data(links[last]).node else links[last];
        if (sort.of(a, end) == .node and !closes(l, ports[last].right, ports[0].left)) {
            try a.fail(.cycle_does_not_close, cst.firstToken(links[last]));
        } else try slash(l, ports[last].right, ports[0].left, token);
        return .{ .left = ports[0].left, .right = &.{} };
    }
    return .{ .left = ports[0].left, .right = ports[last].right };
}

fn isSame(cst: *const Cst, x: Node.Index, y: Node.Index) bool {
    return sort.isLeaf(cst, x, .edge_id) and sort.isLeaf(cst, y, .edge_id) and
        std.mem.eql(u8, cst.tokenText(cst.mainToken(x)), cst.tokenText(cst.mainToken(y)));
}

/// A cycle that ends on a side must end on its start. A failed one closes
/// anything.
fn closes(l: *Level, end: []const Port, start: []const Port) bool {
    if (end.len != 1 or start.len != 1) return true;
    const e = value(l, end[0]);
    const s = value(l, start[0]);
    if (e != .side or s != .side) return true;
    return std.meta.eql(e.side, s.side);
}

/// One side of a `/` is one port, meeting every port on the other. Anything
/// else was reported by rule 2.
fn slash(l: *Level, left: []const Port, right: []const Port, token: TokenIndex) error{OutOfMemory}!void {
    if (left.len == 1 and right.len >= 1) {
        for (right) |p| try meet(l, left[0], p, token, null);
    } else if (right.len == 1 and left.len >= 1) {
        for (left) |p| try meet(l, p, right[0], token, null);
    } else {
        failAll(l, left);
        failAll(l, right);
    }
}

/// Two ports in one place. An open end takes the side it meets; two open
/// ends would need a side nobody named; two sides must be the same.
fn meet(l: *Level, x: Port, y: Port, token: TokenIndex, mark: ?u32) error{OutOfMemory}!void {
    const vx = value(l, x);
    const vy = value(l, y);
    if (vx == .failed or vy == .failed) {
        failAll(l, &.{ x, y });
    } else if (vx == .open and vy == .open) {
        try l.a.fail(.unnamed_side, token);
        failAll(l, &.{ x, y });
    } else if (vx == .open) {
        slotOf(l, x).* = vy;
    } else if (vy == .open) {
        slotOf(l, y).* = vx;
    } else if (!std.meta.eql(vx.side, vy.side)) {
        if (mark) |cell| try l.marks.append(l.arena(), .{ .err = @intCast(l.a.errors.items.len), .cell = cell });
        try l.a.fail(.two_names_for_one_side, token);
    }
}

fn value(l: *Level, port: Port) Value {
    return switch (port) {
        .side => |s| .{ .side = s },
        .slot => slotOf(l, port).*,
        .failed => .failed,
    };
}

fn slotOf(l: *Level, port: Port) *Value {
    const cell = &l.cells.items[port.slot.cell];
    return if (port.slot.end == .left) &cell.left else &cell.right;
}

/// Every open end among `ports` fails, quietly.
fn failAll(l: *Level, ports: []const Port) void {
    for (ports) |p| {
        if (p != .slot) continue;
        const v = slotOf(l, p);
        if (v.* == .open) v.* = .failed;
    }
}
