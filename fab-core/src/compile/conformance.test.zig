//! The conformance corpus: the spec's examples and error rows, run through
//! the whole pipeline.
//!
//! Each case is a spec snippet, the diagnostics it reports (by code, in
//! order) and, when it matters, the IR it denotes (as `Ir.dump`). Tests are
//! named after the spec section the case comes from.
//!
//! Each case names the plan step (CLAUDE.md) that makes it pass. `done` is the
//! last step finished; cases for later steps are skipped. Finishing a step
//! bumps `done`, and its cases must then pass. Each step adds its new
//! diagnostic codes together with their rows.

const std = @import("std");
const testing = std.testing;
const Compilation = @import("Compilation.zig");
const Diagnostic = @import("Diagnostic.zig");

/// The last plan step finished.
const done = 4;

const Case = struct {
    source: [:0]const u8,
    /// The diagnostics the case reports, in order. None: the case is accepted.
    codes: []const Diagnostic.Code = &.{},
    /// The IR's dump, when the case checks the graph it denotes.
    ir: ?[]const u8 = null,
    /// The plan step that makes the case pass.
    step: u8,
};

/// Keeps the IR of a program with errors, so a rejected case can check it too.
const tolerance: Compilation.Tolerance = .{ .warnings = .warn, .ir = .keep };

fn check(case: Case) !void {
    if (case.step > done) return error.SkipZigTest;

    var c = try Compilation.init(testing.allocator, case.source, tolerance);
    defer c.deinit();

    const diags = try c.diagnostics();
    const same = diags.len == case.codes.len and for (diags, case.codes) |d, want| {
        if (!std.meta.eql(d.code, want)) break false;
    } else true;
    if (!same) {
        std.debug.print("source: {s}\nexpected:", .{case.source});
        for (case.codes) |want| std.debug.print(" {s}", .{want.name()});
        std.debug.print("\nreported:", .{});
        for (diags) |d| std.debug.print(" {s}", .{d.code.name()});
        std.debug.print("\n", .{});
        return error.TestUnexpectedResult;
    }

    if (case.ir) |want| {
        var out: std.Io.Writer.Allocating = .init(testing.allocator);
        defer out.deinit();
        try (try c.ir()).?.dump(&out.writer);
        try testing.expectEqualStrings(want, out.written());
    }
}

// ---------------------------------------------------------------------------
// Composition

test "Composition: two edges in a path" {
    try check(.{ .step = 5, .source = "G :: f g", .ir =
        \\zone G
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  node n2 canon g+
        \\  edge f n0 -> n1
        \\  edge g n1 -> n2
        \\
    });
}

test "Composition: one edge" {
    try check(.{ .step = 5, .source = "G :: f" });
}

test "Composition: a path" {
    try check(.{ .step = 5, .source = "G :: f g h" });
}

test "Composition: disjoint union" {
    try check(.{ .step = 5, .source = "G :: f, g" });
}

test "Composition: fork" {
    try check(.{ .step = 5, .source = "G :: f +(g, h)" });
}

test "Composition: join" {
    try check(.{ .step = 5, .source = "G :: (f, g)+ h" });
}

test "Composition: a declaration in braces spans lines" {
    try check(.{ .step = 5, .source =
        \\Db :: {
        \\  Document/owner/User,
        \\  Config/settings_of/User
        \\}
    });
}

// ---------------------------------------------------------------------------
// The slash: one edge, attachment

test "Slash: attached at the start" {
    try check(.{ .step = 5, .source = "G :: #A/f" });
}

test "Slash: attached at the end" {
    try check(.{ .step = 5, .source = "G :: f/#B" });
}

test "Slash: attached at both ends" {
    try check(.{ .step = 5, .source = "G :: #A/f/#B" });
}

test "Slash: starting at dom(f), ending at cod(f)" {
    try check(.{ .step = 5, .source = "G :: f, +f/g, h/f+" });
}

test "Slash: parallel to f" {
    try check(.{ .step = 5, .source = "G :: f, +f/g/f+" });
}

test "Slash: null nodes at the start and the end" {
    try check(.{ .step = 5, .source = "G :: */f, g/*" });
}

test "Slash: a node continues with a space" {
    try check(.{ .step = 5, .source = "G :: receive/#Received validate" });
}

// ---------------------------------------------------------------------------
// The slash: two or more edges, cycles

test "Cycles: two edges" {
    try check(.{ .step = 5, .source = "G :: f/g" });
}

test "Cycles: a loop" {
    try check(.{ .step = 5, .source = "G :: f/f" });
}

test "Cycles: a directed triangle" {
    try check(.{ .step = 5, .source = "G :: f/g/h" });
}

test "Cycles: through a named node" {
    try check(.{ .step = 5, .source = "G :: f/#Z/g" });
}

test "Cycles: between two named nodes" {
    try check(.{ .step = 5, .source = "G :: #A/f/#B/g" });
}

test "Cycles: the pair" {
    try check(.{ .step = 5, .source = "G :: f, g, +f/m/g+/n" });
}

test "Cycles: a path, then back" {
    try check(.{ .step = 5, .source = "G :: (f g)/h" });
}

test "Cycles: a cycle exposes its start on the left" {
    try check(.{ .step = 5, .source = "G :: h f/g" });
}

test "Cycles: a pinch gathers a cycle by its start" {
    try check(.{ .step = 5, .source = "G :: f ?(b/b, e)" });
}

test "Cycles: continuing from another node of the cycle" {
    try check(.{ .step = 5, .source = "G :: f/g, f+/h" });
}

