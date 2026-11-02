//! The conformance corpus: the spec's examples and error rows, run through
//! the whole pipeline.
//!
//! Each case is a spec snippet, the diagnostics it reports (by code, in
//! order) and, when it matters, the IR it denotes (as `Ir.dump`). Tests are
//! named after the spec section the case comes from.
//!
//! Each case names the plan step (CLAUDE.md) that makes it pass, and within
//! step 5 the analyser's rule. `done` is the last one finished; later cases
//! are skipped. Finishing a step or a rule bumps `done`, and its cases must
//! then pass. Each adds its new diagnostic codes together with their rows.
//!
//! Unsupported diagnostics are left out: the spec never mentions them
//! (statements.md §15), and a case states what the spec says.

const std = @import("std");
const testing = std.testing;
const Compilation = @import("Compilation.zig");
const Diagnostic = @import("Diagnostic.zig");

/// The last plan step, and rule of step 5, finished.
const done: Progress = .{ .step = 5, .rule = 4 };

const Progress = struct {
    step: u8,
    rule: u8 = 0,

    fn after(a: Progress, b: Progress) bool {
        return a.step > b.step or (a.step == b.step and a.rule > b.rule);
    }
};

const Case = struct {
    source: [:0]const u8,
    /// The diagnostics the case reports, in order. None: the case is accepted.
    codes: []const Diagnostic.Code = &.{},
    /// The IR's dump, when the case checks the graph it denotes.
    ir: ?[]const u8 = null,
    /// The plan step that makes the case pass.
    step: u8,
    /// Within step 5, the analyser's rule that makes the case pass.
    rule: u8 = 0,
};

/// Keeps the IR of a program with errors, so a rejected case can check it too.
const tolerance: Compilation.Tolerance = .{ .warnings = .warn, .ir = .keep };

fn check(case: Case) !void {
    if ((Progress{ .step = case.step, .rule = case.rule }).after(done)) return error.SkipZigTest;

    var c = try Compilation.init(testing.allocator, case.source, tolerance);
    defer c.deinit();

    var reported: std.ArrayList(Diagnostic) = .empty;
    defer reported.deinit(testing.allocator);
    for (try c.diagnostics()) |d| {
        if (d.severity != .unsupported) try reported.append(testing.allocator, d);
    }
    const diags = reported.items;
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
    try check(.{ .step = 5, .rule = 3, .source = "G :: f g", .ir =
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
    try check(.{ .step = 5, .rule = 3, .source = "G :: #A/f/#B", .ir =
        \\zone G
        \\  node n0 #A
        \\  node n1 #B canon f+
        \\  edge f n0 -> n1
        \\
    });
}

test "Slash: starting at dom(f), ending at cod(f)" {
    try check(.{ .step = 5, .source = "G :: f, +f/g, h/f+" });
}

test "Slash: parallel to f" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: f, +f/g/f+", .ir =
        \\zone G
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\  edge g n0 -> n1
        \\
    });
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
    try check(.{ .step = 5, .rule = 3, .source = "G :: f/g", .ir =
        \\zone G
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\  edge g n1 -> n0
        \\
    });
}

test "Cycles: a loop" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: f/f", .ir =
        \\zone G
        \\  node n0 canon +f
        \\  edge f n0 -> n0
        \\
    });
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
    try check(.{ .step = 5, .rule = 3, .source = "G :: (f g)/h", .ir =
        \\zone G
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  node n2 canon g+
        \\  edge f n0 -> n1
        \\  edge g n1 -> n2
        \\  edge h n2 -> n0
        \\
    });
}

test "Cycles: a cycle exposes its start on the left" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: h f/g", .ir =
        \\zone G
        \\  node n0 canon +h
        \\  node n1 canon h+
        \\  node n2 canon f+
        \\  edge h n0 -> n1
        \\  edge f n1 -> n2
        \\  edge g n2 -> n1
        \\
    });
}

test "Cycles: a pinch gathers a cycle by its start" {
    try check(.{ .step = 5, .source = "G :: f/? +(b/b, e)" });
}

test "Cycles: continuing from another node of the cycle" {
    try check(.{ .step = 5, .source = "G :: f/g, f+/h" });
}

