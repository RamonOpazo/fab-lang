//! Turns a concrete syntax tree into the IR, and reports what is wrong with it.
//!
//! The analyser always produces an IR, valid program or not, together with the
//! errors it found. Deciding whether an IR with errors is acceptable belongs to
//! the compiler, not to this file.
//!
//! Statements are analysed one at a time, in source order, so references can
//! only point left. A statement with a syntax error is skipped: the parser
//! already said what is wrong with it, and the rest of the program is still
//! analysed.
//!
//! This file is the driver and the shared state; each concern is a namespace
//! of functions over `*Analyser`:
//!
//! | File             | What                                              |
//! | ---------------- | ------------------------------------------------- |
//! | `Error.zig`      | the error tags, their severity, the release guard |
//! | `sort.zig`       | what a term is, from its shape: node or edges     |
//! | `terms.zig`      | the terms of a declaration (rules 0–1)            |
//! | `interface.zig`  | each term's sides, and what a space joins (rule 2)|
//! | `elaborate.zig`  | terms into nodes and edges (rules 3 on)           |
//! | `definitions.zig`| the heads and entries of a definition (rule 0)    |
//!
//! Rewritten for the 1 November spec in plan step 5 (CLAUDE.md), one rule at a
//! time. So far, rules 0 to 3.

const std = @import("std");
const Cst = @import("../parse/Cst.zig");
const Ir = @import("Ir.zig");
const terms = @import("terms.zig");
const interface = @import("interface.zig");
const elaborate = @import("elaborate.zig");
const UnionFind = @import("UnionFind.zig");
const definitions = @import("definitions.zig");

const Analyser = @This();
const Node = Cst.Node;
const TokenIndex = Cst.TokenIndex;

pub const Error = @import("Error.zig");

/// An element of the graph under construction, before it becomes part of the
/// IR: a union-find element (whose class is a node), an edge, a cell or a zone.
pub const Subject = union(enum) {
    elem: u32,
    edge: u32,
    cell: u32,
    zone: u32,
};

/// Always an IR, and the errors found while building it. Errors with a
/// subject appear in the IR's issues table.
pub const Result = struct {
    ir: Ir,
    errors: []const Error,

    pub fn deinit(result: *Result, gpa: std.mem.Allocator) void {
        result.ir.deinit(gpa);
        gpa.free(result.errors);
        result.* = undefined;
    }
};

gpa: std.mem.Allocator,
cst: *const Cst,
builder: Ir.Builder,
errors: std.ArrayList(Error) = .empty,
/// The zones declared so far, by name: the first declaration of each.
zones: std.StringHashMapUnmanaged(Zone) = .empty,
/// The CST nodes of terms with an error. A failed term becomes a hole, so
/// its neighbours report nothing more about it.
failed: std.DynamicBitSetUnmanaged = .{},
/// Elaboration's working memory, freed when analysis ends.
arena: std.heap.ArenaAllocator,
/// The edge ends and named nodes of every declaration; a class is a node.
uf: UnionFind = undefined,
/// The start and end elements of each IR edge, by edge index.
edge_ends: std.ArrayList([2]u32) = .empty,
/// The names of the declaration being elaborated.
scope: Scope = .{},
/// Errors reported before the graph exists, waiting for the element that
/// elaboration makes for their CST node: a term (its hole, its node), or
/// the space before a step (`joins`, by that step).
pending: Pending = .empty,
pending_joins: Pending = .empty,

pub const Pending = std.AutoHashMapUnmanaged(Node.Index, std.ArrayList(u32));

/// What names mean inside one declaration.
const Scope = struct {
    zone: Ir.ZoneIndex = undefined,
    edges: std.StringHashMapUnmanaged(elaborate.Binding) = .empty,
    /// Named nodes, `@` and diagram names, by name.
    names: std.StringHashMapUnmanaged(u32) = .empty,
    /// The declaration's last token: references look ahead to it.
    end: TokenIndex = 0,
    /// The outermost closed chain being elaborated, first and last token.
    chain: ?[2]TokenIndex = null,
    /// How many pinches the term being elaborated is inside.
    pinches: u32 = 0,
};

