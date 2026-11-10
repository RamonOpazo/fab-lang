//! The conformance corpus: the spec's examples and error rows, run through
//! the whole pipeline.
//!
//! Each case is a spec snippet, the diagnostics it reports (by code, in
//! order) and, when it matters, the IR it denotes (as `Ir.dump`) and the
//! style it resolves to (as `Sheet.dump`: what the author asked for). Tests
//! are named after the spec section the case comes from.
//!
//! Each case names the plan step (CLAUDE.md) that makes it pass, and within
//! a step its part: the analyser's rule in step 5, the increment in steps 7
//! and 8 (1 for 7a or 8a, 2 for 7b or 8b, and so on), and in step 9 its
//! letter and sub-increment (10 for 9a, 20 for 9b0, 22 for 9b2, 30 for 9c, 52 for 9e2). `done` is the last one finished; later cases
//! are skipped. Finishing a step or a rule bumps `done`, and its cases must
//! then pass. Each adds its new diagnostic codes together with their rows.
//!
//! Unsupported diagnostics are left out: the spec never mentions them
//! (statements.md §15), and a case states what the spec says.

const std = @import("std");
const testing = std.testing;
const Compilation = @import("Compilation.zig");
const Diagnostic = @import("Diagnostic.zig");

/// The last plan step, and its rule or increment, finished.
const done: Progress = .{ .step = 9, .rule = 52 };

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
    /// The Sheet's dump, when the case checks the style it resolves to.
    sheet: ?[]const u8 = null,
    /// The plan step that makes the case pass.
    step: u8,
    /// Within the step, the part that makes the case pass: step 5's rule, or
    /// the increment of steps 7 and 8.
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
    if (case.sheet) |want| {
        var out: std.Io.Writer.Allocating = .init(testing.allocator);
        defer out.deinit();
        try (try c.sheet()).?.dump(&out.writer, .{});
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
        \\User :: */id
        \\Document :: */id
        \\Config :: */id
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
    try check(.{ .step = 5, .rule = 7, .source = "G :: #A/f/#B", .ir =
        \\zone G
        \\  node n0 #A
        \\  node n1 #B
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
    try check(.{ .step = 5, .rule = 7, .source = "G :: receive/#Received validate", .ir =
        \\zone G
        \\  node n0 canon +receive
        \\  node n1 #Received
        \\  node n2 canon validate+
        \\  edge receive n0 -> n1
        \\  edge validate n1 -> n2
        \\
    });
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
    try check(.{ .step = 5, .rule = 7, .source = "G :: #A/f/#B/", .ir =
        \\zone G
        \\  node n0 #A
        \\  node n1 #B
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
    try check(.{ .step = 5, .rule = 7, .source = "G :: validate/#Valid +(yes, no)", .ir =
        \\zone G
        \\  node n0 canon +validate
        \\  node n1 #Valid
        \\  node n2 canon yes+
        \\  node n3 canon no+
        \\  edge validate n0 -> n1
        \\  edge yes n1 -> n2
        \\  edge no n1 -> n3
        \\
    });
}

// ---------------------------------------------------------------------------
// Null nodes

test "Null nodes: a path from a start to a stop" {
    try check(.{ .step = 5, .rule = 7, .source = "G :: */f g h/*", .ir =
        \\zone G
        \\  node n0 null_node canon +f
        \\  node n1 canon f+
        \\  node n2 canon g+
        \\  node n3 null_node canon h+
        \\  edge f n0 -> n1
        \\  edge g n1 -> n2
        \\  edge h n2 -> n3
        \\
    });
}

test "Null nodes: a start is named through its edge" {
    try check(.{ .step = 5, .rule = 7, .source = "G :: */f", .ir =
        \\zone G
        \\  node n0 null_node canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
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

test "Relations: * beside a group (statements.md §23.3)" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: */(f, g)", .ir =
        \\zone G
        \\  node n0 null_node canon +f
        \\  node n1 canon f+
        \\  node n2 canon g+
        \\  edge f n0 -> n1
        \\  edge g n0 -> n2
        \\
    });
    try check(.{ .step = 5, .rule = 2, .source = "G :: */(f, g h, k/*)" });
}

test "Relations: a group beside * (statements.md §23.3)" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: (f, g)/*", .ir =
        \\zone G
        \\  node n0 canon +f
        \\  node n1 null_node canon f+
        \\  node n2 canon +g
        \\  edge f n0 -> n1
        \\  edge g n2 -> n1
        \\
    });
    try check(.{ .step = 5, .rule = 2, .source = "G :: f/? +(yes, no)/*" });
}

test "Relations: * beside a pinch" {
    try check(.{ .step = 5, .rule = 2, .source = "G :: */+(f, g)", .codes = &.{.{ .analysis = .slash_between_nodes }} });
}

test "Relations: * beside a group exposing nothing" {
    try check(.{ .step = 5, .rule = 2, .source = "G :: */(*/f)", .codes = &.{.{ .analysis = .nothing_to_join }} });
}

test "Relations: nothing to join before a start of a group" {
    try check(.{ .step = 5, .rule = 2, .source = "G :: h */(f, g)", .codes = &.{.{ .analysis = .nothing_to_join }} });
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

test "Relations: nothing to join at a slash, a node before a start (statements.md §23.4)" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: #X/(*/f g)", .codes = &.{.{ .analysis = .nothing_to_join }} });
    try check(.{ .step = 5, .rule = 3, .source = "G :: g/(f/*)/#X", .codes = &.{.{ .analysis = .nothing_to_join }} });
}

test "Undirected: a cycle" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: f/g/", .ir =
        \\zone G
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -- n1
        \\  edge g n1 -- n0
        \\
    });
    try check(.{ .step = 5, .rule = 3, .source = "G :: #A/f/#B/g/", .ir =
        \\zone G
        \\  node n0 #A
        \\  node n1 #B
        \\  edge f n0 -- n1
        \\  edge g n1 -- n0
        \\
    });
}

