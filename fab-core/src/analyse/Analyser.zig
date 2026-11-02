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
//! | `definitions.zig`| the heads and entries of a definition (rule 0)    |
//!
//! Rewritten for the 1 November spec in plan step 5 (CLAUDE.md), one rule at a
//! time. So far, rules 0 and 1.

const std = @import("std");
const Cst = @import("../parse/Cst.zig");
const Ir = @import("Ir.zig");
const terms = @import("terms.zig");
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

const Zone = struct {
    index: Ir.ZoneIndex,
    /// The name in the head of its first declaration.
    token: TokenIndex,
};

/// Analyses a program. A program with syntax errors is analysed too.
pub fn analyse(gpa: std.mem.Allocator, cst: *const Cst) error{OutOfMemory}!Result {
    var a: Analyser = .{
        .gpa = gpa,
        .cst = cst,
        .builder = .init(gpa),
        .failed = try .initEmpty(gpa, cst.nodes.len),
    };
    defer a.zones.deinit(gpa);
    defer a.failed.deinit(gpa);
    errdefer a.builder.deinit();
    errdefer a.errors.deinit(gpa);

    for (cst.children(.root)) |node| {
        if (cst.tag(node) != .statement or a.hasSyntaxError(node)) continue;
        try a.statement(node);
    }

    const errors = try a.errors.toOwnedSlice(gpa);
    errdefer gpa.free(errors);
    return .{ .ir = try a.builder.finish(), .errors = errors };
}

pub fn fail(a: *Analyser, tag: Error.Tag, token: TokenIndex) error{OutOfMemory}!void {
    try a.errors.append(a.gpa, .{ .tag = tag, .token = token });
}

/// Reports an error in a term, and marks the term as failed.
pub fn failTerm(a: *Analyser, tag: Error.Tag, node: Node.Index, token: TokenIndex) error{OutOfMemory}!void {
    a.failed.set(@backingInt(node));
    try a.fail(tag, token);
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

fn statement(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    const head, const body = a.cst.data(node).nodes;
    switch (a.cst.tokenTag(a.cst.mainToken(node))) {
        .decl => try a.declaration(head, body),
        .defn => try definitions.definition(a, node, head, body),
        else => unreachable,
    }
}

/// `G :: body`. Only diagrams are declared today; nodes and edges are
/// reserved.
fn declaration(a: *Analyser, head: Node.Index, body: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    const name = cst.mainToken(head);
    if (cst.tag(head) == .leaf) switch (cst.tokenTag(name)) {
        .zone_id => try a.declareZone(name),
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
}

/// A diagram is declared once. A second declaration is still drawn, as a zone
/// of its own; references go to the first.
fn declareZone(a: *Analyser, name: TokenIndex) error{OutOfMemory}!void {
    const text = a.cst.tokenText(name);
    const index = try a.builder.addZone(.{ .name = try a.builder.addString(text), .own = null });
    const gop = try a.zones.getOrPut(a.gpa, text);
    if (gop.found_existing) {
        try a.errors.append(a.gpa, .{ .tag = .zone_declared_twice, .token = name, .related = gop.value_ptr.token });
    } else {
        gop.value_ptr.* = .{ .index = index, .token = name };
    }
}

test {
    _ = @import("analyse.test.zig");
    _ = @import("union_find.test.zig");
}
