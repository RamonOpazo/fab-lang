//! Tests of the analyser that the conformance corpus doesn't see: the IR's
//! zones, related tokens, and the unsupported diagnostics the corpus leaves
//! out.

const std = @import("std");
const testing = std.testing;
const Parser = @import("../parse/Parser.zig");
const Cst = @import("../parse/Cst.zig");
const Analyser = @import("Analyser.zig");

const Analysed = struct {
    cst: Cst,
    result: Analyser.Result,

    fn deinit(a: *Analysed) void {
        a.result.deinit(testing.allocator);
        a.cst.deinit(testing.allocator);
    }

    fn tags(a: Analysed) []const Analyser.Error.Tag {
        const S = struct {
            var buf: [32]Analyser.Error.Tag = undefined;
        };
        for (a.result.errors, 0..) |err, i| S.buf[i] = err.tag;
        return S.buf[0..a.result.errors.len];
    }
};

fn analyse(source: [:0]const u8) !Analysed {
    var cst = try Parser.parse(testing.allocator, source);
    errdefer cst.deinit(testing.allocator);
    return .{ .cst = cst, .result = try Analyser.analyse(testing.allocator, &cst) };
}

fn expectTags(source: [:0]const u8, want: []const Analyser.Error.Tag) !void {
    var a = try analyse(source);
    defer a.deinit();
    try testing.expectEqualSlices(Analyser.Error.Tag, want, a.tags());
}

// ---------------------------------------------------------------------------
// Zones

test "every declared diagram becomes a zone, in order" {
    var a = try analyse("A :: f\nB :: g\nA :style := f :label \"x\"");
    defer a.deinit();
    const ir = a.result.ir;
    try testing.expectEqual(@as(usize, 2), ir.zones.len);
    try testing.expectEqualStrings("A", ir.string(ir.zones.items(.name)[0]));
    try testing.expectEqualStrings("B", ir.string(ir.zones.items(.name)[1]));
}

test "a diagram declared twice is drawn twice, and points back to the first" {
    var a = try analyse("G :: f\nG :: g");
    defer a.deinit();
    try testing.expectEqual(@as(usize, 2), a.result.ir.zones.len);
    const err = a.result.errors[0];
    try testing.expectEqual(Analyser.Error.Tag.zone_declared_twice, err.tag);
    try testing.expectEqualStrings("G", a.cst.tokenText(err.token));
    try testing.expectEqual(@as(?Cst.TokenIndex, 0), err.related);
}

test "a reserved or bad head declares no diagram: it draws a placeholder" {
    try expectGraph("review :: a b\n[red] :: f",
        \\placeholder review
        \\placeholder [red]
        \\issue e0 zone review
        \\issue e1 zone [red]
        \\
    );
}

// ---------------------------------------------------------------------------
// Statements with syntax errors

// A statement with a syntax error is not read (spec/statements.md §15.4).

test "a statement with a syntax error is skipped, and the rest analysed" {
    try expectTags("G :: f(g :label \"x\")\nH :: (h :label \"y\")", &.{.entry_in_declaration});
}

test "a syntax error in the tail the parser skipped belongs to the statement it cut short" {
    // Read, `G :: f/` would draw f undirected.
    try expectGraph("G :: f/ /g\nH :: h",
        \\placeholder G
        \\zone H
        \\  node n0 canon +h
        \\  node n1 canon h+
        \\  edge h n0 -> n1
        \\issue s0 zone G
        \\
    );
}

test "a statement broken inside braces draws its placeholder too, for now" {
    try expectGraph("G :: { f /g, h }",
        \\placeholder G
        \\issue s0 zone G
        \\
    );
}

test "a broken diagram is declared: what refers into it is a hole, silently" {
    var a = try analyse("G :: f(g)\nH :: G.+f/x, G/y, G.#A/z");
    defer a.deinit();
    try testing.expectEqual(@as(usize, 0), a.result.errors.len);
    try testing.expectEqual(@as(usize, 1), a.result.ir.issues.len);
}

test "a broken statement about a declared diagram marks it" {
    try expectGraph("G :: f\nG :: f(g)",
        \\zone G
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\issue s0 zone G
        \\
    );
}

test "a broken statement naming no diagram draws a placeholder named by its first token" {
    try expectGraph(":: f\n[red] :: f g ]",
        \\placeholder ::
        \\placeholder [red]
        \\issue s0 zone ::
        \\issue s1 zone [red]
        \\
    );
}

// ---------------------------------------------------------------------------
// Unsupported

test "levels above the first are reported once per body, and skipped" {
    // `&node` in the second level would be an error if it were analysed.
    try expectTags("G :: +(f, g)+ | f/α/g | &node", &.{.unsupported_levels});
}

test "levels inside braces are levels of the body" {
    try expectTags("G :: { +(f, g)+ | f/α/g }", &.{.unsupported_levels});
}

test "every definition is reported once as unsupported, after its errors" {
    try expectTags("G :style := yes, paid :label \"yes\"", &.{ .bare_term_in_definition, .unsupported_definition });
}

test "unsupported and warnings have their own severity" {
    const T = Analyser.Error.Tag;
    try testing.expectEqual(.unsupported, T.unsupported_levels.severity());
    try testing.expectEqual(.warning, T.chain_broken_across_lines.severity());
    try testing.expectEqual(.@"error", T.reserved_node_or_edge_declaration.severity());
}

// ---------------------------------------------------------------------------
// Operators

test "a mixed run is reported once, at the first different operator" {
    var a = try analyse("G :prove := a == b ~= c == d ~= e");
    defer a.deinit();
    try testing.expectEqualSlices(Analyser.Error.Tag, &.{ .mixed_operators, .unsupported_definition }, a.tags());
    try testing.expectEqualStrings("~=", a.cst.tokenText(a.result.errors[0].token));
}

