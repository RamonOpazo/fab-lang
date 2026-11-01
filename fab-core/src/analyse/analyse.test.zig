//! The analyser's tests: source in, IR or errors out.
//!
//! They run the parser and the analyser together, so they check the whole
//! relations layer as a user sees it. The union-find has its own unit tests.

const std = @import("std");
const testing = std.testing;
const Parser = @import("../parse/Parser.zig");
const Analyser = @import("Analyser.zig");

fn expectIr(source: [:0]const u8, expected: []const u8) !void {
    var cst = try Parser.parse(testing.allocator, source);
    defer cst.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 0), cst.errors.len);

    var result = try Analyser.analyse(testing.allocator, &cst);
    defer result.deinit(testing.allocator);
    if (result.errors.len > 0) {
        for (result.errors) |e| std.debug.print("unexpected {s} at '{s}'\n", .{ @tagName(e.tag), cst.tokenText(e.token) });
        return error.TestUnexpectedResult;
    }
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try result.ir.dump(&out.writer);
    try testing.expectEqualStrings(expected, out.written());
}

/// Checks the first error's tag and the text of the token it points at.
fn expectError(source: [:0]const u8, tag: Analyser.Error.Tag, at: []const u8) !void {
    var cst = try Parser.parse(testing.allocator, source);
    defer cst.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 0), cst.errors.len);

    var result = try Analyser.analyse(testing.allocator, &cst);
    defer result.deinit(testing.allocator);
    if (result.errors.len == 0) return error.TestExpectedError;
    testing.expectEqual(tag, result.errors[0].tag) catch |err| {
        std.debug.print("source: {s}\n", .{source});
        return err;
    };
    try testing.expectEqualStrings(at, cst.tokenText(result.errors[0].token));
}

test "a chain" {
    try expectIr("G :: f g h",
        \\zone G
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  node n2 canon g+
        \\  node n3 canon h+
        \\  edge f n0 -> n1
        \\  edge g n1 -> n2
        \\  edge h n2 -> n3
        \\
    );
}

test "fork and join" {
    try expectIr("Fork :: f (g, h)\nJoin :: (f, g) h",
        \\zone Fork
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  node n2 canon g+
        \\  node n3 canon h+
        \\  edge f n0 -> n1
        \\  edge g n1 -> n2
        \\  edge h n1 -> n3
        \\zone Join
        \\  node n4 canon +f
        \\  node n5 canon f+
        \\  node n6 canon +g
        \\  node n7 canon h+
        \\  edge f n4 -> n5
        \\  edge g n6 -> n5
        \\  edge h n5 -> n7
        \\
    );
}

test "back edges and endomorphisms" {
    try expectIr("A :: f/e\nB :: (f g)/h\nC :: f/f g h/h",
        \\zone A
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\  edge e n1 -> n0
        \\zone B
        \\  node n2 canon +f
        \\  node n3 canon f+
        \\  node n4 canon g+
        \\  edge f n2 -> n3
        \\  edge g n3 -> n4
        \\  edge h n4 -> n2
        \\zone C
        \\  node n5 canon +f
        \\  node n6 canon g+
        \\  edge f n5 -> n5
        \\  edge g n5 -> n6
        \\  edge h n6 -> n6
        \\
    );
}

test "the commutative square: canonical nodes as in the spec" {
    try expectIr("Sq :: f h, +f/g k/h+",
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
    );
}

test "node kinds" {
    try expectIr("If :: f? (fg g, fh h)? k\nWhile :: f? (b/f+, e)\nP :: *f g h*",
        \\zone If
        \\  node n0 canon +f
        \\  node n1 choice canon f+
        \\  node n2 canon fg+
        \\  node n3 choice canon g+
        \\  node n4 canon fh+
        \\  node n5 canon k+
        \\  edge f n0 -> n1
        \\  edge fg n1 -> n2
        \\  edge g n2 -> n3
        \\  edge fh n1 -> n4
        \\  edge h n4 -> n3
        \\  edge k n3 -> n5
        \\zone While
        \\  node n6 canon +f
        \\  node n7 choice canon f+
        \\  node n8 canon e+
        \\  edge f n6 -> n7
        \\  edge b n7 -> n7
        \\  edge e n7 -> n8
        \\zone P
        \\  node n9 null_node canon +f
        \\  node n10 canon f+
        \\  node n11 canon g+
        \\  node n12 null_node canon h+
        \\  edge f n9 -> n10
        \\  edge g n10 -> n11
        \\  edge h n11 -> n12
        \\
    );
}

test "undirected edges" {
    try expectIr("G :: #A f/ #B, #B g/ #C",
        \\zone G
        \\  node n0 #A
        \\  node n1 #B
        \\  node n2 #C
        \\  edge f n0 -- n1
        \\  edge g n1 -- n2
        \\
    );
}

