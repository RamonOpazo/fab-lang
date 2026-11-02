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

test "a reserved or bad head declares no zone" {
    var a = try analyse("review :: a b\n[red] :: f");
    defer a.deinit();
    try testing.expectEqual(@as(usize, 0), a.result.ir.zones.len);
}

// ---------------------------------------------------------------------------
// Statements with syntax errors

test "a statement with a syntax error is skipped, and the rest analysed" {
    try expectTags("G :: f(g :label \"x\")\nH :: (h :label \"y\")", &.{.entry_in_declaration});
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

test "a term with an error is not looked into" {
    // `f?` is also a kind on a reference; beside a space, that is all it is.
    try expectTags("G :: f? (g, h), (*) f", &.{ .pinched_edge_beside_space, .node_beside_space });
}