// ---------------------------------------------------------------------------
// The slash: distribution

test "Distribution: over a group, from a node" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: #X/(g1, f, g2)", .ir =
        \\zone G
        \\  node n0 #X
        \\  node n1 canon g1+
        \\  node n2 canon f+
        \\  node n3 canon g2+
        \\  edge g1 n0 -> n1
        \\  edge f n0 -> n2
        \\  edge g2 n0 -> n3
        \\
    });
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
    try check(.{ .step = 5, .rule = 3, .source = "G :: #A/f/#B/", .ir =
        \\zone G
        \\  node n0 #A
        \\  node n1 #B canon f+
        \\  edge f n0 -- n1
        \\
    });
}

test "Undirected: attached, then continued" {
    try check(.{ .step = 5, .source = "G :: #A/f/ g/" });
}

// ---------------------------------------------------------------------------
// Node kinds and pinching

test "Pinches: a parallel pair" {
    try check(.{ .step = 5, .rule = 3, .source = "Pair :: +(f, g)+", .ir =
        \\zone Pair
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\  edge g n0 -> n1
        \\
    });
}

test "Pinches: a square" {
    try check(.{ .step = 5, .rule = 4, .source = "Sq :: +(f h, g k)+", .ir =
        \\zone Sq
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  node n2 canon h+
        \\  node n3 canon g+
        \\  edge f n0 -> n1
        \\  edge h n1 -> n2
        \\  edge g n0 -> n3
        \\  edge k n3 -> n2
        \\
    });
}

test "Pinches: decision and merge" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: f/? +(g, h)? k", .ir =
        \\zone G
        \\  node n0 canon +f
        \\  node n1 choice canon f+
        \\  node n2 choice canon g+
        \\  node n3 canon k+
        \\  edge f n0 -> n1
        \\  edge g n1 -> n2
        \\  edge h n1 -> n2
        \\  edge k n2 -> n3
        \\
    });
}

test "Pinches: fork and join" {
    try check(.{ .step = 5, .source = "G :: f/! +(g, h)! k" });
}

test "Pinches: a bowtie" {
    try check(.{ .step = 5, .source = "G :: (a, b)+ +(c, d)" });
}

test "Pinches: one bar that joins and forks" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: (a, b)! +(c, d)", .ir =
        \\zone G
        \\  node n0 canon +a
        \\  node n1 parallel canon a+
        \\  node n2 canon +b
        \\  node n3 canon c+
        \\  node n4 canon d+
        \\  edge a n0 -> n1
        \\  edge b n2 -> n1
        \\  edge c n1 -> n3
        \\  edge d n1 -> n4
        \\
    });
}

test "Where nodes meet: a fan out of a named node" {
    try check(.{ .step = 5, .source = "G :: validate/#Valid +(yes, no)" });
}

// ---------------------------------------------------------------------------
// Null nodes

test "Null nodes: a path from a start to a stop" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: */f g h/*", .ir =
        \\zone G
        \\  node n0 null_node
        \\  node n1 canon f+
        \\  node n2 canon g+
        \\  node n3 null_node canon h+
        \\  edge f n0 -> n1
        \\  edge g n1 -> n2
        \\  edge h n2 -> n3
        \\
    });
}

test "Null nodes: two starts, joined" {
    try check(.{ .step = 5, .source = "G :: (*/f, */g)+ h" });
}

test "Null nodes: two starts, two paths, one end" {
    try check(.{ .step = 5, .source = "G :: (*/f f1, */g g1)+" });
}

// ---------------------------------------------------------------------------
// Interfaces

test "Interfaces: a stopped branch is written apart" {
    try check(.{ .step = 5, .source = "G :: f/*, g h" });
}

test "Interfaces: a cycle's branch is gathered by a pinch" {
    try check(.{ .step = 5, .source = "G :: f/? +(b/b, e k)" });
}

test "Interfaces: lone nodes" {
    try check(.{ .step = 5, .source = "T :: #UUID7, #DTZ" });
}

// ---------------------------------------------------------------------------
// Interfaces (rule 2)

