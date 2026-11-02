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
//! Rewritten for the 1 November spec in plan step 5 (CLAUDE.md), one rule at a
//! time. So far, rule 0: which items each statement holds, and its head.

const std = @import("std");
const builtin = @import("builtin");
const Cst = @import("../parse/Cst.zig");
const Ir = @import("Ir.zig");

const Analyser = @This();
const Node = Cst.Node;
const TokenIndex = Cst.TokenIndex;

pub const Error = struct {
    tag: Tag,
    /// Where the error is reported.
    token: TokenIndex,
    /// Where the conflicting thing was first declared, when that helps.
    related: ?TokenIndex = null,
    /// What to mark in the graph, if anything.
    subject: ?Subject = null,

    pub const Tag = enum(u8) {
        // -- statements (rule 0) ---------------------------------------------

        /// `G :: f (g :label "x")`, `G :: f == g`.
        entry_in_declaration,
        /// `G :: &node f`.
        class_in_declaration,
        /// `G :: +(g1, [f], g2)`.
        value_in_declaration,
        /// `yes, paid :label "yes"`: the bare `yes`.
        bare_term_in_definition,
        /// `:x := a | b`.
        levels_in_definition,
        /// `[red] :: f`, `G :style :: f`.
        bad_declaration_head,
        /// `f g := [red]`, `G := [red]`.
        bad_definition_head,
        /// `f == g ~= h`.
        mixed_operators,
        /// `G :: f` … `G :: g`.
        zone_declared_twice,
        /// Warning. `f g` then `h k` on the next line, in braces.
        chain_broken_across_lines,

        // -- reserved: the spec has not decided (statements.md §15) ----------

        /// `#User :: @/(id, name)`, `review :: a b`.
        reserved_node_or_edge_declaration,

        // -- unsupported: the compiler has not caught up (statements.md §15) -

        /// Levels above the first, until plan step 7.
        unsupported_levels,
        /// The contents of a definition, until plan steps 8–11.
        unsupported_definition,

        pub fn severity(tag: Tag) Severity {
            return switch (tag) {
                .chain_broken_across_lines => .warning,
                .unsupported_levels, .unsupported_definition => .unsupported,
                else => .@"error",
            };
        }
    };

    /// An error's own severity, before the compiler promotes anything.
    /// Reserved tags are plain errors; only their message says they are
    /// reserved.
    pub const Severity = enum { warning, @"error", unsupported };
};

// Unsupported never ships (statements.md §15): a release build refuses to
// compile while any unsupported tag remains.
comptime {
    if (builtin.mode != .debug) for (std.enums.values(Error.Tag)) |tag| {
        if (tag.severity() == .unsupported)
            @compileError("unsupported construct in a release build: " ++ @tagName(tag));
    };
}

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

const Zone = struct {
    index: Ir.ZoneIndex,
    /// The name in the head of its first declaration.
    token: TokenIndex,
};

/// Analyses a program. A program with syntax errors is analysed too.
pub fn analyse(gpa: std.mem.Allocator, cst: *const Cst) error{OutOfMemory}!Result {
    var a: Analyser = .{ .gpa = gpa, .cst = cst, .builder = .init(gpa) };
    defer a.zones.deinit(gpa);
    errdefer a.builder.deinit();
    errdefer a.errors.deinit(gpa);

    for (cst.children(.root)) |node| {
        if (cst.tag(node) != .statement or a.hasSyntaxError(node)) continue;
        try a.statement(node);
    }

    const ir = try a.builder.finish();
    return .{ .ir = ir, .errors = try a.errors.toOwnedSlice(gpa) };
}

