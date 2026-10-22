//! Tests for best-effort analysis: broken programs still produce an IR.
//!
//! Each test gives a broken program, the errors it should report, and the IR
//! it should produce, issues included. The IR dump shows holes as nodes of
//! kind `hole`, and issues as `issue e<error> <subject>` lines at the end.

const std = @import("std");
const testing = std.testing;
const Parser = @import("../parse/Parser.zig");
const Analyser = @import("Analyser.zig");

const Tag = Analyser.Error.Tag;

fn expectRecovery(source: [:0]const u8, errors: []const Tag, expected: []const u8) !void {
    const gpa = testing.allocator;
    var cst = try Parser.parse(gpa, source);
    defer cst.deinit(gpa);
    var result = try Analyser.analyse(gpa, &cst);
    defer result.deinit(gpa);

    var tags: std.ArrayList(Tag) = .empty;
    defer tags.deinit(gpa);
    for (result.errors) |e| try tags.append(gpa, e.tag);
    try testing.expectEqualSlices(Tag, errors, tags.items);

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try result.ir.dump(&out.writer);
    try testing.expectEqualStrings(expected, out.written());
}

test "a failed element becomes a hole, and the path stays connected" {
    try expectRecovery("G :: f g/+k h", &.{.undeclared_edge},
        \\zone G
        \\  node n0 canon +f
        \\  node n1 hole canon f+
        \\  node n2 canon h+
        \\  edge f n0 -> n1
        \\  edge h n1 -> n2
        \\issue e0 node n1
        \\
    );
}

test "a cascade is silent, and its hole points back to the cause" {
    // g is rolled back with its element, so the later +g reports nothing.
    try expectRecovery("G :: f (g/+k, h), +g/x", &.{.undeclared_edge},
        \\zone G
        \\  node n0 canon +f
        \\  node n1 hole canon f+
        \\  node n2 canon h+
        \\  node n3 hole
        \\  edge f n0 -> n1
        \\  edge h n1 -> n2
        \\issue e0 node n1
        \\issue e0 node n3
        \\
    );
}

test "a hole absorbs markers glued to it" {
    try expectRecovery("G :: (f +k)? g", &.{.undeclared_edge},
        \\zone G
        \\  node n0 canon +f
        \\  node n1 hole canon f+
        \\  node n2 canon g+
        \\  edge f n0 -> n1
        \\  edge g n1 -> n2
        \\issue e0 node n1
        \\
    );
}

test "undefined zones become holes at both ends" {
    try expectRecovery("Db :: Doc owner User", &.{ .zone_not_defined, .zone_not_defined },
        \\zone Db
        \\  node n0 hole
        \\  node n1 hole canon owner+
        \\  edge owner n0 -> n1
        \\issue e0 node n0
        \\issue e1 node n1
        \\
    );
}

test "an edge declared twice keeps the shape that was written" {
    try expectRecovery("G :: f g f", &.{.edge_declared_twice},
        \\zone G
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  node n2 canon g+
        \\  node n3 canon f+
        \\  edge f n0 -> n1
        \\  edge g n1 -> n2
        \\  edge f n2 -> n3
        \\issue e0 edge f
        \\
    );
}

test "a zone defined twice is drawn, and references go to the first" {
    try expectRecovery("G :: f\nG :: g\nH :: k/G.+f", &.{.zone_defined_twice},
        \\zone G
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\zone G
        \\  node n2 canon +g
        \\  node n3 canon g+
        \\  edge g n2 -> n3
        \\zone H
        \\  node n4 canon +k
        \\  edge k n4 -> n0
        \\issue e0 zone G
        \\
    );
}

test "local fixes: the first kind and the first name are kept" {
    try expectRecovery("G :: f?! g", &.{.conflicting_kinds},
        \\zone G
        \\  node n0 canon +f
        \\  node n1 choice canon f+
        \\  node n2 canon g+
        \\  edge f n0 -> n1
        \\  edge g n1 -> n2
        \\issue e0 node n1
        \\
    );
    try expectRecovery("G :: #A #B f", &.{.node_named_twice},
        \\zone G
        \\  node n0 #A
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\issue e0 node n0
        \\
    );
}

test "local fixes: a second @ is the first one" {
    try expectRecovery("U :: @ f @", &.{.two_own_nodes},
        \\zone U own n0
        \\  node n0
        \\  edge f n0 -> n0
        \\issue e0 node n0
        \\
    );
}

test "local fixes: juxtaposition that glues nothing keeps the pieces apart" {
    try expectRecovery("G :: f* g", &.{.juxtaposition_glues_nothing},
        \\zone G
        \\  node n0 canon +f
        \\  node n1 null_node canon f+
        \\  node n2 canon +g
        \\  node n3 canon g+
        \\  edge f n0 -> n1
        \\  edge g n2 -> n3
        \\
    );
}

test "cells: a block that fails is dropped, a non-parallel cell is kept and marked" {
    try expectRecovery("G :: f, +f/g/f+, [α β]", &.{ .inner_node_not_an_edge, .inner_node_not_an_edge },
        \\zone G
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\  edge g n0 -> n1
        \\
    );
    try expectRecovery("Sq :: f h, +f/g k/h+, [f α h]", &.{.cells_not_parallel},
        \\zone Sq
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  node n2 canon h+
        \\  node n3 canon g+
        \\  edge f n0 -> n1
        \\  edge h n1 -> n2
        \\  edge g n0 -> n3
        \\  edge k n3 -> n2
        \\  cell α f => h
        \\issue e0 cell α
        \\
    );
}

test "statements with syntax errors are skipped, and the rest is analysed" {
    // The parser reports `/` and keeps `H :: g`; J is unaffected.
    try expectRecovery("G :: f\nH :: g /k\nJ :: m", &.{},
        \\zone G
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\zone H
        \\  node n2 canon +g
        \\  node n3 canon g+
        \\  edge g n2 -> n3
        \\zone J
        \\  node n4 canon +m
        \\  node n5 canon m+
        \\  edge m n4 -> n5
        \\
    );
}