test "Relations: ends don't match, one against two" {
    try check(.{ .step = 5, .rule = 2, .source = "G :: f (g, h)", .codes = &.{.{ .analysis = .ends_dont_match }} });
}

test "Relations: ends don't match, two against one" {
    try check(.{ .step = 5, .rule = 2, .source = "G :: (f, g) h", .codes = &.{.{ .analysis = .ends_dont_match }} });
}

test "Relations: ends don't match, two against two" {
    try check(.{ .step = 5, .rule = 2, .source = "G :: (a, b) (c, d)", .codes = &.{.{ .analysis = .ends_dont_match }} });
}

test "Relations: nothing to join after a cycle" {
    try check(.{ .step = 5, .rule = 2, .source = "G :: f/g h", .codes = &.{.{ .analysis = .nothing_to_join }} });
}

test "Relations: nothing to join after a stop" {
    try check(.{ .step = 5, .rule = 2, .source = "G :: f/* g", .codes = &.{.{ .analysis = .nothing_to_join }} });
}

test "Relations: nothing to join after a group of a stop" {
    try check(.{ .step = 5, .rule = 2, .source = "G :: (f/*) g", .codes = &.{.{ .analysis = .nothing_to_join }} });
}

test "Relations: * beside a group" {
    try check(.{ .step = 5, .rule = 2, .source = "G :: */(f, g)", .codes = &.{.{ .analysis = .null_not_on_one_end }} });
}

test "Relations: a group beside *" {
    try check(.{ .step = 5, .rule = 2, .source = "G :: (f, g)/*", .codes = &.{.{ .analysis = .null_not_on_one_end }} });
}

test "Relations: * beside a pinch" {
    try check(.{ .step = 5, .rule = 2, .source = "G :: */+(f, g)", .codes = &.{.{ .analysis = .null_not_on_one_end }} });
}

test "Relations: warning, a space reaches one branch past a stop" {
    try check(.{ .step = 5, .rule = 2, .source = "G :: (f/*, g) h", .codes = &.{.{ .analysis = .space_reaches_one_branch }} });
}

test "Relations: warning, a space reaches one branch past a lone node" {
    try check(.{ .step = 5, .rule = 2, .source = "G :: (f, #A) g", .codes = &.{.{ .analysis = .space_reaches_one_branch }} });
}

test "Relations: warning, a space reaches one branch of a pinch" {
    try check(.{ .step = 5, .rule = 2, .source = "G :: +(g/*, h) k", .codes = &.{.{ .analysis = .space_reaches_one_branch }} });
}

// ---------------------------------------------------------------------------
// Slash chains (rule 3)

test "Relations: a slash between two groups" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: (f, g)/(h, k)", .codes = &.{.{ .analysis = .slash_between_groups }} });
}