test "zones as nodes, own nodes and shared types" {
    try expectIr(
        \\T :: #UUID7, #String
        \\User :: @ (id T.#UUID7, name T.#String)
        \\Doc :: @ (id T.#UUID7)
        \\Db :: Doc owner User
    ,
        \\zone T
        \\  node n0 #UUID7
        \\  node n1 #String
        \\zone User own n2
        \\  node n2
        \\  edge id n2 -> n0
        \\  edge name n2 -> n1
        \\zone Doc own n3
        \\  node n3
        \\  edge id n3 -> n0
        \\zone Db
        \\  edge owner n3 -> n2
        \\
    );
}

test "a cross-zone reference reaches into another zone's node" {
    try expectIr("A :: f g\nB :: h/A.+f",
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
    );
}

test "edge-to-edge relations" {
    try expectIr("Nat :: f, +f/g/f+, [f α g]\nIso :: f, +f/g/f+, [f α/β g]",
        \\zone Nat
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\  edge g n0 -> n1
        \\  cell α f => g
        \\zone Iso
        \\  node n2 canon +f
        \\  node n3 canon f+
        \\  edge f n2 -> n3
        \\  edge g n2 -> n3
        \\  cell α f => g
        \\  cell β g => f
        \\
    );
}

test "the spec's flowchart" {
    try expectIr(
        \\Order :: *receive #Received validate #Valid? (
        \\    yes #Accepted! (
        \\        charge #Charged? (paid, declined #Waiting retry/charge+)
        \\      , reserve #InStock? (reserved, short #Backorder restock/reserve+)
        \\    )! #Ready ship #Shipped close*
        \\  , no #Rejected notify*
        \\)
    ,
        \\zone Order
        \\  node n0 null_node canon +receive
        \\  node n1 #Received
        \\  node n2 choice #Valid
        \\  node n3 parallel #Accepted
        \\  node n4 choice #Charged
        \\  node n5 parallel #Ready
        \\  node n6 #Waiting
        \\  node n7 choice #InStock
        \\  node n8 #Backorder
        \\  node n9 #Shipped
        \\  node n10 null_node canon close+
        \\  node n11 #Rejected
        \\  node n12 null_node canon notify+
        \\  edge receive n0 -> n1
        \\  edge validate n1 -> n2
        \\  edge yes n2 -> n3
        \\  edge charge n3 -> n4
        \\  edge paid n4 -> n5
        \\  edge declined n4 -> n6
        \\  edge retry n6 -> n4
        \\  edge reserve n3 -> n7
        \\  edge reserved n7 -> n5
        \\  edge short n7 -> n8
        \\  edge restock n8 -> n7
        \\  edge ship n5 -> n9
        \\  edge close n9 -> n10
        \\  edge no n2 -> n11
        \\  edge notify n11 -> n12
        \\
    );
}

test "layers are placed but not yet analysed" {
    try expectIr("G :: f\nG :format { f :label \"x\" }\nG :proof { f == f }",
        \\zone G
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\
    );
}

test "errors: zones and layers" {
    try expectError("G :: f\nG :: g", .zone_defined_twice, "G");
    try expectError("Db :: Doc owner User", .zone_not_defined, "Doc");
    try expectError("G :: f G", .zone_not_defined, "G");
    try expectError("T :: #A\nDb :: T owns T", .zone_has_no_own_node, "T");
    try expectError("H :format { f :label \"x\" }", .layer_for_unknown_zone, "H");
    try expectError("G :: f\nG :style { f :label \"x\" }", .unknown_layer, ":style");
    try expectError("G :: f\nG :format { f :label \"x\" }\nG :format { f :label \"y\" }", .layer_defined_twice, ":format");
}

test "errors: edges and references (the spec's table)" {
    try expectError("G :: f g f", .edge_declared_twice, "f");
    try expectError("G :: (f g)/f", .self_reference_outside_endomorphism, "f");
    try expectError("G :: f/+f", .redundant_self_attachment, "/");
    try expectError("G :: f/f+", .vacuous_self_attachment, "/");
    try expectError("G :: f g, +g/+f", .edge_from_references_only, "/");
    try expectError("G :: +f/g f", .undeclared_edge, "f");
    try expectError("G :: f, k +f", .bare_reference, "+");
    try expectError("G :: f, +(f g)/h", .not_an_edge, "(");
    try expectError("A :: f\nB :: h/A.+k", .undeclared_edge, "k");
    try expectError("T :: #A\nU :: f T.#B", .undeclared_name, "#B");
}

test "errors: node kinds and sealing (the spec's table)" {
    try expectError("G :: f, k?/+f", .kind_declared_twice, "?");
    try expectError("G :: f, +f?", .kind_declared_twice, "?");
    try expectError("G :: f?*", .conflicting_kinds, "*");
    try expectError("G :: f?!", .conflicting_kinds, "!");
    try expectError("G :: f* g", .juxtaposition_glues_nothing, "g");
    try expectError("G :: f, g/+f h", .juxtaposition_glues_nothing, "h");
    try expectError("G :: f*, k/f+", .reference_to_sealed_end, "+");
    try expectError("G :: f/e*", .sealing_shared_end, "*");
    try expectError("G :: *f*", .both_ends_sealed, "*");
}

test "errors: names and own nodes" {
    try expectError("G :: #A #B", .node_named_twice, "#B");
    try expectError("G :: @ f @", .two_own_nodes, "@");
    try expectError("G :: .iso f", .class_in_relations, ".");
}

test "errors: edge-to-edge relations" {
    try expectError("Sq :: f h, +f/g k/h+, [f α h]", .cells_not_parallel, "α");
    try expectError("G :: f, +f/g/f+, [α β]", .inner_node_not_an_edge, "α");
    try expectError("G :: f, +f/g/f+, [f g]", .two_edges_in_one_node, "g");
}