test "Undirected: a mixed cycle names its nodes" {
    try check(.{ .step = 5, .rule = 3, .source = "G :: #A/f/#B/, #B/g/#A", .ir =
        \\zone G
        \\  node n0 #A
        \\  node n1 #B
        \\  edge f n0 -- n1
        \\  edge g n1 -> n0
        \\
    });
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

test "Relations: a pinch of a diagram" {
    try check(.{ .step = 5, .rule = 4, .source = "A :: f\nG :: (A)+", .codes = &.{.{ .analysis = .pinch_of_a_node }} });
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
// Where nodes meet (rule 5)

test "Relations: kinds disagree in a pinch" {
    try check(.{ .step = 5, .rule = 5, .source = "G :: (a/?, b/!)+", .codes = &.{.{ .analysis = .kinds_disagree }} });
}

test "Relations: a named node is not a decision" {
    try check(.{ .step = 5, .rule = 5, .source = "G :: validate/? #Valid/yes", .codes = &.{.{ .analysis = .kinds_disagree }} });
}

test "Relations: two names for one node" {
    try check(.{ .step = 5, .rule = 5, .source = "G :: a/#A #B/b", .codes = &.{.{ .analysis = .two_names_for_one_node }} });
}

test "Relations: a reference to a null node" {
    try check(.{ .step = 5, .rule = 5, .source = "G :: k f/*, j/f+", .codes = &.{.{ .analysis = .reference_to_null_node }} });
}

test "Where nodes meet: the same kind agrees" {
    try check(.{ .step = 5, .rule = 5, .source = "G :: (a/?, b/?)+" });
}

// ---------------------------------------------------------------------------
// Other diagrams (rule 6)

test "Diagrams and names: a cross reference shares A's node" {
    try check(.{ .step = 5, .rule = 6, .source = "A :: f g\nB :: h/A.+f", .ir =
        \\zone A
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  node n2 canon g+
        \\  edge f n0 -> n1
        \\  edge g n1 -> n2
        \\zone B
        \\  node n3 canon +h
        \\  edge h n3 -> n0
        \\
    });
}

test "Diagrams as nodes: attached on either side" {
    try check(.{ .step = 5, .rule = 6, .source = "A :: f\nB :: h/A, A/k" });
}

test "Diagrams and names: a diagram not declared" {
    try check(.{ .step = 5, .rule = 6, .source = "B :: h/A.+f", .codes = &.{.{ .analysis = .diagram_not_declared }} });
}

test "Diagrams and names: a diagram declared later" {
    try check(.{ .step = 5, .rule = 6, .source = "B :: h/A.+f\nA :: f", .codes = &.{.{ .analysis = .diagram_not_declared }} });
}

test "Diagrams as nodes: a diagram's own name" {
    try check(.{ .step = 5, .rule = 6, .source = "G :: G/f", .codes = &.{.{ .analysis = .diagram_not_declared }} });
}

test "Named nodes: an undeclared name in another diagram" {
    try check(.{ .step = 5, .rule = 6, .source = "T :: #UUID7\nU :: */id/T.#UUDI7", .codes = &.{.{ .analysis = .undeclared_name_in_diagram }} });
}

test "Diagrams and names: an undeclared edge in another diagram" {
    try check(.{ .step = 5, .rule = 6, .source = "A :: g\nB :: h/A.+f", .codes = &.{.{ .analysis = .undeclared_name_in_diagram }} });
}

test "Diagrams as nodes: the diagram itself, a node of the one naming it (statements.md §23.2)" {
    try check(.{ .step = 5, .rule = 6, .source = "T :: #UUID7\nUser :: */id/T.#UUID7\nDb :: T/owns/User", .ir =
        \\zone T in Db
        \\  node n0 #UUID7
        \\zone User in Db
        \\  node n1 null_node canon +id
        \\  edge id n1 -> n0
        \\zone Db
        \\  member T
        \\  member User
        \\  node n2 diagram T
        \\  node n3 diagram User
        \\  edge owns n2 -> n3
        \\
    });
}

test "Diagrams as nodes: alone, and repeated, one node (statements.md §23.2)" {
    try check(.{ .step = 5, .rule = 6, .source = "A :: f\nB :: A, A/g", .ir =
        \\zone A in B
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\zone B
        \\  member A
        \\  node n2 diagram A
        \\  node n3 canon g+
        \\  edge g n2 -> n3
        \\
    });
}

test "Diagrams as nodes: a reference to a part holds nothing (statements.md §23.2)" {
    try check(.{ .step = 5, .rule = 6, .source = "A :: f\nB :: A.f+/g", .ir =
        \\zone A
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\zone B
        \\  node n2 canon g+
        \\  edge g n1 -> n2
        \\
    });
}

test "Diagrams as nodes: held by several, nested under the first; nested in turn" {
    try check(.{ .step = 5, .rule = 6, .source = "A :: f\nB :: A\nC :: A, B", .ir =
        \\zone A in B
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\zone B in C
        \\  member A
        \\  node n2 diagram A
        \\zone C
        \\  member A
        \\  member B
        \\  node n3 diagram A
        \\  node n4 diagram B
        \\
    });
}

test "Diagrams as nodes: two diagrams meeting" {
    try check(.{ .step = 5, .rule = 5, .source = "A :: f\nB :: g\nC :: h/A B/k", .codes = &.{.{ .analysis = .two_names_for_one_node }} });
}

test "Lexical: @ is free for later (statements.md §23.1)" {
    try check(.{ .step = 4, .source = "G :: @/f", .codes = &.{.{ .syntax = .invalid_token }} });
}

test "Diagrams and names: a reference to another diagram's null node" {
    try check(.{ .step = 5, .rule = 6, .source = "A :: f/*\nB :: h/A.f+", .codes = &.{.{ .analysis = .reference_to_null_node }} });
}

test "Diagrams and names: another diagram's edge in relations" {
    try check(.{ .step = 5, .rule = 6, .source = "A :: f\nB :: A.f g", .codes = &.{.{ .analysis = .cross_reference_not_a_node }} });
}

test "Diagrams and names: a group of another diagram's edges" {
    try check(.{ .step = 5, .rule = 6, .source = "A :: f\nG :: A.(f, g)", .codes = &.{.{ .analysis = .cross_reference_not_a_node }} });
}

// ---------------------------------------------------------------------------
// Statements (rule 0)

test "Statements: a bare term in a record" {
    try check(.{ .step = 5, .source = "G :: yes, paid\nG :style { yes, paid :label \"yes\" }", .codes = &.{.{ .analysis = .bare_term_in_record }} });
    // A token is named: `[ink] [#fff]` is two terms side by side.
    try check(.{ .step = 9, .rule = 10, .source = ":Style [x] := { [ink] [#fff] }", .codes = &.{.{ .analysis = .bare_term_in_record }} });
}

test "Statements: an entry in a declaration" {
    try check(.{ .step = 5, .source = "G :: f (g :label \"x\")", .codes = &.{.{ .analysis = .entry_in_zone_declaration }} });
}

test "Statements: an equation in a declaration" {
    try check(.{ .step = 5, .source = "G :: f == g", .codes = &.{.{ .analysis = .entry_in_zone_declaration }} });
}

test "Statements: a class in a declaration" {
    try check(.{ .step = 5, .source = "G :: &node f", .codes = &.{.{ .analysis = .class_in_zone_declaration }} });
}

test "Statements: levels in a naming" {
    try check(.{ .step = 5, .source = ":x := a | b", .codes = &.{.{ .analysis = .levels_in_naming }} });
}

test "Statements: a value as a declaration's head" {
    try check(.{ .step = 5, .source = "[red] :: f", .codes = &.{.{ .analysis = .bad_declaration_head }} });
}

test "Statements: an entry as a declaration's head" {
    try check(.{ .step = 5, .source = "G :style :: f", .codes = &.{.{ .analysis = .bad_declaration_head }} });
}

test "Statements: a node declared, reserved" {
    try check(.{ .step = 5, .source = "#User :: */(id, name)", .codes = &.{.{ .analysis = .reserved_node_or_edge_declaration }} });
}

test "Statements: an edge declared, reserved" {
    try check(.{ .step = 5, .source = "review :: a b", .codes = &.{.{ .analysis = .reserved_node_or_edge_declaration }} });
}

test "Statements: a chain as a naming's head" {
    try check(.{ .step = 5, .source = "f g := [red]", .codes = &.{.{ .analysis = .bad_naming_head }} });
}

test "Statements: a diagram as a naming's head" {
    try check(.{ .step = 5, .source = "G := [red]", .codes = &.{.{ .analysis = .bad_naming_head }} });
}

test "Statements: a bad head's body is not checked, but its brackets are" {
    try check(.{ .step = 8, .rule = 3, .source = ":Label.(:Color) := :Text", .codes = &.{.{ .analysis = .bad_naming_head }} });
    try check(.{ .step = 8, .rule = 3, .source = "f g := { h k, :x }", .codes = &.{.{ .analysis = .bad_naming_head }} });
    try check(.{ .step = 8, .rule = 3, .source = "G := [1.]", .codes = &.{
        .{ .analysis = .bad_naming_head }, .{ .analysis = .malformed_number },
    } });
}

test "Statements: warning, a chain broken across lines" {
    try check(.{ .step = 5, .source = "G :: {\n  f g\n  h k\n}", .codes = &.{.{ .analysis = .chain_broken_across_lines }} });
}

test "Statements: a chain across lines in a group" {
    try check(.{ .step = 5, .source = "G :: {\n  (f g\n  h k)\n}" });
}

test "Statements: the three forms" {
    try check(.{ .step = 9, .rule = 10, .source =
        \\[brand] := [#ff0000]
        \\:terminal := { :shape [circle], :fill [brand] }
        \\G :: f
        \\G :style { :caption "x", &node :shape [circle], f :label "x", +f { :label $P$ } }
        \\G.f :arrow [epi]
        \\G { :style { f :hide } }
    });
}

test "Statements: a description written with :=" {
    try check(.{ .step = 9, .rule = 10, .source = "G :: f\nG :style := { f :label \"x\" }", .codes = &.{.{ .analysis = .description_with_operator }} });
    try check(.{ .step = 9, .rule = 10, .source = "G :: f\nG.f :arrow := [epi]", .codes = &.{.{ .analysis = .description_with_operator }} });
    // Its body is still checked, as a description's.
    try check(.{ .step = 9, .rule = 10, .source = "G :: f\nG :style := { f, f :label \"x\" }", .codes = &.{
        .{ .analysis = .description_with_operator }, .{ .analysis = .bare_term_in_record },
    } });
}

test "Statements: a description with no context" {
    try check(.{ .step = 9, .rule = 10, .source = ":fill [red]", .codes = &.{.{ .analysis = .context_missing }} });
    try check(.{ .step = 9, .rule = 10, .source = "{ :fill [red] }", .codes = &.{.{ .syntax = .expected_token }} });
}

test "Statements: a declaration in a record" {
    try check(.{ .step = 9, .rule = 10, .source = ":Style [x] := { [ink] :: :Color }", .codes = &.{.{ .analysis = .declaration_in_record }} });
    try check(.{ .step = 9, .rule = 10, .source = "G :: f\nG :style { f :: g }", .codes = &.{.{ .analysis = .declaration_in_record }} });
}

test "Statements: warning, owner described after a part" {
    try check(.{ .step = 9, .rule = 10, .source = "G :: f\nG :style { &node :fill [red], :caption \"x\" }", .codes = &.{.{ .analysis = .owner_after_part }} });
    // Tokens are no parts: they name, and describe nothing.
    try check(.{ .step = 9, .rule = 10, .source = ":Style [x] := { [ink] := [#fff], :fill [red] }" });
}

test "Statements: a table's key, and a proposition as a value" {
    try check(.{ .step = 9, .rule = 10, .source = "G :: f g, h\nG :prove { :axiom.[a] (f g == h), :lemma (#M :pushout), :axiom (f g == h ~= h) }", .codes = &.{.{ .analysis = .mixed_operators }} });
}

test "Relations: a diagram declared twice" {
    try check(.{ .step = 5, .source = "G :: f\nG :: g", .codes = &.{.{ .analysis = .zone_declared_twice }} });
}

test "Definitions and values: attributes side by side" {
    try check(.{ .step = 4, .source = "G :: f\nG :style { f :label \"x\" :bend [inner] }", .codes = &.{.{ .syntax = .attributes_side_by_side }} });
}

test "Definitions and values: a value in a declaration" {
    try check(.{ .step = 5, .source = "G :: +(g1, [f], g2)", .codes = &.{.{ .analysis = .value_in_zone_declaration }} });
}

test "Definitions and values: a type in a diagram's declaration" {
    try check(.{ .step = 8, .rule = 1, .source = "G :: f :Color", .codes = &.{.{ .analysis = .type_in_zone_declaration }} });
    try check(.{ .step = 8, .rule = 1, .source = "G :: +(g1, :Shape, g2)", .codes = &.{.{ .analysis = .type_in_zone_declaration }} });
}

test "Definitions and values: types, labels and signatures are accepted" {
    try check(.{ .step = 8, .rule = 1, .source = ":Mood :: [calm], [busy]" });
    try check(.{ .step = 8, .rule = 1, .source = ":Mood :: {\n  [calm],\n  [busy]\n}" });
    try check(.{ .step = 8, .rule = 1, .source = "(&node, &zone) :glow :: :Color" });
    try check(.{ .step = 9, .rule = 20, .source = "&zone :backdrops :: [:Style]" });
    try check(.{ .step = 9, .rule = 20, .source = ":Width :: :Number" });
    try check(.{ .step = 9, .rule = 20, .source = ":Tap :: [=>]\n:Trace :: [clean]\n:Gap :: [nil]\n:Mid :: :Trace, :Gap\n:Pointer :: [:Tap/:Mid/:Tap]" });
    try check(.{ .step = 8, .rule = 1, .source = ":Color [brand] := [#d1242f]" });
}

test "Definitions and values: a record binds tokens" {
    try check(.{ .step = 8, .rule = 1, .source = ":Style [night] := { [ink] := [#dddddd], &zone :fill [#1e1e1e] }" });
}

test "Definitions and values: a flag turned off" {
    try check(.{ .step = 8, .rule = 1, .source = "G :: f\nG :style { f :hide! }" });
}

test "Definitions and values: uppercase name" {
    try check(.{ .step = 8, .rule = 2, .source = "[Warn] := [#f00]", .codes = &.{.{ .analysis = .uppercase_name }} });
    try check(.{ .step = 8, .rule = 2, .source = "[w] := [myColor]", .codes = &.{.{ .analysis = .uppercase_name }} });
}

test "Definitions and values: name malformed" {
    try check(.{ .step = 8, .rule = 2, .source = "[w] := [warn_bg]", .codes = &.{.{ .analysis = .malformed_name }} });
}

test "Definitions and values: colour malformed" {
    try check(.{ .step = 8, .rule = 2, .source = ":Color [w] := [#12345]", .codes = &.{.{ .analysis = .malformed_color }} });
}

test "Definitions and values: negative number" {
    try check(.{ .step = 8, .rule = 2, .source = "G :: f\nG.f :bend [-30]", .codes = &.{.{ .analysis = .negative_number }} });
}

test "Definitions and values: number malformed" {
    try check(.{ .step = 8, .rule = 2, .source = "G :: f\nG :style { f :label-at [.5], f :size [1.] }", .codes = &.{
        .{ .analysis = .malformed_number }, .{ .analysis = .malformed_number },
    } });
    try check(.{ .step = 8, .rule = 2, .source = "[big] := [1234567890123456789]", .codes = &.{.{ .analysis = .malformed_number }} });
}

test "Definitions and values: empty range" {
    try check(.{ .step = 8, .rule = 2, .source = "[card] := [5..2/1..*]", .codes = &.{.{ .analysis = .empty_range }} });
}

test "Definitions and values: symbol malformed" {
    try check(.{ .step = 8, .rule = 2, .source = ":Tip :: [=>], [OX]", .codes = &.{.{ .analysis = .malformed_symbol }} });
}

test "Definitions and values: ! misplaced" {
    try check(.{ .step = 8, .rule = 2, .source = "[a] := [1/2!!]", .codes = &.{.{ .analysis = .misplaced_bang }} });
}

test "Definitions and values: every element is read" {
    try check(.{ .step = 8, .rule = 2, .source = "[a] := [Warn/-3]", .codes = &.{
        .{ .analysis = .uppercase_name }, .{ .analysis = .negative_number },
    } });
}

test "Definitions and values: undefined name" {
    try check(.{ .step = 8, .rule = 3, .source = "[w] := [wran]", .codes = &.{.{ .analysis = .undefined_name }} });
    // Before use: a name defined further down is not seen.
    try check(.{ .step = 8, .rule = 3, .source = "[w] := [brand]\n[brand] := [#f00]", .codes = &.{.{ .analysis = .undefined_name }} });
    try check(.{ .step = 8, .rule = 3, .source = "[x] := [>/zigzag/~>]", .codes = &.{
        .{ .analysis = .undefined_name }, .{ .analysis = .undefined_name },
    } });
}

test "Definitions and values: name defined twice" {
    try check(.{ .step = 8, .rule = 3, .source = "[brand] := [#f00]\n[brand] := [#e00]", .codes = &.{.{ .analysis = .name_defined_twice }} });
    try check(.{ .step = 8, .rule = 3, .source = ":Mood :: [calm]\n:Mood :: [calm]", .codes = &.{.{ .analysis = .name_defined_twice }} });
    try check(.{ .step = 8, .rule = 3, .source = ":Mood :: [calm]\n[calm] := [#f00]", .codes = &.{.{ .analysis = .name_defined_twice }} });
    try check(.{ .step = 8, .rule = 3, .source = ":Color :: :Text", .codes = &.{.{ .analysis = .bad_declaration_head }} });
    try check(.{ .step = 8, .rule = 3, .source = "&node :glow :: :Color\n&edge :glow :: :Color", .codes = &.{.{ .analysis = .name_defined_twice }} });
    // The prelude comes first, and its names count.
    try check(.{ .step = 8, .rule = 3, .source = "[red] := [#f00]", .codes = &.{.{ .analysis = .name_defined_twice }} });
    try check(.{ .step = 8, .rule = 3, .source = ":Shape :: [circle]", .codes = &.{.{ .analysis = .name_defined_twice }} });
    // Labels added to a type of the prelude are fine.
    try check(.{ .step = 8, .rule = 3, .source = ":Shape :: [blob]" });
    try check(.{ .step = 8, .rule = 3, .source = "&node :fill :: :Color", .codes = &.{.{ .analysis = .name_defined_twice }} });
}

test "Definitions and values: label in two types" {
    try check(.{ .step = 8, .rule = 3, .source = ":Bow :: [outer]", .codes = &.{.{ .analysis = .label_in_two_types }} });
}

test "Definitions and values: shared words get a type of their own" {
    try check(.{ .step = 8, .rule = 3, .source =
        \\:Near :: [close], [far]
        \\:Here :: [here]
        \\:Where :: :Near, :Here
        \\:Where [away] := [far]
        \\:Where [now] := [here]
        \\:Side [around] := [outer]
    });
}

test "Definitions and values: not a type" {
    try check(.{ .step = 8, .rule = 3, .source = ":Colour [x] := [#f00]", .codes = &.{.{ .analysis = .not_a_type }} });
    try check(.{ .step = 8, .rule = 3, .source = "&node :glow :: [red]", .codes = &.{.{ .analysis = .not_a_type }} });
}

test "Definitions and values: type with parameters" {
    try check(.{ .step = 9, .rule = 20, .source = ":X :: :Color.(:Text)", .codes = &.{.{ .analysis = .type_with_parameters }} });
    try check(.{ .step = 9, .rule = 20, .source = "&zone :backdrops :: :Style.(:Text)", .codes = &.{.{ .analysis = .type_with_parameters }} });
}

test "Definitions and values: type named with :=" {
    // Read as the declaration it meant, so its uses don't fail too.
    try check(.{ .step = 9, .rule = 20, .source = ":Width := :Number\n:Width [w] := [2]", .codes = &.{.{ .analysis = .type_named_with_defn }} });
}

test "Definitions and values: types are spelled like their values" {
    try check(.{ .step = 9, .rule = 20, .source =
        \\:Mood :: [calm], [busy]
        \\:Moods :: [:Mood]
        \\:Pair :: [:Mood/:Mood]
        \\:Either :: (:Mood, :Number)
        \\:Moods [some] := [calm/busy]
        \\:Pair [p] := [calm/busy]
        \\:Either [e] := [2]
        \\&node :mood :: :Mood, :Pair
    });
}

test "Definitions and values: declared types are distinct" {
    // A literal fits by shape; a length is no angle.
    try check(.{ .step = 9, .rule = 20, .source = ":Length [spacing] := [2]\n:Angle [right] := [90]\n:Angle [w] := [spacing]", .codes = &.{.{ .analysis = .contract_broken }} });
    try check(.{ .step = 9, .rule = 20, .source = ":Length [spacing] := [2]\n:Number [n] := [spacing]", .codes = &.{.{ .analysis = .contract_broken }} });
    // A type includes the types its declaration names.
    try check(.{ .step = 9, .rule = 20, .source = ":Wide :: :Length\n:Length [spacing] := [2]\n:Wide [w] := [spacing]" });
}

test "Definitions and values: a declaration adds to its type" {
    try check(.{ .step = 9, .rule = 20, .source = ":Mood :: [calm]\n:Mood :: :Number\n:Mood [a] := [calm]\n:Mood [b] := [2]" });
    try check(.{ .step = 9, .rule = 20, .source = ":Label :: [blank]\n:Label [x] := [blank]" });
}

test "Definitions and values: a type including itself" {
    try check(.{ .step = 9, .rule = 20, .source = ":A :: :Number\n:B :: :A\n:A :: :B", .codes = &.{.{ .analysis = .type_includes_itself }} });
    try check(.{ .step = 9, .rule = 20, .source = ":A :: [:A]", .codes = &.{.{ .analysis = .type_includes_itself }} });
}

test "Definitions and values: types and values mixed, a type as a value" {
    try check(.{ .step = 9, .rule = 20, .source = ":X :: [:Tip/solid/>]", .codes = &.{.{ .analysis = .types_and_values_mixed }} });
    try check(.{ .step = 9, .rule = 20, .source = "[x] := [:Tip/solid/>]", .codes = &.{.{ .analysis = .types_and_values_mixed }} });
    try check(.{ .step = 9, .rule = 20, .source = "[x] := [:Style]", .codes = &.{.{ .analysis = .type_as_value }} });
}

test "Definitions and values: expression in a bracket" {
    try check(.{ .step = 9, .rule = 20, .source = ":Arrow2 :: [:Tip/(:Line,:Nil)/:Tip]", .codes = &.{.{ .syntax = .expression_in_bracket }} });
    try check(.{ .step = 9, .rule = 20, .source = "[x] := [a,b]", .codes = &.{.{ .syntax = .expression_in_bracket }} });
}

test "Definitions and values: nil fits where a type admits it" {
    try check(.{ .step = 9, .rule = 21, .source =
        \\[nothing] := []
        \\:Nil [also] := []
        \\:Arrow [no-tail] := [/solid/>]
        \\:Arrow [no-line] := [>//>]
        \\:Arrow [no-head] := [>/solid/]
        \\:Sizes :: [:Number]
        \\:Sizes [none-yet] := []
        \\:Maybe :: :Color, :Nil
        \\:Maybe [m] := []
        \\:Style [x] := { :theme [], &node :shape [], &node :line [] }
    });
}

test "Definitions and values: nil where a type does not admit it" {
    try check(.{ .step = 9, .rule = 21, .source = ":Color [w] := []", .codes = &.{.{ .analysis = .contract_broken }} });
    try check(.{ .step = 9, .rule = 21, .source = ":Cardinality [c] := [/1..1]", .codes = &.{.{ .analysis = .contract_broken }} });
    try check(.{ .step = 9, .rule = 21, .source = ":Style [x] := { &node :size [] }", .codes = &.{.{ .analysis = .wrong_type }} });
    // A list's nil is no elements, never one of them.
    try check(.{ .step = 9, .rule = 21, .source = ":Sizes :: [:Number]\n:Sizes [s] := [/2]", .codes = &.{.{ .analysis = .contract_broken }} });
    try check(.{ .step = 9, .rule = 21, .source = "[none] := [#000]\n:Shape [s] := [none]", .codes = &.{.{ .analysis = .contract_broken }} });
}

test "Definitions and values: twins" {
    try check(.{ .step = 9, .rule = 20, .source =
        \\:Angle [inward] := [30!]
        \\:Arrow [hooked] := [?!/solid/>]
        \\:Arrow [not] := [/solid!/>]
        \\:Sides :: (:Facing, :On)!
    });
}

test "Definitions and values: not invertible" {
    try check(.{ .step = 9, .rule = 20, .source = ":Length [l] := [2!]", .codes = &.{.{ .analysis = .not_invertible }} });
    try check(.{ .step = 9, .rule = 20, .source = ":Arrow [a] := [>!/solid/>]", .codes = &.{.{ .analysis = .not_invertible }} });
    try check(.{ .step = 9, .rule = 20, .source = ":X :: [:Number/:Number]!", .codes = &.{.{ .analysis = .not_invertible }} });
    try check(.{ .step = 9, .rule = 20, .source = ":X :: [:Style!/:Number]", .codes = &.{.{ .analysis = .not_invertible }} });
}

test "Definitions and values: contract broken" {
    try check(.{ .step = 8, .rule = 3, .source = ":Color [w] := [circle]", .codes = &.{.{ .analysis = .contract_broken }} });
    try check(.{ .step = 8, .rule = 3, .source = ":Pair :: [:Number/:Number]\n:Pair [p] := [1/2/3]", .codes = &.{.{ .analysis = .contract_broken }} });
    try check(.{ .step = 8, .rule = 3, .source = ":Color [w] := { :fill [#f00] }", .codes = &.{.{ .analysis = .contract_broken }} });
}

test "Definitions and values: contracts that hold" {
    try check(.{ .step = 8, .rule = 3, .source =
        \\:Arrow [twice] := [/solid/>>]
        \\:Arrow [ends] := [>//>]
        \\:Sizes :: [:Number]
        \\:Sizes [some] := [1/1.5/2]
        \\:Sizes [one] := [2]
        \\:Sizes [none-yet] := []
        \\:Color [warn] := [#d1242f]
        \\[alias] := [warn]
        \\:Color [again] := [alias]
        \\:Color [fg] := [ink]
    });
}

test "Definitions and values: not a label" {
    try check(.{ .step = 8, .rule = 3, .source = ":Mood :: [#f00], [a/b], [x!]", .codes = &.{
        .{ .analysis = .not_a_label }, .{ .analysis = .not_a_label }, .{ .analysis = .not_a_label },
    } });
}

test "Definitions and values: labels on structure" {
    try check(.{ .step = 9, .rule = 20, .source = ":Flag :: [x]", .codes = &.{.{ .analysis = .labels_on_structure }} });
    try check(.{ .step = 9, .rule = 20, .source = ":Style :: [x]", .codes = &.{.{ .analysis = .labels_on_structure }} });
    try check(.{ .step = 9, .rule = 22, .source = ":Style :: :Shape", .codes = &.{.{ .analysis = .labels_on_structure }} });
    try check(.{ .step = 9, .rule = 22, .source = ":Notes :: { &node :memo :: :Text }\n:Notes :: [x]", .codes = &.{.{ .analysis = .labels_on_structure }} });
}

test "Definitions and values: a record type is declared by its descriptors" {
    try check(.{ .step = 9, .rule = 22, .source = ":Notes :: { &node :memo :: :Text, &zone :todo :: :Flag }\n:Notes [n] := { :todo, &node :memo \"x\" }" });
    // Repeating the declaration adds descriptors.
    try check(.{ .step = 9, .rule = 22, .source = ":Style :: { &node :glow :: :Color }\n:Style [x] := { &node :glow [red] }" });
    // A theme is a style, and `:theme` takes a list of styles.
    try check(.{ .step = 9, .rule = 22, .source = ":Style [x] := { :theme [dark/compact] }" });
    try check(.{ .step = 9, .rule = 22, .source = ":Notes :: { &node :memo :: :Text }\n:Notes [n] := { &node :memo \"x\" }\n:Style [x] := { :theme [n] }", .codes = &.{.{ .analysis = .wrong_type }} });
    // A record's type, unwritten, is its descriptors'.
    try check(.{ .step = 9, .rule = 22, .source = "[x] := { &node :fill [red] }\n:Style [y] := { :theme [x] }" });
    try check(.{ .step = 9, .rule = 22, .source = ":Notes :: { &node :memo :: :Text }\n[n] := { &node :memo \"x\" }\n:Style [y] := { :theme [n] }", .codes = &.{.{ .analysis = .wrong_type }} });
    try check(.{ .step = 9, .rule = 22, .source = ":Color [x] := { &node :fill [red] }", .codes = &.{.{ .analysis = .contract_broken }} });
    try check(.{ .step = 9, .rule = 22, .source = ":Style [x] := [red]", .codes = &.{.{ .analysis = .contract_broken }} });
}

test "Definitions and values: :Record goes" {
    try check(.{ .step = 9, .rule = 22, .source = ":Record [x] := {}", .codes = &.{.{ .analysis = .not_a_type }} });
}

test "Definitions and values: descriptors on a value type" {
    try check(.{ .step = 9, .rule = 22, .source = ":Shape :: { &node :x :: :Color }", .codes = &.{.{ .analysis = .descriptors_on_value_type }} });
    try check(.{ .step = 9, .rule = 22, .source = ":Color :: { &node :x :: :Color }", .codes = &.{.{ .analysis = .descriptors_on_value_type }} });
    try check(.{ .step = 9, .rule = 22, .source = ":Mood :: { [calm], &node :x :: :Color }", .codes = &.{.{ .analysis = .descriptors_on_value_type }} });
}

test "Definitions and values: a naming in a type" {
    try check(.{ .step = 9, .rule = 22, .source = ":Style :: { [ink] := [#fff] }", .codes = &.{.{ .analysis = .naming_in_type }} });
}

test "Definitions and values: a descriptor of another record type does not apply" {
    const notes = ":Notes :: { &node :memo :: :Text }\n";
    try check(.{ .step = 9, .rule = 22, .source = notes ++ ":Style [x] := { &node :memo \"x\" }", .codes = &.{.{ .analysis = .does_not_apply }} });
    try check(.{ .step = 9, .rule = 22, .source = notes ++ ":Notes [n] := { &node :fill [red] }", .codes = &.{.{ .analysis = .does_not_apply }} });
    // A top-level descriptor belongs to no record type.
    try check(.{ .step = 9, .rule = 22, .source = ":Style [x] := { :style {} }", .codes = &.{.{ .analysis = .does_not_apply }} });
    // Under a contract, each foreign descriptor where it is written.
    try check(.{ .step = 9, .rule = 22, .source = notes ++ ":Style [x] := { :memo \"y\", &node :fill [red], &node :memo \"x\" }", .codes = &.{ .{ .analysis = .does_not_apply }, .{ .analysis = .does_not_apply } } });
}

test "Layers: contexts are subjects" {
    const g = "G :: f/#Done g, +(h, k)+ | h/α/k\n";
    try check(.{ .step = 9, .rule = 31, .source = g ++ "G :style { :caption \"G\", #Done :shape [box], (f, g) :label \"x\", g+ :ink [red], +f :ink [red], α :label \"a\", &edge :pen [thin] }" });
    // The top-level shorthand, a class in a diagram, a class everywhere.
    try check(.{ .step = 9, .rule = 31, .source = g ++ "G.g+ :ink [red]\nG.&edge :pen [thin]\n&node :fill [red]\n(G, G.f) :note \"n\"" });
    // `G.f` inside G's block is `f`; braces and groups organise.
    try check(.{ .step = 9, .rule = 31, .source = g ++ "G :style { G.f :label \"x\", { g :label \"y\" }, f { :ink [red] } }" });
}

test "Layers: description at an undeclared context" {
    try check(.{ .step = 9, .rule = 31, .source = "G :style { :caption \"G\" }\nG :: f", .codes = &.{.{ .analysis = .description_at_undeclared_context }} });
    try check(.{ .step = 9, .rule = 31, .source = "X.f :label \"x\"", .codes = &.{.{ .analysis = .description_at_undeclared_context }} });
}

test "Layers: an undeclared name in the diagram" {
    const g = "G :: f g\n";
    try check(.{ .step = 9, .rule = 31, .source = g ++ "G.zz :label \"x\"", .codes = &.{.{ .analysis = .undeclared_name_in_diagram }} });
    try check(.{ .step = 9, .rule = 31, .source = g ++ "G :style { +zz :label \"x\", #Zz :label \"y\" }", .codes = &.{ .{ .analysis = .undeclared_name_in_diagram }, .{ .analysis = .undeclared_name_in_diagram } } });
    try check(.{ .step = 9, .rule = 31, .source = g ++ "G.&nodes :fill [red]", .codes = &.{.{ .analysis = .unknown_class }} });
}

test "Layers: another diagram's subject" {
    const ac = "A :: f\nC :: A.f+/g\n";
    try check(.{ .step = 9, .rule = 31, .source = ac ++ "C :style { A.f+ :fill [red] }", .codes = &.{.{ .analysis = .another_diagrams_subject }} });
    try check(.{ .step = 9, .rule = 31, .source = ac ++ "C :style { A :fill [red] }", .codes = &.{.{ .analysis = .another_diagrams_subject }} });
    // At the top level, A describes itself.
    try check(.{ .step = 9, .rule = 31, .source = ac ++ "A.f+ :fill [red]" });
}

test "Layers: not a subject" {
    const g = "G :: f g\n";
    try check(.{ .step = 9, .rule = 31, .source = g ++ "G :style { f g :label \"x\" }", .codes = &.{.{ .analysis = .not_a_subject }} });
    try check(.{ .step = 9, .rule = 31, .source = g ++ "G :style { f/g :label \"x\" }", .codes = &.{.{ .analysis = .not_a_subject }} });
    try check(.{ .step = 9, .rule = 31, .source = g ++ "G :style { +(f, g)+ :label \"x\" }", .codes = &.{.{ .analysis = .not_a_subject }} });
    // At the top level, a part is qualified by its diagram.
    try check(.{ .step = 9, .rule = 31, .source = g ++ "f :label \"x\"", .codes = &.{.{ .analysis = .not_a_subject }} });
}

test "Layers: an element has no parts" {
    const g = "G :: f/#Done g\n";
    try check(.{ .step = 9, .rule = 31, .source = g ++ "G :style { #Done { f :label \"x\" } }", .codes = &.{.{ .analysis = .element_has_no_parts }} });
    try check(.{ .step = 9, .rule = 31, .source = g ++ "G :style { &node { #Done :fill [red] } }", .codes = &.{.{ .analysis = .element_has_no_parts }} });
    // The owner, described with no context, is fine.
    try check(.{ .step = 9, .rule = 31, .source = g ++ "G :style { #Done { :fill [red], :shape [box] } }" });
}

test "Layers: a node is referenced canonically" {
    // In `f g` the middle node is f+; in `+(f h, g k)+` the canonical
    // references are +f, f+, g+ and h+.
    try check(.{ .step = 9, .rule = 32, .source = "G :: f g\nG.f+ :label \"x\"\nG.+f :label \"s\"" });
    try check(.{ .step = 9, .rule = 32, .source = "G :: +(f h, g k)+\nG :style { +f :label \"a\", f+ :label \"b\", g+ :label \"c\", h+ :label \"d\" }" });
    try check(.{ .step = 9, .rule = 32, .source = "G :: f g\nG.+g :label \"x\"", .codes = &.{.{ .analysis = .non_canonical_reference }} });
    try check(.{ .step = 9, .rule = 32, .source = "G :: +(f h, g k)+\nG :style { +g :label \"a\", +h :label \"b\", +k :label \"c\", k+ :label \"d\" }", .codes = &.{ .{ .analysis = .non_canonical_reference }, .{ .analysis = .non_canonical_reference }, .{ .analysis = .non_canonical_reference }, .{ .analysis = .non_canonical_reference } } });
    // A null node's canonical end is its edge's.
    try check(.{ .step = 9, .rule = 32, .source = "G :: */f g\nG.+f :label \"start\"" });
}

test "Layers: a shared start is named through its first edge (statements.md §23.3)" {
    try check(.{ .step = 9, .rule = 32, .source = "T :: */(id, name)\nT.+id :label \"row\"" });
    try check(.{ .step = 9, .rule = 32, .source = "T :: */(id, name)\nT.+name :label \"row\"", .codes = &.{.{ .analysis = .non_canonical_reference }} });
}

test "Layers: a named node is referenced by its name" {
    try check(.{ .step = 9, .rule = 32, .source = "G :: #A/f g\nG.+f :label \"x\"", .codes = &.{.{ .analysis = .named_node_referenced_by_end }} });
    try check(.{ .step = 9, .rule = 32, .source = "G :: #A/f g\nG.#A :label \"x\"" });
}

test "Layers: a node's descriptors apply to its kind" {
    const knob = ":Style :: { &choice :knob :: :Number, (&start, &end) :dot :: :Color }\n";
    try check(.{ .step = 9, .rule = 33, .source = knob ++ "G :: a/? +(b, c)\nG.a+ :knob [1]" });
    try check(.{ .step = 9, .rule = 33, .source = knob ++ "G :: a/#Done b\nG.#Done :knob [1]", .codes = &.{.{ .analysis = .does_not_apply }} });
    // A null node is a start if no edge arrives at it, else an end.
    try check(.{ .step = 9, .rule = 33, .source = knob ++ "G :: */a b/*\nG :style { +a :dot [red], b+ :dot [red] }" });
    try check(.{ .step = 9, .rule = 33, .source = knob ++ "G :: */a b\nG.a+ :dot [red]", .codes = &.{.{ .analysis = .does_not_apply }} });
    // A class of kinds applies to them, and nodes of every kind take &node's.
    try check(.{ .step = 9, .rule = 33, .source = "G :: a/? +(b, c)\nG :style { a+ :shape [box], &choice :shape [hexagon] }" });
}

test "Layers: a node another diagram made is that diagram's" {
    try check(.{ .step = 9, .rule = 33, .source = "A :: f\nC :: A.f+/g\nC :style { +g :fill [red] }", .codes = &.{.{ .analysis = .another_diagrams_subject }} });
}

test "Layers: binding made twice" {
    const g = "G :: f/#Done g\n";
    try check(.{ .step = 9, .rule = 33, .source = g ++ "G :style { #Done :shape [box], #Done :shape [round] }", .codes = &.{.{ .analysis = .binding_made_twice }} });
    // A layer is open: a block and the top-level shorthand are one layer.
    try check(.{ .step = 9, .rule = 33, .source = g ++ "G :style { f :label \"x\" }\nG.f :label \"y\"", .codes = &.{.{ .analysis = .binding_made_twice }} });
    try check(.{ .step = 9, .rule = 33, .source = g ++ "G :style { (f, f) :label \"x\" }", .codes = &.{.{ .analysis = .binding_made_twice }} });
    try check(.{ .step = 9, .rule = 33, .source = g ++ "G :style { &node :fill [red] }\nG.&node :fill [blue]", .codes = &.{.{ .analysis = .binding_made_twice }} });
    // Different contexts overlap freely; different descriptors, different keys.
    try check(.{ .step = 9, .rule = 33, .source = g ++ "G :style { &node :fill [red], #Done :fill [blue], f :label \"x\", f :ink [red] }\n&node :fill [red]" });
    const legend = ":Style :: { &zone :legend.[] :: :Label }\n";
    try check(.{ .step = 9, .rule = 33, .source = legend ++ g ++ "G :style { :legend.[a] \"x\", :legend.[b] \"y\", :legend \"z\", :legend \"w\" }" });
    try check(.{ .step = 9, .rule = 33, .source = legend ++ g ++ "G :style { :legend.[a] \"x\", :legend.[a] \"y\" }", .codes = &.{.{ .analysis = .binding_made_twice }} });
}

test "Layers: what is read is checked against :Style" {
    const g = "G :: f g\n";
    try check(.{ .step = 9, .rule = 31, .source = g ++ "G.f :memo \"x\"", .codes = &.{.{ .analysis = .unknown_attribute }} });
    try check(.{ .step = 9, .rule = 31, .source = g ++ "G :style { f+ :shape [red] }", .codes = &.{.{ .analysis = .wrong_type }} });
    try check(.{ .step = 9, .rule = 31, .source = g ++ "G :style { f :shape [box] }", .codes = &.{.{ .analysis = .does_not_apply }} });
    try check(.{ .step = 9, .rule = 31, .source = g ++ "G :style { :style { :fill [red] } }", .codes = &.{.{ .analysis = .does_not_apply }} });
}

test "Definitions and values: an empty arrow" {
    try check(.{ .step = 9, .rule = 24, .source = ":Style [x] := { &edge :arrow [//] }", .codes = &.{.{ .analysis = .empty_arrow }} });
    try check(.{ .step = 9, .rule = 24, .source = ":Arrow [nothing] := [//]", .codes = &.{.{ .analysis = .empty_arrow }} });
    try check(.{ .step = 9, .rule = 24, .source = "[nothing] := [//]\n:Style [x] := { &edge :arrow [nothing] }", .codes = &.{.{ .analysis = .empty_arrow }} });
    // Any field may be empty, and the arrow itself may be nil: computed.
    try check(.{ .step = 9, .rule = 24, .source = ":Style [x] := { &edge :arrow [>//>], &cell :arrow [/solid/], &cell :arrow [] }" });
}

test "Definitions and values: nil takes a value away" {
    try check(.{ .step = 9, .rule = 24, .source = ":Style [x] := { &node { :fill [], :stroke [], :font [], :wrap [], :step [], :label [] }, &zone :caption [] }" });
    try check(.{ .step = 9, .rule = 24, .source = ":Style [x] := { &node :size [] }", .codes = &.{.{ .analysis = .wrong_type }} });
    try check(.{ .step = 9, .rule = 24, .source = ":Style [x] := { &node :line [triple] }" });
}

test "Definitions and values: a table is declared by its key slot" {
    const legend = ":Style :: { &zone :legend.[] :: :Label }\n";
    try check(.{ .step = 9, .rule = 23, .source = legend ++ ":Style [x] := { :legend.[done] \"green: shipped\", :legend.[late] \"red: overdue\", :legend \"grey\" }" });
    // Keys are optional; a flag table takes a key and nothing else.
    try check(.{ .step = 9, .rule = 23, .source = ":Style :: { &node :seen.[] :: :Flag }\n:Style [x] := { &node { :seen.[a], :seen } }" });
    try check(.{ .step = 9, .rule = 23, .source = legend ++ ":Style [x] := { :legend.[a] }", .codes = &.{.{ .analysis = .value_missing }} });
}

test "Definitions and values: key in a declaration" {
    try check(.{ .step = 9, .rule = 23, .source = ":Style :: { &zone :legend.[a] :: :Label }", .codes = &.{.{ .analysis = .key_in_declaration }} });
    try check(.{ .step = 9, .rule = 23, .source = "&zone :legend.[/] :: :Label", .codes = &.{.{ .analysis = .key_in_declaration }} });
}

test "Definitions and values: key not taken" {
    try check(.{ .step = 9, .rule = 23, .source = ":Style [x] := { &node :fill.[a] [red] }", .codes = &.{.{ .analysis = .key_not_taken }} });
    try check(.{ .step = 9, .rule = 23, .source = ":t := { :shape [box] }\n:Style [x] := { &node :t.[a] }", .codes = &.{.{ .analysis = .key_not_taken }} });
    try check(.{ .step = 9, .rule = 23, .source = ":t := { :fill.[a] [red] }", .codes = &.{.{ .analysis = .key_not_taken }} });
}

test "Definitions and values: key malformed" {
    const legend = ":Style :: { &zone :legend.[] :: :Label }\n";
    try check(.{ .step = 9, .rule = 23, .source = legend ++ ":Style [x] := { :legend.[] \"x\" }", .codes = &.{.{ .analysis = .key_malformed }} });
    try check(.{ .step = 9, .rule = 23, .source = legend ++ ":Style [x] := { :legend.[a/b] \"x\" }", .codes = &.{.{ .analysis = .key_malformed }} });
    try check(.{ .step = 9, .rule = 23, .source = legend ++ ":Style [x] := { :legend.[#fff] \"x\" }", .codes = &.{.{ .analysis = .key_malformed }} });
    try check(.{ .step = 9, .rule = 23, .source = legend ++ ":Style [x] := { :legend.[a!] \"x\" }", .codes = &.{.{ .analysis = .key_malformed }} });
    try check(.{ .step = 9, .rule = 23, .source = legend ++ ":Style [x] := { :legend.[Done] \"x\" }", .codes = &.{.{ .analysis = .uppercase_name }} });
}

test "Definitions and values: a record is checked by its structure where it is used" {
    const notes = ":Notes :: { &node :memo :: :Text }\n";
    // No type: fine on its own, whatever its descriptors.
    try check(.{ .step = 9, .rule = 22, .source = notes ++ "[x] := { &node :fill [red], &node :memo \"x\" }" });
    // Wrong where a :Style is expected, and where a :Notes is.
    try check(.{ .step = 9, .rule = 22, .source = notes ++ "[x] := { &node :fill [red], &node :memo \"x\" }\n:Style [y] := { :theme [x] }", .codes = &.{.{ .analysis = .wrong_type }} });
    try check(.{ .step = 9, .rule = 22, .source = notes ++ "[x] := { &node :fill [red] }\n[y] := { &node :fill [blue] }\n:Style [z] := { :theme [x/y] }" });
    try check(.{ .step = 9, .rule = 22, .source = notes ++ "[x] := { &node :fill [red] }\n[n] := { &node :memo \"x\" }\n:Style [z] := { :theme [x/n] }", .codes = &.{.{ .analysis = .wrong_type }} });
    // A name for named records keeps their structure.
    try check(.{ .step = 9, .rule = 22, .source = notes ++ "[n] := { &node :memo \"x\" }\n[both] := [dark/n]\n:Style [z] := { :theme [both] }", .codes = &.{.{ .analysis = .wrong_type }} });
    try check(.{ .step = 9, .rule = 22, .source = notes ++ "[n] := { &node :memo \"x\" }\n:Style [both] := [dark/n]", .codes = &.{.{ .analysis = .contract_broken }} });
    // A contract checks, and names no type: [n] is still a record.
    try check(.{ .step = 9, .rule = 22, .source = notes ++ ":Notes [n] := { &node :memo \"x\" }\n:Notes [m] := { &node :memo \"y\" }\n[both] := [n/m]" });
}

test "Definitions and values: a bundle is checked where it is used" {
    const notes = ":Notes :: { &node :memo :: :Text }\n";
    // Fine on its own, wrong in both record types.
    try check(.{ .step = 9, .rule = 22, .source = notes ++ ":key := { :memo \"k\", :fill [red] }" });
    try check(.{ .step = 9, .rule = 22, .source = notes ++ ":key := { :memo \"k\", :fill [red] }\n:Style [x] := { &node :key }", .codes = &.{.{ .analysis = .does_not_apply }} });
    try check(.{ .step = 9, .rule = 22, .source = notes ++ ":key := { :memo \"k\", :fill [red] }\n:Notes [n] := { &node :key }", .codes = &.{.{ .analysis = .does_not_apply }} });
    // Through a bundle in a bundle.
    try check(.{ .step = 9, .rule = 22, .source = notes ++ ":key := { :memo \"k\" }\n:outer := { :key }\n:Style [x] := { &node :outer }", .codes = &.{.{ .analysis = .does_not_apply }} });
    // One error per use, however many contents are foreign.
    try check(.{ .step = 9, .rule = 22, .source = notes ++ ":Notes :: { &node :tag :: :Text }\n:key := { :memo \"k\", :tag \"t\" }\n:Style [x] := { &node :key }", .codes = &.{.{ .analysis = .does_not_apply }} });
    try check(.{ .step = 9, .rule = 22, .source = ":terminal := { :shape [circle], :fill [red] }\n:Style [x] := { &node :terminal }" });
}

test "Definitions and values: tokens are labels added to a colour" {
    try check(.{ .step = 8, .rule = 3, .source = ":Color :: [highlight]\n:Color [text] := [highlight]" });
}

test "Definitions and values: unknown class" {
    try check(.{ .step = 8, .rule = 3, .source = "(&nodes, &zone) :fill :: :Color", .codes = &.{.{ .analysis = .unknown_class }} });
}

test "Definitions and values: a bundle, applied where all its contents apply" {
    try check(.{ .step = 8, .rule = 5, .source = ":terminal := { :shape [circle], :fill [red] }" });
    try check(.{ .step = 8, .rule = 5, .source = ":ref := :shape [round], :fill [muted]" });
    try check(.{ .step = 8, .rule = 5, .source = ":terminal := :shape [circle]\n:done := { :terminal, :hide! }" });
    try check(.{ .step = 8, .rule = 5, .source = ":faded := { :ink [muted], :pen [thin] }" });
}

test "Definitions and values: a theme: tokens, classes, and functions binding its diagram" {
    try check(.{ .step = 8, .rule = 5, .source = ":Style [paper] := { [ink] := [#000], :fill [white], &node { :fill [white], &choice :shape [box] }, &hole :line [dashed] }" });
    try check(.{ .step = 8, .rule = 5, .source = "[plainer] := { [circle] := [box] }" });
}

test "Definitions and values: unknown attribute" {
    try check(.{ .step = 8, .rule = 5, .source = ":Style [x] := { &node :colour [red] }", .codes = &.{.{ .analysis = .unknown_attribute }} });
    try check(.{ .step = 8, .rule = 5, .source = ":t := { :terminal }\n:terminal := :shape [circle]", .codes = &.{.{ .analysis = .unknown_attribute }} });
}

test "Definitions and values: does not apply" {
    try check(.{ .step = 8, .rule = 5, .source = ":Style [x] := { &edge :fill [red] }", .codes = &.{.{ .analysis = .does_not_apply }} });
    try check(.{ .step = 8, .rule = 5, .source = ":Style [x] := { &node :arrow [mono] }", .codes = &.{.{ .analysis = .does_not_apply }} });
    try check(.{ .step = 8, .rule = 5, .source = ":Style [x] := { :shape [box] }", .codes = &.{.{ .analysis = .does_not_apply }} });
    try check(.{ .step = 8, .rule = 5, .source = ":t := { :fill [red], :arrow [mono] }", .codes = &.{.{ .analysis = .does_not_apply }} });
    try check(.{ .step = 8, .rule = 5, .source = ":Style :: { &choice :knob :: :Number }\n:Style [x] := { &node :knob [1], &choice :knob [1] }", .codes = &.{.{ .analysis = .does_not_apply }} });
    try check(.{ .step = 8, .rule = 5, .source = ":t := :shape [box]\n:Style [x] := { &edge :t }", .codes = &.{.{ .analysis = .does_not_apply }} });
}

test "Definitions and values: wrong type" {
    try check(.{ .step = 8, .rule = 5, .source = ":Style [x] := { &node :shape [red] }", .codes = &.{.{ .analysis = .wrong_type }} });
    try check(.{ .step = 8, .rule = 5, .source = ":Style [x] := { :theme [circle] }", .codes = &.{.{ .analysis = .wrong_type }} });
    try check(.{ .step = 8, .rule = 5, .source = ":Style [x] := { &node :label [1] }", .codes = &.{.{ .analysis = .wrong_type }} });
    try check(.{ .step = 8, .rule = 5, .source = ":spare := []", .codes = &.{.{ .analysis = .wrong_type }} });
}

test "Definitions and values: values a theme can take" {
    try check(.{ .step = 8, .rule = 5, .source = ":Style [x] := { :theme [dark/compact], &edge { :arrow [/dashed/>], :label-at [0.3] }, &node :label $x$ }" });
}

test "Definitions and values: value given to a flag, value missing" {
    try check(.{ .step = 8, .rule = 5, .source = ":Style [x] := { &node :hide [on] }", .codes = &.{.{ .analysis = .value_given_to_flag }} });
    try check(.{ .step = 8, .rule = 5, .source = ":Style [x] := { &node :shape }", .codes = &.{.{ .analysis = .value_missing }} });
}

test "Definitions and values: only a flag inverts, as not invertible" {
    try check(.{ .step = 9, .rule = 20, .source = ":Style [x] := { &node :fill! }", .codes = &.{.{ .analysis = .not_invertible }} });
    try check(.{ .step = 9, .rule = 20, .source = ":terminal := :shape [circle]\n:Style [x] := { &node :terminal! }", .codes = &.{.{ .analysis = .not_invertible }} });
    try check(.{ .step = 9, .rule = 20, .source = ":Style [x] := { &node :size [2!], &edge :bend [30!] }", .codes = &.{.{ .analysis = .not_invertible }} });
}

test "Definitions and values: key of the wrong type" {
    try check(.{ .step = 8, .rule = 5, .source = ":Style [x] := { [ink] := [circle] }", .codes = &.{.{ .analysis = .key_of_wrong_type }} });
    try check(.{ .step = 8, .rule = 5, .source = ":Style [x] := { [red] := [#fff] }", .codes = &.{.{ .analysis = .not_a_label }} });
    try check(.{ .step = 8, .rule = 5, .source = ":Style [x] := { [inc] := [#fff] }", .codes = &.{.{ .analysis = .undefined_name }} });
}

test "Definitions and values: subject in a bundle" {
    try check(.{ .step = 8, .rule = 5, .source = ":t := { &node :fill [red] }", .codes = &.{.{ .analysis = .subject_in_bundle }} });
    try check(.{ .step = 8, .rule = 5, .source = ":t := { [ink] := [#fff] }", .codes = &.{.{ .analysis = .subject_in_bundle }} });
}

test "Definitions and values: element in a theme" {
    try check(.{ .step = 8, .rule = 5, .source = "G :: f\n:Style [x] := { G.f :pen [thin] }", .codes = &.{.{ .analysis = .element_in_theme }} });
    try check(.{ .step = 8, .rule = 5, .source = "G :: f\n:Style [x] := { G.&edge :pen [thin] }", .codes = &.{.{ .analysis = .element_in_theme }} });
}

test "Definitions and values: a bundle defined twice" {
    try check(.{ .step = 8, .rule = 5, .source = ":t := :hide\n:t := :hide", .codes = &.{.{ .analysis = .name_defined_twice }} });
    try check(.{ .step = 8, .rule = 5, .source = ":fill := :hide", .codes = &.{.{ .analysis = .name_defined_twice }} });
}

test "Statements: a signature's subjects are classes" {
    try check(.{ .step = 8, .rule = 1, .source = "G :: f\nG.f :fill :: :Color", .codes = &.{.{ .analysis = .bad_declaration_head }} });
}

test "Proofs: different operators without a group" {
    try check(.{ .step = 5, .source = "G :: f\nG :prove { :axiom (f == g ~= h) }", .codes = &.{.{ .analysis = .mixed_operators }} });
}

test "Proofs: different operators, grouped" {
    try check(.{ .step = 5, .source = "G :: f\nG :prove { :axiom ((f == g) ~= h, f == g == h) }" });
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

test "Relations: a diagram before a space" {
    try check(.{ .step = 5, .rule = 1, .source = "A :: f\nG :: A (f)", .codes = &.{.{ .analysis = .node_beside_space }} });
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
    try check(.{ .step = 5, .rule = 1, .source = "G :: *", .codes = &.{.{ .analysis = .null_not_on_one_side }} });
}

test "Relations: a null node between edges" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: f/*/g", .codes = &.{.{ .analysis = .null_not_on_one_side }} });
}

test "Relations: a null node in a cycle" {
    try check(.{ .step = 5, .rule = 1, .source = "G :: */f/g", .codes = &.{.{ .analysis = .null_not_on_one_side }} });
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
    try check(.{ .step = 4, .source = "G :style { #Done :terminal f :label \"x\" }", .codes = &.{.{ .syntax = .missing_comma }} });
}

test "Statements: a trailing comma in a group" {
    try check(.{ .step = 4, .source = "G :: (f, g,)", .codes = &.{.{ .syntax = .trailing_comma }} });
}

test "Statements: a trailing comma in braces" {
    try check(.{ .step = 4, .source = "G :style { a :x, }", .codes = &.{.{ .syntax = .trailing_comma }} });
}

test "Statements: empty braces in a declaration" {
    try check(.{ .step = 4, .source = "G :: {}", .codes = &.{.{ .syntax = .empty_braces }} });
}

test "Statements: empty braces are only a value" {
    try check(.{ .step = 9, .rule = 22, .source = "G :: f\nG :style {}\n:Style [x] := {}" });
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

test "Levels: side not declared" {
    try check(.{ .step = 7, .rule = 4, .source = "G :: +(f, g)+ | f/α/#B", .codes = &.{.{ .analysis = .side_not_declared }} });
}

test "Levels: not a cell" {
    try check(.{ .step = 7, .rule = 1, .source = "G :: +(f, g)+ | f/α/*", .codes = &.{.{ .analysis = .not_a_cell }} });
    try check(.{ .step = 7, .rule = 1, .source = "G :: +(f, g)+ | f/α/?", .codes = &.{.{ .analysis = .not_a_cell }} });
    try check(.{ .step = 7, .rule = 1, .source = "A :: #X/f\nG :: +(f, g)+ | f/α/A.#X", .codes = &.{.{ .analysis = .not_a_cell }} });
    try check(.{ .step = 7, .rule = 1, .source = "A :: f\nG :: +(f, g)+ | A.α", .codes = &.{.{ .analysis = .not_a_cell }} });
}

test "Levels: pinch above level 1" {
    try check(.{ .step = 7, .rule = 1, .source = "G :: +(f, g)+ | +(α, β)", .codes = &.{.{ .analysis = .pinch_above_level_one }} });
    try check(.{ .step = 7, .rule = 1, .source = "G :: +(f, g)+ | f/α/g, +α/β/g", .codes = &.{.{ .analysis = .pinch_above_level_one }} });
}

test "Levels: path as a side" {
    try check(.{ .step = 7, .rule = 2, .source = "G :: +(f h, g)+ | (f h)/α/g", .codes = &.{.{ .analysis = .path_as_side }} });
}

test "Levels: unnamed side" {
    try check(.{ .step = 7, .rule = 2, .source = "G :: +(f, g)+ | f/α β/g", .codes = &.{.{ .analysis = .unnamed_side }} });
    try check(.{ .step = 7, .rule = 2, .source = "G :: +(f, g)+ | α", .codes = &.{.{ .analysis = .unnamed_side }} });
    try check(.{ .step = 7, .rule = 2, .source = "G :: +(f, g)+ | (α, β)/g", .codes = &.{ .{ .analysis = .unnamed_side }, .{ .analysis = .unnamed_side } } });
}

test "Levels: two names for one side" {
    try check(.{ .step = 7, .rule = 2, .source = "G :: +(f, g, h, k)+ | f/α/g h/β/k", .codes = &.{.{ .analysis = .two_names_for_one_side }} });
}

test "Levels: a cell declared twice" {
    try check(.{ .step = 7, .rule = 2, .source = "G :: +(f, g)+ | f/α/g, f/α/g", .codes = &.{.{ .analysis = .edge_declared_twice }} });
}

test "Levels: a level inside a block" {
    try check(.{ .step = 7, .rule = 2, .source = "G :: f, { g | α }", .codes = &.{.{ .analysis = .level_inside_branch }} });
}

test "Levels: cells between non-parallel cells" {
    try check(.{ .step = 7, .rule = 3, .source = "Sq :: +(f h, g k)+ | f/α/h", .codes = &.{.{ .analysis = .cells_not_parallel }} });
    try check(.{ .step = 7, .rule = 3, .source = "G :: +(f, g, h)+ | f/(α, β)/g, f/γ/h | α/m/γ", .codes = &.{.{ .analysis = .cells_not_parallel }} });
    // 1_B starts at B, and f at A.
    try check(.{ .step = 7, .rule = 4, .source = "G :: #A/f/#B | f/α/#B", .codes = &.{.{ .analysis = .cells_not_parallel }} });
}

test "Levels: a lower side is an identity" {
    try check(.{ .step = 7, .rule = 4, .source = "C :: #A/f/#A | f/α/#A", .ir =
        \\zone C
        \\  node n0 #A
        \\  edge f n0 -> n0
        \\  cell α f => n0
        \\
    });
    try check(.{ .step = 7, .rule = 4, .source = "D :: #A/f/#A | f/α/f | α/m/f", .ir =
        \\zone D
        \\  node n0 #A
        \\  edge f n0 -> n0
        \\  cell α f => f
        \\  cell m α => f level 3
        \\
    });
}

test "Levels: undirected sides and cells" {
    try check(.{ .step = 7, .rule = 4, .source = "U :: #A/f/#B/, #B/g/#A | f/α/g", .ir =
        \\zone U
        \\  node n0 #A
        \\  node n1 #B
        \\  edge f n0 -- n1
        \\  edge g n1 -> n0
        \\  cell α f => g
        \\
    });
    try check(.{ .step = 7, .rule = 4, .source = "G :: +(f, g)+ | f/α/g/", .ir =
        \\zone G
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\  edge g n0 -> n1
        \\  cell α f == g
        \\
    });
}

test "Levels: the spec's cells" {
    try check(.{ .step = 7, .rule = 2, .source = "Mod :: +(f, g)+ | f/(α, β)/g | α/m/β", .ir =
        \\zone Mod
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\  edge g n0 -> n1
        \\  cell α f => g
        \\  cell β f => g
        \\  cell m α => β level 3
        \\
    });
    try check(.{ .step = 7, .rule = 2, .source = "Vc :: +(f, g, h)+ | f/α/g, g/β/h", .ir =
        \\zone Vc
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\  edge g n0 -> n1
        \\  edge h n0 -> n1
        \\  cell α f => g
        \\  cell β g => h
        \\
    });
}

test "Levels: the spec's examples" {
    try check(.{ .step = 7, .rule = 1, .source =
        \\Nat :: +(f, g)+ | f/α/g
        \\Eq  :: +(f, g)+ | f/α/g/β
        \\Vc  :: +(f, g, h)+ | f/α/g, g/β/h
        \\Vs  :: +(f, g, h)+ | f/α g/β/h
        \\Mod :: +(f, g)+ | f/(α, β)/g | α/m/β
        \\Iso :: {
        \\  +(f, g)+
        \\  | f/α/g/β
        \\}
    });
}

// ---------------------------------------------------------------------------
// Examples (the spec's Examples section)

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
        \\Order :style {
        \\  #Received  :label "Order received",
        \\  validate+  :label "Valid?",
        \\  charge+    :label "Payment accepted?",
        \\  #Waiting   :label "Wait 10 min",
        \\  reserve+   :label "In stock?",
        \\  #Shipped   :label "Shipped",
        \\  #Rejected  :label "Rejected",
        \\  (yes, paid, reserved)  :label "yes",
        \\  (no, declined, short)  :label "no",
        \\  (retry, restock)       { :arrow [/dashed/>], :bend [inner] }
        \\}
    });
}

test "Examples: a database schema: documents and comments" {
    try check(.{ .step = 5, .source =
        \\T :: #UUID7, #DTZ, #String, #Text, #JSONB, #Bool
        \\
        \\User         :: */(id/T.#UUID7, email/T.#String, nick/T.#String, name/T.#String, created_at/T.#DTZ)
        \\Organization :: */(id/T.#UUID7, name/T.#String)
        \\Membership   :: */(id/T.#UUID7, admin/T.#Bool)
        \\Project      :: */(id/T.#UUID7, name/T.#String)
        \\Document     :: */(id/T.#UUID7, title/T.#String, body/T.#JSONB)
        \\Comment      :: */(id/T.#UUID7, text/T.#Text)
        \\Tag          :: */(id/T.#UUID7, label/T.#String)
        \\Tagging      :: */id/T.#UUID7
        \\
        \\Db :: {
        \\  Membership/(user/User, org/Organization),
        \\  Project/owner/Organization,
        \\  Document/(project/Project, author/User),
        \\  Comment/(document/Document, writer/User, parent/Comment),
        \\  Tagging/(doc/Document, tag/Tag)
        \\}
        \\
        \\Db :prove {
        \\  :kind [schema],
        \\
        \\  :axiom (&node.id :pk, &edge :card [0..*/1]),
        \\  :axiom (User.(email, nick)! :uk, Tag.label :uk, (user, org)! :uk, (doc, tag)! :uk),
        \\  :axiom (parent { :nullable, :card [0..*/0..1] }),
        \\  :axiom (parent document == document)    // a reply is on the same document as its parent
        \\}
        \\
        \\Db :style { writer :label "author_id" }
        \\User :style { :label "users", :fill [muted] }
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
        \\:ref := :shape [round], :fill [muted]
        \\
        \\Repo :style {
        \\  &node :shape [point],
        \\  #Head    { :ref, :label "main" },
        \\  #Feature { :ref, :label "feature/auth" },
        \\  #V1      { :ref, :label "v1.0" },
        \\  #Spike   { :ref, :label "spike/cache" },
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
        \\Repo :prove {
        \\  :kind [category],
        \\  :axiom (fix merge == login session merge'),   // both paths from the fork reach the same state
        \\  :lemma.[clean] (#Merged :pushout)              // fAB checks the merge is clean: the least common state
        \\}
        ,
    });
}

// ---------------------------------------------------------------------------
// Styles, as they resolve (step 9e2): the spec's styled examples, and the
// cascade as the spec states it.

test "Program structure: a block is factored contexts" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\G :: f/#Done
        \\:terminal := { :shape [circle], :fill [red] }
        \\G :style { #Done :terminal, f :label "x" }
    , .sheet =
        \\zone G
        \\  node n1: fill [#cf222e] program, shape [circle] program
        \\  edge f: label "x" program
        \\
    });
}

test "Program structure: a block, expanded" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\G :: f/#Done
        \\:terminal := { :shape [circle], :fill [red] }
        \\G.#Done :terminal
        \\G.f :label "x"
    , .sheet =
        \\zone G
        \\  node n1: fill [#cf222e] program, shape [circle] program
        \\  edge f: label "x" program
        \\
    });
}

test "Style layer: the example" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\G :: f g
        \\
        \\G :style {
        \\    f  { :arrow [epi], :stroke [#c0392b] },
        \\    +f {
        \\        :label $\mathbb{R}$,
        \\        :shape [circle]
        \\    },
        \\    f+ :label $\mathbb{N}$,
        \\    g+ :label $\sigma$
        \\}
    , .sheet =
        \\zone G
        \\  node n0: label $\mathbb{R}$ program, shape [circle] program
        \\  node n1: label $\mathbb{N}$ program
        \\  node n2: label $\sigma$ program
        \\  edge f: stroke [#c0392b] program, arrow [/solid/>>] program
        \\
    });
}

test "Specificity: a class, a narrower class, a class in a diagram, an element" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\G :: */f/? +(g, h)
        \\&node   :fill [#111111]
        \\&choice :fill [#222222]
        \\&choice :line [dotted]
        \\G :style { &node { :stroke [#333333], :line [dashed] }, &choice :stroke [#444444], g+ :stroke [#555555] }
    , .sheet =
        \\zone G
        \\  node n0: fill [#111111] program, stroke [#333333] program, line [dashed] program
        \\  node n1: fill [#222222] program, stroke [#444444] program, line [dashed] program
        \\  node n2: fill [#111111] program, stroke [#555555] program, line [dashed] program
        \\  node n3: fill [#111111] program, stroke [#333333] program, line [dashed] program
        \\
    });
}

test "Themes: [base], then themes left to right, then the program" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\:Style [one] := { &node :fill [#111111], &edge :stroke [#111111], &zone :fill [#111111] }
        \\:Style [two] := { &node :fill [#222222] }
        \\G :: f
        \\G :style { :theme [one/two], f :stroke [#333333] }
    , .sheet =
        \\zone G: fill [#111111] theme
        \\  node n0: fill [#222222] theme
        \\  node n1: fill [#222222] theme
        \\  edge f: stroke [#333333] program
        \\
    });
}

test "Themes: a theme includes others, applied before its own bindings" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\:Style [night] := { :theme [dark], [accent] := [#58a6ff] }
        \\G :: f
        \\G :style { :theme [night] }
    , .sheet =
        \\zone G: fill [#1e1e1e] theme
        \\  token ink [#dddddd]
        \\  token soft [#aaaaaa]
        \\  token accent [#58a6ff]
        \\
    });
}

test "Themes: a later layer turns a flag off, and takes a value away with nil" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\:Style [hidden] := { &edge :hide, &zone :fill [#111111] }
        \\G :: f
        \\G :style { :theme [hidden], :fill [], f :hide! }
    , .sheet =
        \\zone G: fill [] program
        \\  edge f: hide! program
        \\
    });
}

test "Themes: a diagram's own tokens, after its themes; any label rebound" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\G :: f
        \\G :style { :theme [dark], [ink] := [#000000], [circle] := [box] }
    , .sheet =
        \\zone G: fill [#1e1e1e] theme
        \\  token ink [#000000]
        \\  token soft [#aaaaaa]
        \\  token circle [box]
        \\
    });
}

test "Text: a label resolves in three ways" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\G :: f g h
        \\G :style { f :label [], g :label "Lorem", h :label "" }
    , .sheet =
        \\zone G
        \\  edge g: label "Lorem" program
        \\  edge h: label "" program
        \\
    });
}

test "Each diagram styles itself, and its members' classes" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\Master  :: */a b
        \\Feature :: Master.(a+)/c
        \\Repo    :: Master, Feature
        \\&node :line [dashed]
        \\Feature :style { &node :shape [box] }
        \\Repo :style { :fill [#123456], &node { :shape [point], :line [dotted], :fill [#00ff00] }, [ink] := [#ff0000] }
    , .sheet =
        \\zone Master
        \\  token ink [#ff0000]
        \\  node n0: fill [#00ff00] program, line [dashed] program, shape [point] program
        \\  node n1: fill [#00ff00] program, line [dashed] program, shape [point] program
        \\  node n2: fill [#00ff00] program, line [dashed] program, shape [point] program
        \\zone Feature
        \\  token ink [#ff0000]
        \\  node n3: fill [#00ff00] program, line [dashed] program, shape [box] program
        \\zone Repo: fill [#123456] program
        \\  token ink [#ff0000]
        \\  node n4: fill [#00ff00] program, line [dotted] program, shape [point] program
        \\  node n5: fill [#00ff00] program, line [dotted] program, shape [point] program
        \\
    });
}

test "Examples: a flowchart, order fulfilment" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\Order :: {
        \\    */receive/#Received validate/? +(
        \\        yes/#Accepted fork/! +(
        \\            charge/? +(paid, declined/#Waiting/retry)
        \\            , reserve/? +(reserved, short/#Backorder/restock)
        \\        )! ready/#Ready ship/#Shipped close/*
        \\        , no/#Rejected notify/*
        \\    )
        \\}
        \\
        \\Order :style {
        \\    #Received             :label "Order received",
        \\    validate+             :label "Valid?",
        \\    charge+               :label "Payment accepted?",
        \\    #Waiting              :label "Wait 10 min",
        \\    reserve+              :label "In stock?",
        \\    #Shipped              :label "Shipped",
        \\    #Rejected             :label "Rejected",
        \\    (yes, paid, reserved) :label "yes",
        \\    (no, declined, short) :label "no",
        \\    (retry, restock)      { :arrow [/dashed/>], :bend [inner] }
        \\}
    , .sheet =
        \\zone Order
        \\  node n1: label "Order received" program
        \\  node n2: label "Valid?" program
        \\  node n5: label "Payment accepted?" program
        \\  node n7: label "Wait 10 min" program
        \\  node n8: label "In stock?" program
        \\  node n11: label "Shipped" program
        \\  node n13: label "Rejected" program
        \\  edge yes: label "yes" program
        \\  edge paid: label "yes" program
        \\  edge declined: label "no" program
        \\  edge retry: arrow [/dashed/>] program, bend [inner] program
        \\  edge reserved: label "yes" program
        \\  edge short: label "no" program
        \\  edge restock: arrow [/dashed/>] program, bend [inner] program
        \\  edge no: label "no" program
        \\
    });
}

test "Examples: a database schema, documents and comments" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\T :: #UUID7, #DTZ, #String, #Text, #JSONB, #Bool
        \\
        \\User         :: */(id/T.#UUID7, email/T.#String, nick/T.#String, name/T.#String, created_at/T.#DTZ)
        \\Organization :: */(id/T.#UUID7, name/T.#String)
        \\Membership   :: */(id/T.#UUID7, admin/T.#Bool)
        \\Project      :: */(id/T.#UUID7, name/T.#String)
        \\Document     :: */(id/T.#UUID7, title/T.#String, body/T.#JSONB)
        \\Comment      :: */(id/T.#UUID7, text/T.#Text)
        \\Tag          :: */(id/T.#UUID7, label/T.#String)
        \\Tagging      :: */id/T.#UUID7
        \\
        \\Db :: {
        \\    Membership/(user/User, org/Organization),
        \\    Project/owner/Organization,
        \\    Document/(project/Project, author/User),
        \\    Comment/(document/Document, writer/User, parent/Comment),
        \\    Tagging/(doc/Document, tag/Tag)
        \\}
        \\
        \\Db :prove {
        \\    :kind [schema],
        \\
        \\    :axiom (&node.id :pk, &edge :card [0..*/1]),
        \\    :axiom (User.(email, nick)! :uk, Tag.label :uk, (user, org)! :uk, (doc, tag)! :uk),
        \\    :axiom (parent { :nullable, :card [0..*/0..1] }),
        \\    :axiom (parent document == document)  // a reply is on the same document as its parent
        \\}
        \\
        \\Db   :style { writer :label "author_id" }
        \\User :style { :label "users", :fill [muted] }
    , .sheet =
        \\zone T
        \\zone User: label "users" program, fill [#888888] program
        \\zone Organization
        \\zone Membership
        \\zone Project
        \\zone Document
        \\zone Comment
        \\zone Tag
        \\zone Tagging
        \\zone Db: stroke [#8250df] mark, caption "unsupported" mark
        \\  edge writer: label "author_id" program
        \\
    });
}

test "Examples: a git history, commits as arrows" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\Repo :: {
        \\    */init readme/#Fork +(fix/#Main, login session/#Feature),
        \\    (#Main/merge, #Feature/merge')/#Merged bump/#V1 +(hotfix/#Head, spike/#Spike)
        \\}
        \\
        \\:ref := :shape [round], :fill [muted]
        \\
        \\Repo :style {
        \\    &node    :shape [point],
        \\    #Head    { :ref, :label "main" },
        \\    #Feature { :ref, :label "feature/auth" },
        \\    #V1      { :ref, :label "v1.0" },
        \\    #Spike   { :ref, :label "spike/cache" },
        \\    init     :label "a1f3 init",
        \\    readme   :label "b27c add readme",
        \\    fix      :label "c90e fix typo",
        \\    login    :label "d4a1 login form",
        \\    session  :label "e5b2 sessions",
        \\    merge    :label "f6c3 merge feature/auth",
        \\    merge'   :arrow [/dashed/>],
        \\    bump     :label "0a7d bump to 1.0",
        \\    hotfix   :label "1b8e hotfix",
        \\    spike    :label "2c9f try cache"
        \\}
        \\
        \\Repo :prove {
        \\    :kind [category],
        \\    :axiom (fix merge == login session merge'),  // both paths from the fork reach the same state
        \\    :lemma.[clean] (#Merged :pushout)            // fAB checks the merge is clean: the least common state
        \\}
    , .sheet =
        \\zone Repo: stroke [#8250df] mark, caption "unsupported" mark
        \\  node n0: shape [point] program
        \\  node n1: shape [point] program
        \\  node n2: shape [point] program
        \\  node n3: shape [point] program
        \\  node n4: shape [point] program
        \\  node n5: label "feature/auth" program, fill [#888888] program, shape [round] program
        \\  node n6: shape [point] program
        \\  node n7: label "v1.0" program, fill [#888888] program, shape [round] program
        \\  node n8: label "main" program, fill [#888888] program, shape [round] program
        \\  node n9: label "spike/cache" program, fill [#888888] program, shape [round] program
        \\  edge init: label "a1f3 init" program
        \\  edge readme: label "b27c add readme" program
        \\  edge fix: label "c90e fix typo" program
        \\  edge login: label "d4a1 login form" program
        \\  edge session: label "e5b2 sessions" program
        \\  edge merge: label "f6c3 merge feature/auth" program
        \\  edge merge': arrow [/dashed/>] program
        \\  edge bump: label "0a7d bump to 1.0" program
        \\  edge hotfix: label "1b8e hotfix" program
        \\  edge spike: label "2c9f try cache" program
        \\
    });
}

test "Examples: a git history, branch by branch" {
    try check(.{ .step = 9, .rule = 52, .source =
        \\Master     :: */init commit1 commit2 commit3 commit4 commit5
        \\FeatureOne :: Master.(commit2+)/commit1 commit2 commit3 commit4
        \\FeatureTwo :: Master.(commit2+)/commit1 commit2 merge/Master.(commit3+)
        \\
        \\Repo :: Master, FeatureOne, FeatureTwo
        \\
        \\Repo :style {
        \\    &node :shape [point]
        \\}
    , .sheet =
        \\zone Master
        \\  node n0: shape [point] program
        \\  node n1: shape [point] program
        \\  node n2: shape [point] program
        \\  node n3: shape [point] program
        \\  node n4: shape [point] program
        \\  node n5: shape [point] program
        \\  node n6: shape [point] program
        \\zone FeatureOne
        \\  node n7: shape [point] program
        \\  node n8: shape [point] program
        \\  node n9: shape [point] program
        \\  node n10: shape [point] program
        \\zone FeatureTwo
        \\  node n11: shape [point] program
        \\  node n12: shape [point] program
        \\zone Repo
        \\  node n13: shape [point] program
        \\  node n14: shape [point] program
        \\  node n15: shape [point] program
        \\
    });
}