pub const Zone = struct {
    index: Ir.ZoneIndex,
    /// The name in the head of its first declaration.
    token: TokenIndex,
    /// What its names mean, once elaborated: other diagrams reach in through
    /// them (`A.+f`, `A.#X`, `A.@`, `A`).
    edges: std.StringHashMapUnmanaged(elaborate.Binding) = .empty,
    names: std.StringHashMapUnmanaged(u32) = .empty,
};

/// Analyses a program. A program with syntax errors is analysed too.
pub fn analyse(gpa: std.mem.Allocator, cst: *const Cst) error{OutOfMemory}!Result {
    var a: Analyser = .{
        .gpa = gpa,
        .cst = cst,
        .builder = .init(gpa),
        .failed = try .initEmpty(gpa, cst.nodes.len),
        .arena = .init(gpa),
    };
    a.uf = .init(a.arena.allocator());
    defer a.arena.deinit();
    defer a.zones.deinit(gpa);
    defer a.failed.deinit(gpa);
    errdefer a.builder.deinit();
    errdefer a.errors.deinit(gpa);

    for (cst.children(.root)) |node| {
        if (cst.tag(node) != .statement or a.hasSyntaxError(node)) continue;
        try a.statement(node);
    }
    try elaborate.graph(&a);

    const errors = try a.errors.toOwnedSlice(gpa);
    errdefer gpa.free(errors);
    return .{ .ir = try a.builder.finish(), .errors = errors };
}

/// The zone of the declaration being elaborated.
pub fn zone(a: *const Analyser) Ir.ZoneIndex {
    return a.scope.zone;
}

/// Reports an error. Its subject is its statement's diagram, or the
/// statement's placeholder, unless something more precise claims it.
pub fn fail(a: *Analyser, tag: Error.Tag, token: TokenIndex) error{OutOfMemory}!void {
    try a.errors.append(a.gpa, .{ .tag = tag, .token = token });
}

/// Reports an error that marks an element already made.
pub fn failOn(a: *Analyser, tag: Error.Tag, token: TokenIndex, subject: Subject) error{OutOfMemory}!void {
    try a.errors.append(a.gpa, .{ .tag = tag, .token = token, .subject = subject });
}

/// Reports an error about a term, to mark whatever elaboration makes of it.
pub fn failAt(a: *Analyser, tag: Error.Tag, token: TokenIndex, node: Node.Index) error{OutOfMemory}!void {
    try a.wait(&a.pending, node);
    try a.fail(tag, token);
}

/// Reports an error in a term, and marks the term as failed: it becomes a
/// hole, which the error marks.
pub fn failTerm(a: *Analyser, tag: Error.Tag, node: Node.Index, token: TokenIndex) error{OutOfMemory}!void {
    a.failed.set(@backingInt(node));
    try a.failAt(tag, token, node);
}

/// Reports an error about the space before `step`, to mark the node it makes.
pub fn failJoin(a: *Analyser, tag: Error.Tag, token: TokenIndex, step: Node.Index) error{OutOfMemory}!void {
    try a.wait(&a.pending_joins, step);
    try a.fail(tag, token);
}

/// The next error waits in `map`, under `node`.
fn wait(a: *Analyser, map: *Pending, node: Node.Index) error{OutOfMemory}!void {
    const arena = a.arena.allocator();
    const gop = try map.getOrPut(arena, node);
    if (!gop.found_existing) gop.value_ptr.* = .empty;
    try gop.value_ptr.append(arena, @intCast(a.errors.items.len));
}

/// Gives the errors waiting under `node` their element.
pub fn settle(a: *Analyser, map: *Pending, node: Node.Index, elem: u32) void {
    const entry = map.fetchRemove(node) orelse return;
    for (entry.value.items) |i| a.errors.items[i].subject = .{ .elem = elem };
}

/// Whether the parser reported anything inside a statement.
fn hasSyntaxError(a: *Analyser, node: Node.Index) bool {
    const first = a.cst.firstToken(node);
    const last = a.cst.lastToken(node);
    for (a.cst.errors) |err| {
        if (err.token >= first and err.token <= last) return true;
    }
    return false;
}