// ---------------------------------------------------------------------------
// The slash: distribution

test "Distribution: over a group, from a node" {
    try check(.{ .step = 5, .source = "G :: #X/(g1, f, g2)" });
}

// ---------------------------------------------------------------------------
// The slash: undirected edges

test "Undirected: one edge" {
    try check(.{ .step = 5, .source = "G :: f/" });
}

test "Undirected: two edges in a path" {
    try check(.{ .step = 5, .source = "G :: f/ g/" });
}

test "Undirected: attached at one end" {
    try check(.{ .step = 5, .source = "G :: #A/f/" });
}

test "Undirected: between two named nodes" {
    try check(.{ .step = 5, .source = "G :: #A/f/#B/" });
}

test "Undirected: attached, then continued" {
    try check(.{ .step = 5, .source = "G :: #A/f/ g/" });
}

// ---------------------------------------------------------------------------
// Node kinds and pinching

test "Pinches: a parallel pair" {
    try check(.{ .step = 5, .source = "Pair :: +(f, g)+" });
}

test "Pinches: a square" {
    try check(.{ .step = 5, .source = "Sq :: +(f h, g k)+" });
}

test "Pinches: decision and merge" {
    try check(.{ .step = 5, .source = "G :: f ?(g, h)? k" });
}

test "Pinches: fork and join" {
    try check(.{ .step = 5, .source = "G :: f !(g, h)! k" });
}

test "Pinches: a bowtie" {
    try check(.{ .step = 5, .source = "G :: (a, b)+ +(c, d)" });
}

test "Pinches: one bar that joins and forks" {
    try check(.{ .step = 5, .source = "G :: (a, b)! !(c, d)" });
}

test "Where nodes meet: a fan out of a named node" {
    try check(.{ .step = 5, .source = "G :: validate/#Valid +(yes, no)" });
}

// ---------------------------------------------------------------------------
// Null nodes

test "Null nodes: a path from a start to a stop" {
    try check(.{ .step = 5, .source = "G :: */f g h/*" });
}

test "Null nodes: two starts, joined" {
    try check(.{ .step = 5, .source = "G :: (*/f, */g)+ h" });
}

test "Null nodes: two starts, two paths, one end" {
    try check(.{ .step = 5, .source = "G :: (*/f f1, */g g1)+" });
}

// ---------------------------------------------------------------------------
// Interfaces

test "Interfaces: a stopped branch is skipped when ends are counted" {
    try check(.{ .step = 5, .source = "G :: (f/*, g) h" });
}

test "Interfaces: lone nodes" {
    try check(.{ .step = 5, .source = "T :: #UUID7, #DTZ" });
}

// ---------------------------------------------------------------------------
// Syntax errors (the spec's error tables)

test "Statements: a statement spanning lines" {
    try check(.{ .step = 4, .source = "Db :: (\n  f, g\n)", .codes = &.{.{ .syntax = .statement_spans_lines }} });
}

test "Statements: a missing comma" {
    try check(.{ .step = 4, .source = "G :style := #Done :terminal f :label \"x\"", .codes = &.{.{ .syntax = .missing_comma }} });
}

test "Statements: a trailing comma in a group" {
    try check(.{ .step = 4, .source = "G :: (f, g,)", .codes = &.{.{ .syntax = .trailing_comma }} });
}

test "Statements: a trailing comma in braces" {
    try check(.{ .step = 4, .source = "G :style := { a :x, }", .codes = &.{.{ .syntax = .trailing_comma }} });
}

test "Statements: empty braces in a declaration" {
    try check(.{ .step = 4, .source = "G :: {}", .codes = &.{.{ .syntax = .empty_braces }} });
}

test "Statements: empty braces in a definition" {
    try check(.{ .step = 4, .source = "G :style := {}", .codes = &.{.{ .syntax = .empty_braces }} });
}

test "Relations: a marker touching both sides" {
    try check(.{ .step = 4, .source = "G :: f?(g, h)", .codes = &.{.{ .syntax = .marker_touches_both_sides }} });
}

test "Relations: a marker touching both sides, between groups" {
    try check(.{ .step = 4, .source = "G :: (a, b)!(c, d)", .codes = &.{.{ .syntax = .marker_touches_both_sides }} });
}

test "Relations: a tight operator touching nothing, infix" {
    try check(.{ .step = 4, .source = "G :: f / g", .codes = &.{.{ .syntax = .operator_touches_nothing }} });
}

test "Relations: a tight operator touching nothing, prefix" {
    try check(.{ .step = 4, .source = "G :: + f", .codes = &.{.{ .syntax = .operator_touches_nothing }} });
}

test "Relations: a prefix slash" {
    try check(.{ .step = 4, .source = "G :: f /g", .codes = &.{.{ .syntax = .slash_has_no_prefix_form }} });
}

test "Relations: atoms touching" {
    try check(.{ .step = 4, .source = "G :: f(g)", .codes = &.{.{ .syntax = .atoms_touch }} });
}

test "Relations: a null node touching an edge" {
    try check(.{ .step = 4, .source = "G :: *f", .codes = &.{.{ .syntax = .atoms_touch }} });
}

test "Levels: an empty level" {
    try check(.{ .step = 4, .source = "G :: f | | m", .codes = &.{.{ .syntax = .empty_level }} });
}

test "Levels: a level inside a branch" {
    try check(.{ .step = 4, .source = "G :: f (g | α)", .codes = &.{.{ .syntax = .bar_in_group }} });
}
