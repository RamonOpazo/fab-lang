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
//! | `value.zig`      | what a bracket holds (step 8b)                    |
//! | `vocabulary.zig` | types, labels, signatures, named values (8c)      |
//!
//! Rewritten for the 1 November spec in plan step 5 (CLAUDE.md), one rule at a
//! time. So far, rules 0 to 3.

const std = @import("std");
const Cst = @import("../parse/Cst.zig");
const Ir = @import("Ir.zig");
const terms = @import("terms.zig");
const interface = @import("interface.zig");
const elaborate = @import("elaborate.zig");
const cells = @import("cells.zig");
const UnionFind = @import("UnionFind.zig");
const definitions = @import("definitions.zig");
const layers = @import("layers.zig");
const vocabulary = @import("vocabulary.zig");
pub const Env = @import("Env.zig");

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
    /// The names the program defined: types, values, labels, functions.
    env: Env,
    /// The layers' descriptions, resolved: what the style pass applies.
    bindings: []const layers.Binding = &.{},
    /// The tokens that name a subject, for the language server.
    references: []const layers.Reference = &.{},

    pub fn deinit(result: *Result, gpa: std.mem.Allocator) void {
        result.ir.deinit(gpa);
        result.env.deinit(gpa);
        gpa.free(result.errors);
        gpa.free(result.bindings);
        gpa.free(result.references);
        result.* = undefined;
    }
};

gpa: std.mem.Allocator,
cst: *const Cst,
builder: Ir.Builder,
errors: std.ArrayList(Error) = .empty,
/// The names defined so far, in source order (statements.md §21).
env: Env,
/// The layers' descriptions read so far, and the tokens naming subjects:
/// nodes still elements until the graph is built (`layers.finish`).
bindings: std.ArrayList(layers.PendingBinding) = .empty,
references: std.ArrayList(layers.PendingReference) = .empty,
/// Each element's IR node, once the graph is built.
node_of: []Ir.NodeIndex = &.{},
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
/// The name of each IR cell, by cell index: where the graph reports it.
cell_tokens: std.ArrayList(TokenIndex) = .empty,
/// The names of the declaration being elaborated.
scope: Scope = .{},
/// Errors reported before the graph exists, waiting for the element that
/// elaboration makes for their CST node: a term (its hole, its node), or
/// the space before a step (`joins`, by that step).
pending: Pending = .empty,
pending_joins: Pending = .empty,

pub const Pending = std.AutoHashMapUnmanaged(Node.Index, std.ArrayList(u32));

/// A diagram's names, each with its level (spec, Levels): named nodes and
/// `@` at 0, edges at 1, cells at k. At level k, a name of level k−1 is a
/// side, and a new one a k-cell.
pub const Table = std.StringHashMapUnmanaged(elaborate.Name);

/// What names mean inside one declaration.
const Scope = struct {
    zone: Ir.ZoneIndex = undefined,
    /// The level being read: 1, or a level above it.
    level: u32 = 1,
    table: Table = .empty,
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
    table: Table = .empty,
    /// Declared by a statement too broken to read: drawn as a placeholder,
    /// and what refers into it is a hole, silently.
    broken: bool = false,
};

/// Analyses a program. A program with syntax errors is analysed too. Its
/// names start as `base`'s, the prelude's (the Result takes it), or else
/// only the built-in types.
pub fn analyse(gpa: std.mem.Allocator, cst: *const Cst, base: ?Env) error{OutOfMemory}!Result {
    // Owned from here, even if analysis fails: freed here until `a` takes it.
    var owned = base;
    errdefer if (owned) |*env| env.deinit(gpa);
    var a: Analyser = .{
        .gpa = gpa,
        .cst = cst,
        .builder = .init(gpa),
        .failed = try .initEmpty(gpa, cst.nodes.len),
        .arena = .init(gpa),
        .env = undefined,
    };
    a.uf = .init(a.arena.allocator());
    defer a.arena.deinit();
    defer a.zones.deinit(gpa);
    defer a.bindings.deinit(gpa);
    defer a.references.deinit(gpa);
    defer a.failed.deinit(gpa);
    errdefer a.builder.deinit();
    errdefer a.errors.deinit(gpa);
    // Last, so the defers above are in place if it fails; the Result takes it.
    a.env = if (owned) |env| env else try .init(gpa);
    owned = null;
    errdefer a.env.deinit(gpa);

    const statements = cst.children(.root);
    for (statements, 0..) |node, i| {
        // A syntax error belongs to the statement it lies in, or whose
        // tail the parser skipped: up to the next statement.
        const start = if (i == 0) 0 else cst.firstToken(node);
        const end = if (i + 1 < statements.len) cst.firstToken(statements[i + 1]) else std.math.maxInt(TokenIndex);
        if (try a.broken(node, start, end)) continue;
        switch (cst.tag(node)) {
            .statement => try a.statement(node),
            .entry => try a.description(node),
            else => {},
        }
    }
    try elaborate.graph(&a);
    const bindings, const references = try layers.finish(&a, a.node_of);
    errdefer gpa.free(bindings);
    errdefer gpa.free(references);

    const errors = try a.errors.toOwnedSlice(gpa);
    errdefer gpa.free(errors);
    return .{ .ir = try a.builder.finish(), .errors = errors, .env = a.env, .bindings = bindings, .references = references };
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

/// A statement with syntax errors between `start` and `end` is not read
/// (spec/statements.md §15.4): its errors mark the diagram its head names,
/// declared as broken if it is new, or a placeholder. Whether it was broken.
fn broken(a: *Analyser, node: Node.Index, start: TokenIndex, end: TokenIndex) error{OutOfMemory}!bool {
    const cst = a.cst;
    var zone_index: ?Ir.ZoneIndex = null;
    for (cst.errors, 0..) |err, i| {
        if (err.token < start or err.token >= end) continue;
        const z = zone_index orelse blk: {
            const z = try a.brokenZone(cst.firstToken(node));
            zone_index = z;
            break :blk z;
        };
        try a.builder.addIssue(.{ .err = .{ .syntax = @intCast(i) }, .subject = .{ .zone = z } });
    }
    return zone_index != null;
}

fn brokenZone(a: *Analyser, head: TokenIndex) error{OutOfMemory}!Ir.ZoneIndex {
    const text = a.cst.tokenText(head);
    if (a.cst.tokenTag(head) == .zone_id) {
        if (a.zones.get(text)) |declared| return declared.index;
    }
    const index = try a.builder.addZone(.{ .name = try a.builder.addString(text), .own = null, .placeholder = true });
    if (a.cst.tokenTag(head) == .zone_id)
        try a.zones.put(a.gpa, text, .{ .index = index, .token = head, .broken = true });
    return index;
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
            try definitions.naming(a, node, head, body);
            break :blk a.namedDiagram(head);
        },
        else => unreachable,
    };
    a.pending.clearRetainingCapacity();
    a.pending_joins.clearRetainingCapacity();
    try a.markStatement(first, zone_index, head);
}