// ---------------------------------------------------------------------------
// Statements

/// A statement, and the subject of its errors that have none of their own:
/// its diagram, or a placeholder when it names none, so that every
/// statement with an issue draws something.
fn statement(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    const head, const body = cst.data(node).nodes;
    const first = a.errors.items.len;
    const zone_index: ?Ir.ZoneIndex = switch (cst.tokenTag(cst.mainToken(node))) {
        .decl => try a.declaration(head, body),
        .defn => blk: {
            try definitions.definition(a, node, head, body);
            break :blk a.namedDiagram(head);
        },
        else => unreachable,
    };
    a.pending.clearRetainingCapacity();
    a.pending_joins.clearRetainingCapacity();

    const rest = a.errors.items[first..];
    for (rest) |err| {
        if (err.subject == null) break;
    } else return;
    const z = zone_index orelse try a.builder.addZone(.{
        .name = try a.builder.addString(cst.tokenText(cst.firstToken(head))),
        .own = null,
        .placeholder = true,
    });
    for (rest) |*err| {
        if (err.subject == null) err.subject = .{ .zone = @backingInt(z) };
    }
}

/// The diagram a definition is about: `G :style`, `G.f :label`. Its first
/// declaration, if it has one.
fn namedDiagram(a: *Analyser, head: Node.Index) ?Ir.ZoneIndex {
    const token = a.cst.firstToken(head);
    if (a.cst.tokenTag(token) != .zone_id) return null;
    const zone_entry = a.zones.get(a.cst.tokenText(token)) orelse return null;
    return zone_entry.index;
}

/// `G :: body`. Only diagrams are declared today; nodes and edges are
/// reserved. Returns the diagram, if it is one.
fn declaration(a: *Analyser, head: Node.Index, body: Node.Index) error{OutOfMemory}!?Ir.ZoneIndex {
    const cst = a.cst;
    const name = cst.mainToken(head);
    var zone_index: ?Ir.ZoneIndex = null;
    if (cst.tag(head) == .leaf) switch (cst.tokenTag(name)) {
        .zone_id => zone_index = try a.declareZone(name),
        .node_id, .edge_id => try a.fail(.reserved_node_or_edge_declaration, name),
        else => try a.fail(.bad_declaration_head, cst.firstToken(head)),
    } else try a.fail(.bad_declaration_head, cst.firstToken(head));

    // Only the first level is analysed; the others wait for plan step 7.
    var first = body;
    if (cst.tag(body) == .levels) {
        first = cst.children(body)[0];
        try a.fail(.unsupported_levels, cst.mainToken(body));
    }
    try terms.items(a, first, .item);
    try interface.items(a, first);

    // Only a diagram has a graph; a reserved head is checked, not drawn.
    const z = zone_index orelse return null;
    a.scope = .{ .zone = z, .end = cst.lastToken(body) };
    try elaborate.items(a, first);

    // The first declaration is the one other diagrams refer to.
    const entry = a.zones.getPtr(cst.tokenText(name)).?;
    if (entry.index == z) {
        entry.edges = a.scope.edges;
        entry.names = a.scope.names;
    }
    return z;
}

/// A diagram is declared once. A second declaration is still drawn, as a zone
/// of its own; references go to the first.
fn declareZone(a: *Analyser, name: TokenIndex) error{OutOfMemory}!Ir.ZoneIndex {
    const text = a.cst.tokenText(name);
    const index = try a.builder.addZone(.{ .name = try a.builder.addString(text), .own = null });
    const gop = try a.zones.getOrPut(a.gpa, text);
    if (gop.found_existing) {
        try a.errors.append(a.gpa, .{ .tag = .zone_declared_twice, .token = name, .related = gop.value_ptr.token });
    } else {
        gop.value_ptr.* = .{ .index = index, .token = name };
    }
    return index;
}

test {
    _ = @import("analyse.test.zig");
    _ = @import("union_find.test.zig");
}