test "Relations: nothing to join at a slash, after a stop" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: (f/*)/g", .codes = &.{.{ .analysis = .nothing_to_join }} });
}

test "Relations: nothing to join at a slash, after a cycle" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: (f/g)/h", .codes = &.{.{ .analysis = .nothing_to_join }} });
}

test "Undirected: a trailing / on a cycle" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: f/g/", .codes = &.{.{ .analysis = .undirected_not_one_edge }} });
}

test "Undirected: a trailing / on a group" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: (f, g)/", .codes = &.{.{ .analysis = .undirected_not_one_edge }} });
}

test "Undirected: a trailing / on a path" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: (f g)/", .codes = &.{.{ .analysis = .undirected_not_one_edge }} });
}

test "Relations: / between nodes, with a trailing /" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: #A/#B/", .codes = &.{.{ .analysis = .slash_between_nodes }} });
}

test "Relations: an edge declared twice" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: f g f", .codes = &.{.{ .analysis = .edge_declared_twice }} });
}

test "Relations: a self-reference outside f/f" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: (f g)/f", .codes = &.{.{ .analysis = .self_reference_outside_loop }} });
}

test "Relations: a redundant self-attachment" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: f/+f", .codes = &.{.{ .analysis = .redundant_self_attachment }} });
}

test "Relations: a vacuous self-attachment" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: f/f+", .codes = &.{.{ .analysis = .vacuous_self_attachment }} });
}

test "Relations: a cycle that does not close, between named nodes" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: #A/f/#B/g/#C", .codes = &.{.{ .analysis = .cycle_does_not_close }} });
}

test "Relations: a cycle that does not close, the old pair form" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: f, g, +f/m/n/g+", .codes = &.{.{ .analysis = .cycle_does_not_close }} });
}

test "Relations: a reference not declared" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: +k/g", .codes = &.{.{ .analysis = .reference_not_declared }} });
}

test "Relations: a forward reference" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: +f/g f", .codes = &.{.{ .analysis = .forward_reference }} });
}

test "Cycles: a cycle that ends on its start" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: #A/f/#B/g/#A" });
}

// ---------------------------------------------------------------------------
// Pinches (rule 4)

test "Relations: a pinch of declared edges" {
    try check(.{ .step = 5, .rule = 4, .source = "G :: f g, h k, +(f, h)", .codes = &.{ .{ .analysis = .pinch_of_declared_edges }, .{ .analysis = .pinch_of_declared_edges } } });
}

test "Relations: a single edge pinched on both sides" {
    try check(.{ .step = 5, .rule = 4, .source = "G :: f, +f+", .codes = &.{.{ .analysis = .single_edge_pinched_twice }} });
}

test "Relations: a single edge in a group, pinched on both sides" {
    try check(.{ .step = 5, .rule = 4, .source = "G :: f, +(f)+", .codes = &.{.{ .analysis = .single_edge_pinched_twice }} });
}

test "Relations: a pinch of a named node" {
    try check(.{ .step = 5, .rule = 4, .source = "G :: +#A", .codes = &.{.{ .analysis = .pinch_of_a_node }} });
}

test "Relations: a kind on a named node" {
    try check(.{ .step = 5, .rule = 4, .source = "G :: #A?", .codes = &.{.{ .analysis = .pinch_of_a_node }} });
}

test "Relations: a pinch of the diagram's own node" {
    try check(.{ .step = 5, .rule = 4, .source = "G :: (@)+", .codes = &.{.{ .analysis = .pinch_of_a_node }} });
}

test "Relations: a pinch of nothing" {
    try check(.{ .step = 5, .rule = 4, .source = "G :: (f/*, g/*)+", .codes = &.{.{ .analysis = .pinch_of_nothing }} });
}

test "Relations: warning, a pinch of one end beside a lone node" {
    try check(.{ .step = 5, .rule = 4, .source = "G :: +(f, #A)", .codes = &.{.{ .analysis = .pinch_of_one_end }} });
}

test "Relations: warning, a pinch of one end beside a cycle" {
    try check(.{ .step = 5, .rule = 4, .source = "G :: (a, b/b)! k", .codes = &.{.{ .analysis = .pinch_of_one_end }} });
}

// ---------------------------------------------------------------------------
// Statements (rule 0)

test "Statements: a bare term in a definition" {
    try check(.{ .step = 5, .source = "G :style := yes, paid :label \"yes\"", .codes = &.{.{ .analysis = .bare_term_in_definition }} });
}

test "Statements: an entry in a declaration" {
    try check(.{ .step = 5, .source = "G :: f (g :label \"x\")", .codes = &.{.{ .analysis = .entry_in_declaration }} });
}

test "Statements: an equation in a declaration" {
    try check(.{ .step = 5, .source = "G :: f == g", .codes = &.{.{ .analysis = .entry_in_declaration }} });
}

test "Statements: a class in a declaration" {
    try check(.{ .step = 5, .source = "G :: &node f", .codes = &.{.{ .analysis = .class_in_declaration }} });
}

test "Statements: levels in a definition" {
    try check(.{ .step = 5, .source = ":x := a | b", .codes = &.{.{ .analysis = .levels_in_definition }} });
}

test "Statements: a value as a declaration's head" {
    try check(.{ .step = 5, .source = "[red] :: f", .codes = &.{.{ .analysis = .bad_declaration_head }} });
}

test "Statements: an entry as a declaration's head" {
    try check(.{ .step = 5, .source = "G :style :: f", .codes = &.{.{ .analysis = .bad_declaration_head }} });
}

test "Statements: a node declared, reserved" {
    try check(.{ .step = 5, .source = "#User :: @/(id, name)", .codes = &.{.{ .analysis = .reserved_node_or_edge_declaration }} });
}

test "Statements: an edge declared, reserved" {
    try check(.{ .step = 5, .source = "review :: a b", .codes = &.{.{ .analysis = .reserved_node_or_edge_declaration }} });
}

test "Statements: a chain as a definition's head" {
    try check(.{ .step = 5, .source = "f g := [red]", .codes = &.{.{ .analysis = .bad_definition_head }} });
}

test "Statements: a diagram as a definition's head" {
    try check(.{ .step = 5, .source = "G := [red]", .codes = &.{.{ .analysis = .bad_definition_head }} });
}

test "Statements: warning, a chain broken across lines" {
    try check(.{ .step = 5, .source = "G :: {\n  f g\n  h k\n}", .codes = &.{.{ .analysis = .chain_broken_across_lines }} });
}

test "Statements: a chain across lines in a group" {
    try check(.{ .step = 5, .source = "G :: {\n  (f g\n  h k)\n}" });
}

test "Statements: the three forms of definition" {
    try check(.{ .step = 5, .source =
        \\[red] := [#ff0000]
        \\:terminal := { :shape [circle] :fill [red] }
        \\G :: f
        \\&node :shape := [circle]
        \\G :style := { f :label "x", +f { :label $P$ } }
        \\G.f :arrow := [epi]
    });
}

test "Relations: a diagram declared twice" {
    try check(.{ .step = 5, .source = "G :: f\nG :: g", .codes = &.{.{ .analysis = .zone_declared_twice }} });
}

test "Definitions and values: a value in a declaration" {
    try check(.{ .step = 5, .source = "G :: +(g1, [f], g2)", .codes = &.{.{ .analysis = .value_in_declaration }} });
}

test "Proofs: different operators without a group" {
    try check(.{ .step = 5, .source = "G :prove := f == g ~= h", .codes = &.{.{ .analysis = .mixed_operators }} });
}

test "Proofs: different operators, grouped" {
    try check(.{ .step = 5, .source = "G :prove := (f == g) ~= h, f == g == h" });
}

// ---------------------------------------------------------------------------
// Sorts (rule 1)

test "Relations: / between two named nodes" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: #A/#B", .codes = &.{.{ .analysis = .slash_between_nodes }} });
}

test "Relations: / between two references" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: f, g, +g/+f", .codes = &.{.{ .analysis = .slash_between_nodes }} });
}

test "Relations: / between a node and a kind" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: #A/?", .codes = &.{.{ .analysis = .slash_between_nodes }} });
}

test "Relations: / between nodes inside a chain" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: f/#A/#B/g", .codes = &.{.{ .analysis = .slash_between_nodes }} });
}

test "Relations: a node beside a space" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: #A f", .codes = &.{.{ .analysis = .node_beside_space }} });
}

test "Relations: a null node beside a space" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: * f", .codes = &.{.{ .analysis = .node_beside_space }} });
}

test "Relations: own node beside a space" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: @ (f)", .codes = &.{.{ .analysis = .node_beside_space }} });
}

test "Relations: a diagram beside a space" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: f User", .codes = &.{.{ .analysis = .node_beside_space }} });
}

test "Relations: a kind beside a space" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: ? f", .codes = &.{.{ .analysis = .node_beside_space }} });
}

test "Relations: a pinched edge beside a space, before a group" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: f? (g, h)", .codes = &.{.{ .analysis = .pinched_edge_beside_space }} });
}

test "Relations: a pinched edge beside a space, after an edge" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: f, k +f", .codes = &.{.{ .analysis = .pinched_edge_beside_space }} });
}

test "Relations: a pinched edge beside a space, before an edge" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: f, f+ g", .codes = &.{.{ .analysis = .pinched_edge_beside_space }} });
}

test "Relations: both ends null" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: */f/*", .codes = &.{.{ .analysis = .both_ends_null }} });
}

test "Relations: a lone null node" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: *", .codes = &.{.{ .analysis = .null_not_on_one_end }} });
}

test "Relations: a null node between edges" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: f/*/g", .codes = &.{.{ .analysis = .null_not_on_one_end }} });
}