/// `G :style { … }`, `G.f :label "x"`: a layer's description, checked for
/// shape, then read (`layers.zig`). Unsupported until the style pass
/// applies it (plan step 9d): read, not drawn.
fn description(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    const first = a.errors.items.len;
    if (try definitions.description(a, node)) {
        try layers.description(a, node);
        try a.fail(.unsupported_layer, cst.firstToken(cst.children(node)[1]));
    }
    try a.markStatement(first, a.namedDiagram(node), node);
}

/// Gives the statement's errors from `first` on that have no subject of
/// their own: its diagram, or a placeholder named after `head`.
fn markStatement(a: *Analyser, first: usize, zone_index: ?Ir.ZoneIndex, head: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
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

/// The diagram a naming or a description is about: `G :style`, `G.f :label`. Its first
/// declaration, if it has one.
fn namedDiagram(a: *Analyser, head: Node.Index) ?Ir.ZoneIndex {
    const token = a.cst.firstToken(head);
    if (a.cst.tokenTag(token) != .zone_id) return null;
    const zone_entry = a.zones.get(a.cst.tokenText(token)) orelse return null;
    return zone_entry.index;
}

/// `G :: body`, a diagram; `:Shape :: [circle]`, `:Angle :: :Number!`, a type;
/// `(&node) :fill :: :Color`, a function. Nodes and edges are reserved.
/// Returns the diagram, if it is one.
fn declaration(a: *Analyser, head: Node.Index, body: Node.Index) error{OutOfMemory}!?Ir.ZoneIndex {
    const cst = a.cst;
    if (definitions.isVocabulary(cst, head)) {
        try definitions.brackets(a, body);
        if (cst.tag(head) == .leaf) try vocabulary.declareType(a, head, body) else try vocabulary.signature(a, head, body, null);
        return null;
    }
    const name = cst.mainToken(head);
    var zone_index: ?Ir.ZoneIndex = null;
    // A head that is no diagram, node, edge, type or signature says nothing
    // of what its body holds, so the body is not checked: its errors would
    // be guesses.
    if (cst.tag(head) == .leaf) switch (cst.tokenTag(name)) {
        .zone_id => zone_index = try a.declareZone(name),
        .node_id, .edge_id => try a.fail(.reserved_node_or_edge_declaration, name),
        else => {
            try a.fail(.bad_declaration_head, cst.firstToken(head));
            return null;
        },
    } else {
        try a.fail(.bad_declaration_head, cst.firstToken(head));
        return null;
    }

    // `f | g`, or the same in braces: levels of the body.
    var levels: []const Node.Index = (&body)[0..1];
    const inner = if (cst.tag(body) == .block) cst.children(body)[0] else body;
    if (cst.tag(inner) == .levels) levels = cst.children(inner);

    a.scope = .{ .zone = zone_index orelse undefined, .end = cst.lastToken(body) };
    try terms.items(a, levels[0], .item);
    try interface.items(a, levels[0]);

    // Only a diagram has a graph; a reserved head is checked, not drawn, and
    // has no names for the levels above to read.
    const z = zone_index orelse return null;
    try elaborate.items(a, levels[0]);

    // Level k is level 1 one dimension up: its sorts read the names of k−1.
    for (levels[1..], 2..) |level, k| {
        a.scope.level = @intCast(k);
        try terms.items(a, level, .item);
        try interface.items(a, level);
        try cells.level(a, level);
    }

    // The first declaration is the one other diagrams refer to.
    const entry = a.zones.getPtr(cst.tokenText(name)).?;
    if (entry.index == z) {
        entry.table = a.scope.table;
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
    _ = @import("value.zig");
    _ = @import("env.test.zig");
}
