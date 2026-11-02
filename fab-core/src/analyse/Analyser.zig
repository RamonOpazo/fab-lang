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
const Token = @import("../lex/Token.zig");
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

        // -- sorts (rule 1) --------------------------------------------------

        /// `#A f`, `* f`, `@ (f)`, `? f`.
        node_beside_space,
        /// `f? (g, h)`, `k +f`, `f+ g`.
        pinched_edge_beside_space,
        /// `*/f/*`.
        both_ends_null,
        /// `*`, `f/*/g`, `*/f/g`.
        null_not_on_one_end,
        /// `?(g, h)`, `!f`, `?/f`, `f/?/g`.
        kind_on_the_left,
        /// `f/g/?`.
        kind_closes_cycle,
        /// `?`, `(!)`.
        lone_kind,
        /// `f?`, `A.f/?`.
        kind_on_reference,
        /// `(a, b)/?`.
        kind_after_group,
        /// Warning. `(f)/?`.
        kind_after_group_of_one,

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
                .chain_broken_across_lines, .kind_after_group_of_one => .warning,
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

fn fail(a: *Analyser, tag: Error.Tag, token: TokenIndex) error{OutOfMemory}!void {
    try a.errors.append(a.gpa, .{ .tag = tag, .token = token });
}

/// Reports an error in a term, and marks the term as failed.
fn failTerm(a: *Analyser, tag: Error.Tag, node: Node.Index, token: TokenIndex) error{OutOfMemory}!void {
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

/// Checks a term: it holds only structure, edges and nodes (rule 0), and
/// each node term stands where its sort allows (rule 1). A term with an error
/// is not looked into further.
fn term(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    const main = cst.mainToken(node);
    switch (cst.tag(node)) {
        .entry, .operation => try a.failTerm(.entry_in_declaration, node, cst.firstToken(node)),
        // Chains judge the leaves in them; a leaf reaching here stands alone.
        .leaf => switch (cst.tokenTag(main)) {
            .class_id => try a.failTerm(.class_in_declaration, node, main),
            .str, .math, .val => try a.failTerm(.value_in_declaration, node, main),
            .star => try a.failTerm(.null_not_on_one_end, node, main),
            .quid, .bang => try a.failTerm(.lone_kind, node, main),
            else => {},
        },
        .group => try a.terms(cst.children(node)[0], .group),
        .o_chain => for (cst.children(node)) |step| {
            if (sort(cst, step) == .edges) {
                try a.term(step);
            } else if (isPinchedEdge(cst, step)) {
                try a.failTerm(.pinched_edge_beside_space, step, cst.firstToken(step));
            } else {
                try a.failTerm(.node_beside_space, step, cst.firstToken(step));
            }
        },
        .c_chain => try a.closedChain(node),
        .prefix => switch (cst.tokenTag(main)) {
            .quid, .bang => try a.failTerm(.kind_on_the_left, node, main),
            else => try a.markerOperand(cst.data(node).node),
        },
        .postfix => switch (cst.tokenTag(main)) {
            .quid, .bang => if (isSingleEdge(cst, cst.data(node).node)) {
                try a.failTerm(.kind_on_reference, node, main);
            } else try a.markerOperand(cst.data(node).node),
            else => try a.markerOperand(cst.data(node).node),
        },
        .invalid => {},
        else => for (cst.children(node)) |child| try a.term(child),
    }
}

/// The operand of a marker. A marker on a node is a question for pinches
/// (rule 4), so only edges are looked into.
fn markerOperand(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    if (sort(a.cst, node) == .edges) try a.term(node);
}

/// `a/b/…`. A `*` is private to one end, so it stands at either end of a
/// one-edge chain. A kind marks where flow arrives, so it stands last, right
/// after the chain's one edge.
fn closedChain(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    const links = cst.children(node);
    const last = links.len - 1;
    var edges: usize = 0;
    for (links) |link| edges += @intFromBool(sort(cst, link) == .edges);

    if (links.len == 3 and edges == 1 and isLeaf(cst, links[0], .star) and isLeaf(cst, links[last], .star))
        return a.failTerm(.both_ends_null, node, cst.mainToken(links[last]));

    for (links, 0..) |link, i| {
        const token = cst.mainToken(link);
        if (isLeaf(cst, link, .star)) {
            if ((i != 0 and i != last) or edges > 1) try a.failTerm(.null_not_on_one_end, link, token);
        } else if (isLeaf(cst, link, .quid) or isLeaf(cst, link, .bang)) {
            if (i != last) {
                try a.failTerm(.kind_on_the_left, link, token);
            } else if (edges > 1) {
                try a.failTerm(.kind_closes_cycle, link, token);
            } else {
                try a.kindAfter(links[i - 1], link);
            }
        } else try a.term(link);
    }
}

/// What a kind node may follow: an edge being declared. A node before it is
/// a slash between nodes, for rule 3.
fn kindAfter(a: *Analyser, before: Node.Index, kind: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    const token = cst.mainToken(kind);
    switch (cst.tag(before)) {
        .leaf => {},
        .group => if (isSingleEdge(cst, before)) {
            try a.fail(.kind_after_group_of_one, token);
        } else try a.failTerm(.kind_after_group, kind, token),
        .prefix, .postfix => if (isPinchedEdge(cst, before)) {
            try a.failTerm(.kind_on_reference, kind, token);
        } else if (cst.tokenTag(cst.mainToken(before)) != .slash) {
            try a.failTerm(.kind_after_group, kind, token);
        },
        .juxtafix => if (sort(cst, before) == .edges) try a.failTerm(.kind_on_reference, kind, token),
        else => {},
    }
}

// ---------------------------------------------------------------------------
// Sorts: what a term is, read from its shape alone.

const Sort = enum { node, edges };

fn sort(cst: *const Cst, node: Node.Index) Sort {
    return switch (cst.tag(node)) {
        .leaf => switch (cst.tokenTag(cst.mainToken(node))) {
            .node_id, .zone_id, .at, .star, .quid, .bang => .node,
            else => .edges,
        },
        .juxtafix => sort(cst, cst.data(node).nodes[1]),
        .prefix, .postfix => if (isPinchedEdge(cst, node)) .node else .edges,
        .group => blk: {
            const inner = cst.children(node)[0];
            break :blk if (cst.tag(inner) == .items) .edges else sort(cst, inner);
        },
        else => .edges,
    };
}

/// `f`, or a group of one that is: `(f)` is f.
fn isSingleEdge(cst: *const Cst, node: Node.Index) bool {
    return switch (cst.tag(node)) {
        .leaf => cst.tokenTag(cst.mainToken(node)) == .edge_id,
        .group => isSingleEdge(cst, cst.children(node)[0]),
        else => false,
    };
}

/// `+f`, `f+`, `f?`, `+(f)`: a marker on a single edge, which is a reference
/// to the node at that end.
fn isPinchedEdge(cst: *const Cst, node: Node.Index) bool {
    return switch (cst.tag(node)) {
        .prefix, .postfix => cst.tokenTag(cst.mainToken(node)) != .slash and isSingleEdge(cst, cst.data(node).node),
        else => false,
    };
}

fn isLeaf(cst: *const Cst, node: Node.Index, tag: Token.Tag) bool {
    return cst.tag(node) == .leaf and cst.tokenTag(cst.mainToken(node)) == tag;
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