test "Relations: a null node in a cycle" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: */f/g", .codes = &.{.{ .analysis = .null_not_on_one_end }} });
}

test "Relations: a kind pinching on the left" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: ?(g, h)", .codes = &.{.{ .analysis = .kind_on_the_left }} });
}

test "Relations: a kind before an edge" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: !f", .codes = &.{.{ .analysis = .kind_on_the_left }} });
}

test "Relations: a kind node before an edge" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: ?/f", .codes = &.{.{ .analysis = .kind_on_the_left }} });
}

test "Relations: a kind node between edges" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: f/?/g", .codes = &.{.{ .analysis = .kind_on_the_left }} });
}

test "Relations: a kind closing a cycle" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: f/g/?", .codes = &.{.{ .analysis = .kind_closes_cycle }} });
}

test "Relations: a lone kind" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: ?", .codes = &.{.{ .analysis = .lone_kind }} });
}

test "Relations: a lone kind in a group" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: (!)", .codes = &.{.{ .analysis = .lone_kind }} });
}

test "Relations: a kind on a reference" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: f, f?", .codes = &.{.{ .analysis = .kind_on_reference }} });
}

test "Relations: a kind on another diagram's edge" {
    try check(.{ .step = 5, .rule = 1, .source = "A :: f\nG :: A.f/?", .codes = &.{.{ .analysis = .kind_on_reference }} });
}