fn fail(a: *Analyser, tag: Error.Tag, token: TokenIndex) error{OutOfMemory}!void {
    try a.errors.append(a.gpa, .{ .tag = tag, .token = token });
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
        .defn => try a.definition(node, head, body),
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
    try a.terms(first, .item);
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

/// Where a list of terms sits: as items of a body or a block, or inside a
/// group.
const Place = enum { item, group };

/// The items of a declaration: terms, side by side.
fn terms(a: *Analyser, node: Node.Index, place: Place) error{OutOfMemory}!void {
    const cst = a.cst;
    switch (cst.tag(node)) {
        .items => for (cst.children(node)) |item| try a.terms(item, place),
        // Braces without a subject only organise; levels inside them are
        // levels of the same body.
        .block => {
            const inner = cst.children(node)[0];
            if (cst.tag(inner) == .levels) {
                try a.fail(.unsupported_levels, cst.mainToken(inner));
                try a.terms(cst.children(inner)[0], place);
            } else try a.terms(inner, place);
        },
        else => {
            if (place == .item) try a.brokenChain(node);
            try a.term(node);
        },
    }
}

/// Checks that a term holds only structure: edges, nodes and groups of them.
fn term(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    switch (cst.tag(node)) {
        .entry, .operation => try a.fail(.entry_in_declaration, cst.firstToken(node)),
        .leaf => switch (cst.tokenTag(cst.mainToken(node))) {
            .class_id => try a.fail(.class_in_declaration, cst.mainToken(node)),
            .str, .math, .val => try a.fail(.value_in_declaration, cst.mainToken(node)),
            else => {},
        },
        .group => try a.terms(cst.children(node)[0], .group),
        .invalid => {},
        else => for (cst.children(node)) |child| try a.term(child),
    }
}

/// Warns about an open chain whose steps continue on the next line: in
/// braces a newline is a space, so `f g` then `h k` is one chain, `f g h k`.
/// The chain must be an item of its own; inside a group it is clearly meant.
fn brokenChain(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    if (cst.tag(node) != .o_chain) return;
    const steps = cst.children(node);
    for (steps[0 .. steps.len - 1], steps[1..]) |left, right| {
        const after = cst.firstToken(right);
        for (cst.lastToken(left) + 1..after) |t| {
            if (cst.tokenTag(@intCast(t)) == .eol) return a.fail(.chain_broken_across_lines, after);
        }
    }
}

/// `head := body`. The head has one of three forms; the body holds entries,
/// operations and, alone, a literal. What a definition means waits for plan
/// steps 8–11.
fn definition(a: *Analyser, node: Node.Index, head: Node.Index, body: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    if (!a.isDefinitionHead(head)) try a.fail(.bad_definition_head, cst.firstToken(head));

    if (cst.tag(body) == .levels) {
        try a.fail(.levels_in_definition, cst.mainToken(body));
    } else if (!isLiteral(cst, body)) {
        try a.entries(body);
    }
    try a.fail(.unsupported_definition, cst.mainToken(node));
}

/// `[name]`, `:attr` or `subject :attr`: one attribute, with no value.
fn isDefinitionHead(a: *Analyser, head: Node.Index) bool {
    const cst = a.cst;
    return switch (cst.tag(head)) {
        .leaf => cst.tokenTag(cst.mainToken(head)) == .val,
        .attr => cst.data(head).node == .root,
        .entry => blk: {
            const attrs = cst.list(cst.data(head).range)[1..];
            break :blk attrs.len == 1 and cst.tag(attrs[0]) == .attr and cst.data(attrs[0]).node == .root;
        },
        else => false,
    };
}

fn isLiteral(cst: *const Cst, node: Node.Index) bool {
    return cst.tag(node) == .leaf and switch (cst.tokenTag(cst.mainToken(node))) {
        .str, .math, .val => true,
        else => false,
    };
}

/// The items of a definition: entries and operations, side by side.
fn entries(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    switch (cst.tag(node)) {
        .items => for (cst.children(node)) |item| try a.entries(item),
        .block => {
            const inner = cst.children(node)[0];
            if (cst.tag(inner) == .levels) {
                try a.fail(.levels_in_definition, cst.mainToken(inner));
            } else try a.entries(inner);
        },
        .entry => {
            // `subject { … }`: the block holds the subject's entries.
            const parts = cst.children(node);
            const last = parts[parts.len - 1];
            if (cst.tag(last) == .block) try a.entries(last);
        },
        .operation => try a.operation(node),
        // A group of propositions: `(f h == g k, +f :pullback)`.
        .group => try a.entries(cst.children(node)[0]),
        .invalid => {},
        else => try a.fail(.bare_term_in_definition, cst.firstToken(node)),
    }
}

/// One operator per run; different ones need a group. Groups among the
/// operands hold runs of their own.
fn operation(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    const operands = cst.children(node);
    const first = cst.tokenTag(cst.operator(node, 0));
    for (1..operands.len - 1) |i| {
        const op = cst.operator(node, i);
        if (cst.tokenTag(op) != first) {
            try a.fail(.mixed_operators, op);
            break;
        }
    }
    for (operands) |operand| try a.nestedOperations(operand);
}

fn nestedOperations(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    switch (a.cst.tag(node)) {
        .operation => try a.operation(node),
        .entry, .leaf, .invalid => {},
        else => for (a.cst.children(node)) |child| try a.nestedOperations(child),
    }
}

test {
    _ = @import("analyse.test.zig");
    _ = @import("union_find.test.zig");
}