test "runs inside groups are checked on their own" {
    try expectTags("G :prove := (a == b ~= c) == d", &.{ .mixed_operators, .unsupported_definition });
}

// ---------------------------------------------------------------------------
// Sorts

test "the old spelling of a decision is a kind on the left" {
    try expectTags("G :: f ?(a, b)", &.{.kind_on_the_left});
}

test "each step of a chain is judged on its own" {
    try expectTags("G :: #A f #B", &.{ .node_beside_space, .node_beside_space });
}

test "a slash between nodes is reported at the slash, and nothing else in the chain" {
    // `*` would also be a null node in a chain with no edge.
    var a = try analyse("G :: f/#A/#B/*");
    defer a.deinit();
    try testing.expectEqualSlices(Analyser.Error.Tag, &.{.slash_between_nodes}, a.tags());
    try testing.expectEqual(@as(Cst.TokenIndex, 5), a.result.errors[0].token);
    try testing.expectEqualStrings("/", a.cst.tokenText(a.result.errors[0].token));
}

// ---------------------------------------------------------------------------
// Interfaces

test "a failed term is a hole, and the space beside it reports nothing" {
    // Read as a cycle, `f/?/g` would expose nothing on its right.
    try expectTags("G :: f/?/g h", &.{.kind_on_the_left});
}

test "a failed branch makes its group's side a hole" {
    // Counted, the group would hold two ends on the right.
    try expectTags("G :: (f, (a, b)/?) h", &.{.kind_after_group});
}

test "ends that don't match are reported at the step after the space" {
    var a = try analyse("G :: f (g, h)");
    defer a.deinit();
    try testing.expectEqualSlices(Analyser.Error.Tag, &.{.ends_dont_match}, a.tags());
    try testing.expectEqualStrings("(", a.cst.tokenText(a.result.errors[0].token));
}

// ---------------------------------------------------------------------------
// Elaboration

fn expectGraph(source: [:0]const u8, want: []const u8) !void {
    var a = try analyse(source);
    defer a.deinit();
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try a.result.ir.dump(&out.writer);
    try testing.expectEqualStrings(want, out.written());
}

test "a join that doesn't match is a hole holding both sides, and the path goes on" {
    try expectGraph("G :: f (g, h) k",
        \\zone G
        \\  node n0 canon +f
        \\  node n1 hole canon f+
        \\  node n2 hole canon g+
        \\  node n3 canon k+
        \\  edge f n0 -> n1
        \\  edge g n1 -> n2
        \\  edge h n1 -> n2
        \\  edge k n2 -> n3
        \\issue e0 node n1
        \\issue e1 node n2
        \\
    );
}

test "a failed link is a hole, and the edges beside it stay declared" {
    try expectGraph("G :: (a, b)/?, +a/x",
        \\zone G
        \\  node n0 canon +a
        \\  node n1 hole canon a+
        \\  node n2 canon +b
        \\  node n3 canon x+
        \\  edge a n0 -> n1
        \\  edge b n2 -> n1
        \\  edge x n0 -> n3
        \\issue e0 node n1
        \\
    );
}

test "an edge declared twice points back to its first declaration" {
    var a = try analyse("G :: f g f");
    defer a.deinit();
    try testing.expectEqualSlices(Analyser.Error.Tag, &.{.edge_declared_twice}, a.tags());
    try testing.expectEqual(@as(?Cst.TokenIndex, 2), a.result.errors[0].related);
}

test "a name declared in a failed term is quiet when declared again" {
    // `f?` fails, so f is bound to its hole; the bare f after it says nothing.
    try expectTags("G :: f?, f", &.{.kind_on_reference});
}

test "a reference is reported at the edge's name" {
    var a = try analyse("G :: +k/g");
    defer a.deinit();
    try testing.expectEqualSlices(Analyser.Error.Tag, &.{.reference_not_declared}, a.tags());
    try testing.expectEqualStrings("k", a.cst.tokenText(a.result.errors[0].token));
}

test "two names meet where the space is, and the first name wins" {
    var a = try analyse("G :: a/#A #B/b");
    defer a.deinit();
    try testing.expectEqualSlices(Analyser.Error.Tag, &.{.two_names_for_one_node}, a.tags());
    const err = a.result.errors[0];
    try testing.expectEqualStrings("#B", a.cst.tokenText(err.token));
    try testing.expectEqualStrings("#A", a.cst.tokenText(err.related.?));
    const ir = a.result.ir;
    try testing.expectEqual(@as(usize, 3), ir.nodes.len);
    try testing.expectEqualStrings("#A", ir.string(ir.nodes.items(.name)[1].?));
}

test "kinds that disagree point back to the kind that stays" {
    var a = try analyse("G :: (a/?, b/!)+");
    defer a.deinit();
    try testing.expectEqualSlices(Analyser.Error.Tag, &.{.kinds_disagree}, a.tags());
    try testing.expectEqualStrings("+", a.cst.tokenText(a.result.errors[0].token));
    try testing.expectEqualStrings("?", a.cst.tokenText(a.result.errors[0].related.?));
}

test "a reserved head is checked, but not drawn" {
    var a = try analyse("review :: a b");
    defer a.deinit();
    try testing.expectEqual(@as(usize, 0), a.result.ir.edges.len);
}

test "a term with an error is not looked into" {
    // `f?` is also a kind on a reference; beside a space, that is all it is.
    try expectTags("G :: f? (g, h), (*) f", &.{ .pinched_edge_beside_space, .node_beside_space });
}