test "Relations: a kind after a group" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: (a, b)/?", .codes = &.{.{ .analysis = .kind_after_group }} });
}

test "Relations: warning, a kind after a group of one" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: (f)/?", .codes = &.{.{ .analysis = .kind_after_group_of_one }} });
}

test "Pinches: a decision with its branches written apart" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: f/?, f+/a, f+/b" });
}

test "Pinches: kinds after edges between nodes" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: #A/f/?, */s/! +(a, b)" });
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
    try check(.{ .step = 4, .source = "G :: f+(g, h)", .codes = &.{.{ .syntax = .marker_touches_both_sides }} });
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

// ---------------------------------------------------------------------------
// Examples (examples/*.fab, and the spec's Examples section)

test "Examples: the simplest program" {
    try check(.{ .step = 5, .source =
        \\G :: f
    });
}

test "Examples: mathematical diagrams" {
    try check(.{ .step = 5, .source =
        \\Sq   :: +(f h, g k)+              // a square: f;h and g;k from A to D
        \\Tri  :: +(f g, h)+                // a triangle: f;g and h from A to C
        \\Iso  :: f/g                       // f : A → B, g : B → A
        \\Endo :: f/f                       // f : A → A
        \\Und  :: f/                        // f connects A and B, in no direction
        \\Cyc  :: f/g/h                     // a directed triangle: f, g, then h back to A
        \\Pair :: +(f, g)+                  // a parallel pair f, g : A ⇉ B
        \\Nat  :: +(f, g)+ | f/α/g          // a natural transformation α : f ⇒ g
        \\Eq   :: +(f, g)+ | f/α/g/β        // α : f ⇒ g and β : g ⇒ f
        \\Pr   :: #X/(g1, f, g2), f+/(p1/g1+, p2/g2+)   // the universal property of a product
    });
}

test "Examples: flows" {
    try check(.{ .step = 5, .source =
        \\If    :: f/? +(fg g, fh h)? k            // decision, two branches, merge
        \\While :: f/? +(b/b, e k)                 // body b loops on the test; e exits to k
        \\Exit  :: f/? +(fg g/*, fh h k)           // g's branch stops; only h continues to k
        \\Loop  :: f/? +(fg g, fh h k/+f)          // k : cod(h) → dom(f), back before the test
        \\Par   :: */s/! +(a, b)! t/*              // start, fork, two parallel branches, join, stop
    });
}

test "Examples: a flowchart: order fulfilment" {
    try check(.{ .step = 5, .source =
        \\Order :: {
        \\  */receive/#Received validate/? +(
        \\      yes/#Accepted fork/! +(
        \\          charge/? +(paid, declined/#Waiting/retry)
        \\        , reserve/? +(reserved, short/#Backorder/restock)
        \\      )! ready/#Ready ship/#Shipped close/*
        \\    , no/#Rejected notify/*
        \\  )
        \\}
        \\
        \\Order :style := {
        \\  #Received  :label "Order received",
        \\  validate+  :label "Valid?",
        \\  charge+    :label "Payment accepted?",
        \\  #Waiting   :label "Wait 10 min",
        \\  reserve+   :label "In stock?",
        \\  #Shipped   :label "Shipped",
        \\  #Rejected  :label "Rejected",
        \\  (yes, paid, reserved)  :label "yes",
        \\  (no, declined, short)  :label "no",
        \\  (retry, restock)       :arrow [/dashed/>]  :bend [inner]
        \\}
    });
}

test "Examples: a database schema: documents and comments" {
    try check(.{ .step = 5, .source =
        \\T :: #UUID7, #DTZ, #String, #Text, #JSONB, #Bool
        \\
        \\User         :: @/(id/T.#UUID7, email/T.#String, nick/T.#String, name/T.#String, created_at/T.#DTZ)
        \\Organization :: @/(id/T.#UUID7, name/T.#String)
        \\Membership   :: @/(id/T.#UUID7, admin/T.#Bool)
        \\Project      :: @/(id/T.#UUID7, name/T.#String)
        \\Document     :: @/(id/T.#UUID7, title/T.#String, body/T.#JSONB)
        \\Comment      :: @/(id/T.#UUID7, text/T.#Text)
        \\Tag          :: @/(id/T.#UUID7, label/T.#String)
        \\Tagging      :: @/(id/T.#UUID7)
        \\
        \\Db :: {
        \\  Membership/(user/User, org/Organization),
        \\  Project/owner/Organization,
        \\  Document/(project/Project, author/User),
        \\  Comment/(document/Document, writer/User, parent/Comment),
        \\  Tagging/(doc/Document, tag/Tag)
        \\}
        \\
        \\Db :kind := [schema]
        \\
        \\Db :prove := {
        \\  &node.id :pk,
        \\  &edge :card [0..*/1],
        \\
        \\  User.(email, nick)! :uk,
        \\  Tag.label :uk,
        \\  (user, org)! :uk,
        \\  (doc, tag)! :uk,
        \\
        \\  parent :nullable :card [0..*/0..1],
        \\  parent document == document         // a reply is on the same document as its parent
        \\}
        \\
        \\Db :style := writer :label "author_id"
        \\User :style := :label "users"  :fill [muted]
    });
}

test "Examples: a git history: commits as arrows" {
    try check(.{
        .step = 5,
        .source =
        \\Repo :: {
        \\  */init readme/#Fork +(fix/#Main, login session/#Feature),
        \\  (#Main/merge, #Feature/merge')/#Merged bump/#V1 +(hotfix/#Head, spike/#Spike)
        \\}
        \\
        \\:ref := :shape [round]  :fill [muted]
        \\
        \\Repo :style := {
        \\  &node :shape [point],
        \\  #Head    :ref  :label "main",
        \\  #Feature :ref  :label "feature/auth",
        \\  #V1      :ref  :label "v1.0",
        \\  #Spike   :ref  :label "spike/cache",
        \\  init    :label "a1f3 init",
        \\  readme  :label "b27c add readme",
        \\  fix     :label "c90e fix typo",
        \\  login   :label "d4a1 login form",
        \\  session :label "e5b2 sessions",
        \\  merge   :label "f6c3 merge feature/auth",
        \\  merge'  :arrow [/dashed/>],
        \\  bump    :label "0a7d bump to 1.0",
        \\  hotfix  :label "1b8e hotfix",
        \\  spike   :label "2c9f try cache"
        \\}
        \\
        \\Repo :prove := {
        \\  fix merge == login session merge',   // both paths from the fork reach the same state
        \\  #Merged :pushout                      // the merge is clean: the least common state
        \\}
        ,
    });
}
