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
    return .{ .cst = cst, .result = try Analyser.analyse(testing.allocator, &cst, null) };
}

fn expectTags(source: [:0]const u8, want: []const Analyser.Error.Tag) !void {
    var a = try analyse(source);
    defer a.deinit();
    try testing.expectEqualSlices(Analyser.Error.Tag, want, a.tags());
}

// ---------------------------------------------------------------------------
// Zones

test "every declared diagram becomes a zone, in order" {
    var a = try analyse("A :: f\nB :: g\nA :style { f :label \"x\" }");
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
    try expectTags("G :: f(g :label \"x\")\nH :: (h :label \"y\")", &.{.entry_in_zone_declaration});
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

/// What the layer tests describe with, since there is no prelude here.
const styles =
    \\:Color :: [red]
    \\:Style :: { (&node, &edge, &zone) :label :: :Text, (&node, &zone) :fill :: :Color, &zone :caption :: :Text }
    \\&zone :style :: :Style
    \\
;

test "every description is reported once as unsupported, after its errors" {
    try expectTags(styles ++ "G :: yes, paid\nG :style { yes, paid :label \"yes\" }", &.{.bare_term_in_record});
    try expectTags(styles ++ "G :: f\nG :style { f :label \"x\" }\nG :label \"y\"", &.{});
}

test "a layer's contexts resolve to elements, kept as bindings" {
    var a = try analyse(styles ++ "G :: f g\nG :style { f :label \"x\", f+ :label \"y\", &edge :label \"z\" }\nG :label \"G\"");
    defer a.deinit();
    const b = a.result.bindings;
    try testing.expectEqual(@as(usize, 4), b.len);
    try testing.expectEqual(@as(u32, 0), @backingInt(b[0].subject.edge));
    // f+ is the node between f and g: the second one made.
    try testing.expectEqual(@as(u32, 1), @backingInt(b[1].subject.node));
    try testing.expect(b[2].subject.class.classes.contains(.edge));
    try testing.expectEqual(@as(?@TypeOf(b[2].subject.class.zone.?), @fromBackingInt(@as(u32, 0))), b[2].subject.class.zone);
    try testing.expectEqual(@as(u32, 0), @backingInt(b[3].subject.zone));
}

// ---------------------------------------------------------------------------
// References (plan step L2a)

/// One line per reference: its text at its offset, its sort, and where its
/// definition is, by offset (`@4`), `prelude`, or `built-in`.
fn dumpReferences(source: [:0]const u8) ![]u8 {
    var a = try analyse(source);
    defer a.deinit();
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    errdefer out.deinit();
    for (a.result.references) |r| {
        try out.writer.print("{s}@{d} {s}", .{ source[r.span.start..r.span.end], r.span.start, @tagName(r.sort) });
        if (r.definition) |d| {
            if (d.prelude) try out.writer.writeAll(" prelude") else try out.writer.print(" @{d}", .{@intFromPtr(a.cst.tokenText(d.token).ptr) - @intFromPtr(source.ptr)});
        } else try out.writer.writeAll(" built-in");
        if (r.subject) |subject| switch (subject) {
            inline else => |i, tag| try out.writer.print(" ={s}{d}", .{ @tagName(tag), @backingInt(i) }),
        };
        try out.writer.writeByte('\n');
    }
    return out.toOwnedSlice();
}

fn expectReferences(source: [:0]const u8, want: []const u8) !void {
    const got = try dumpReferences(source);
    defer testing.allocator.free(got);
    try testing.expectEqualStrings(want, got);
}

test "references: every name in a declaration, and what it names" {
    // A's names, then B's uses of them: an end (`A.f+`), a named node
    // (`A.#X`), the diagram itself (`A`), its own edge (`+h`).
    try expectReferences("A :: #Y/f/#X g\nB :: A.f+/h, A.#X/k, A/m, +h/n",
        \\A@0 zone @0 =zone0
        \\#Y@5 node @5 =node0
        \\f@8 edge @8 =edge0
        \\#X@10 node @10 =node1
        \\g@13 edge @13 =edge1
        \\B@15 zone @15 =zone1
        \\A@20 zone @0 =zone0
        \\f@22 edge @8 =edge0
        \\h@25 edge @25 =edge2
        \\A@28 zone @0 =zone0
        \\#X@30 node @10 =node1
        \\k@33 edge @33 =edge3
        \\A@36 zone @0 =zone0
        \\m@38 edge @38 =edge4
        \\h@42 edge @25 =edge2
        \\n@44 edge @44 =edge5
        \\
    );
}

test "references: sides above level 1, and a diagram declared twice" {
    // The second G is drawn apart: its name points to the first, its `f`
    // is its own.
    try expectReferences("G :: f/g | f/α/g\nG :: f",
        \\G@0 zone @0 =zone0
        \\f@5 edge @5 =edge0
        \\g@7 edge @7 =edge1
        \\f@11 edge @5 =edge0
        \\α@13 cell @13 =cell0
        \\g@16 edge @7 =edge1
        \\G@18 zone @0 =zone0
        \\f@23 edge @23 =edge2
        \\
    );
}

test "references: types, labels, values and descriptors, once each" {
    // A label's use is its name inside the bracket (`red`); its definition
    // is the bracket that declares it. Built-in types have no site.
    try expectReferences(styles ++ "[warn] := [red]\nG :: f\nG :style { f :fill [warn], +f :fill [red] }\nG.f :label \"x\"",
        \\:Color@0 type built-in
        \\red@11 label @10
        \\:Style@16 type @16
        \\:label@50 descriptor @50
        \\:Text@60 type built-in
        \\:fill@82 descriptor @82
        \\:Color@91 type built-in
        \\:caption@105 descriptor @105
        \\:Text@117 type built-in
        \\:style@131 descriptor @131
        \\:Style@141 type @16
        \\warn@149 value @148
        \\red@159 label @10
        \\G@164 zone @164 =zone0
        \\f@169 edge @169 =edge0
        \\G@171 zone @164 =zone0
        \\:style@173 descriptor @131
        \\f@182 edge @169 =edge0
        \\:fill@184 descriptor @82
        \\warn@191 value @148
        \\f@199 edge @169 =edge0
        \\:fill@201 descriptor @82
        \\red@208 label @10
        \\G@215 zone @164 =zone0
        \\f@217 edge @169 =edge0
        \\:label@219 descriptor @50
        \\
    );
}

test "a description with an operator, or with no context, is no layer" {
    try expectTags("G :style := { f :label \"x\" }", &.{.description_with_operator});
    try expectTags(":fill [red]", &.{.context_missing});
}

test "the owner is described first, and warned about once per descriptor" {
    try expectTags(styles ++ "G :: f\nG :style { f :label \"x\", :fill [red], :caption \"y\" }", &.{ .owner_after_part, .owner_after_part });
    // Each block is its own: a part's block starts afresh.
    try expectTags(styles ++ "G :: f, g\nG :style { f { :label \"x\" }, g { :label \"y\" } }", &.{});
}

test "a theme's tokens are namings; a bundle holds none" {
    // No prelude here: the labels are declared first.
    try expectTags(":Color :: [ink]\n:Shape :: [circle]\n[x] := { [ink] := [#fff], [ink] := [circle] }", &.{.key_of_wrong_type});
    try expectTags(":t := { [ink] := [#fff] }", &.{.subject_in_bundle});
    try expectTags("[x] := { [ink] :: :Color }", &.{.declaration_in_record});
}

test "unsupported and warnings have their own severity" {
    const T = Analyser.Error.Tag;
    try testing.expectEqual(.unsupported, T.unsupported_layer.severity());
    try testing.expectEqual(.unsupported, T.unsupported_case.severity());
    try testing.expectEqual(.warning, T.chain_broken_across_lines.severity());
    try testing.expectEqual(.@"error", T.reserved_node_or_edge_declaration.severity());
}

// ---------------------------------------------------------------------------
// Levels

test "levels above the first are drawn as cells, inline or in the body's braces" {
    const mod =
        \\zone G
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\  edge g n0 -> n1
        \\  cell α f => g
        \\  cell β f => g
        \\  cell m α => β level 3
        \\
    ;
    try expectGraph("G :: +(f, g)+ | f/(α, β)/g | α/m/β", mod);
    try expectGraph("G :: {\n  +(f, g)+\n  | f/(α, β)/g\n  | α/m/β\n}", mod);
}

test "a cycle of cells closes on its start" {
    try expectGraph("G :: +(f, g)+ | f/α/g/β",
        \\zone G
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\  edge g n0 -> n1
        \\  cell α f => g
        \\  cell β g => f
        \\
    );
}

test "a space lands on a named side" {
    try expectGraph("G :: +(f, g, h)+ | f/α g/β/h",
        \\zone G
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\  edge g n0 -> n1
        \\  edge h n0 -> n1
        \\  cell α f => g
        \\  cell β g => h
        \\
    );
}

test "levels are checked like the first" {
    try expectTags("G :: +(f, g)+ | f/α/g | &node", &.{.class_in_zone_declaration});
    try expectTags("G :: f, { g | α }", &.{.level_inside_branch});
}

test "above level 1 a name of the level below is a side, and a new one a cell" {
    // At level 2, f and g are sides, so `f/g` is a slash between nodes; α and
    // β are cells, and `α/β` has no side at all.
    try expectTags("G :: +(f, g)+ | f/g, α/β", &.{ .slash_between_nodes, .unnamed_side, .unnamed_side });
    // At level 3, α and β are sides.
    try expectTags("G :: +(f, g)+ | f/(α, β)/g | α/m/β, α/β", &.{.slash_between_nodes});
}

test "each term that is not a cell is reported, and the rest of its item is not looked into" {
    try expectTags("G :: +(f, g)+ | f/α/*, (*, ?)/β, +α", &.{
        .not_a_cell, .not_a_cell, .not_a_cell, .pinch_above_level_one,
    });
}

test "a side of a lower level stands for its identity" {
    // α : f ⇒ 1_A, and m : β ⇛ 1_f, with β : f ⇒ f.
    try expectTags("G :: #A/f/#A | f/α/#A, f/β/f | β/m/f", &.{});
    try expectTags("G :: @/f/@ | f/α/@", &.{});
    // β : 1_A ⇒ 1_A, and m : β ⇛ 1_(1_A).
    try expectGraph("G :: #A/f/#A | f/α/#A, #A/β/#A | β/m/#A",
        \\zone G
        \\  node n0 #A
        \\  edge f n0 -> n0
        \\  cell α f => n0
        \\  cell β n0 => n0
        \\  cell m β => n0 level 3
        \\
    );
    // 1_A starts and ends at A, and f doesn't; α : f ⇒ g is not f ⇒ f.
    try expectTags("G :: #A/f/#B | f/α/#A", &.{.cells_not_parallel});
    try expectTags("G :: +(f, g)+ | f/(α, β)/g | α/m/f", &.{.cells_not_parallel});
    // α : f ⇒ 1_A, but 1_(1_A) goes from 1_A to 1_A.
    try expectTags("G :: #A/f/#A | f/α/#A | α/m/#A", &.{.cells_not_parallel});
}

test "only level 1 makes nodes" {
    var a = try analyse("G :: +(f, g)+ | f/α/#B, #C/β/g");
    defer a.deinit();
    try testing.expectEqualSlices(Analyser.Error.Tag, &.{ .side_not_declared, .side_not_declared }, a.tags());
    try testing.expectEqualStrings("#B", a.cst.tokenText(a.result.errors[0].token));
}

test "a named node only a failed term held is quiet above" {
    try expectTags("G :: (f/#A/g)/, +(h, k)+ | h/α/#A", &.{.undirected_not_one_edge});
}

test "unnamed sides are reported where two open ends meet, and at a cell left open" {
    var a = try analyse("G :: +(f, g)+ | f/α β/g, γ, (δ, ε)/g");
    defer a.deinit();
    try testing.expectEqualSlices(Analyser.Error.Tag, &.{ .unnamed_side, .unnamed_side, .unnamed_side, .unnamed_side }, a.tags());
    const at = [_][]const u8{ "β", "γ", "δ", "ε" };
    for (a.result.errors, at) |err, text| try testing.expectEqualStrings(text, a.cst.tokenText(err.token));
}

test "a cell with an unnamed side is left out, and the cells on it stay quiet" {
    try expectGraph("G :: +(f, g)+ | f/α, f/β/g | α/m/β",
        \\zone G
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\  edge g n0 -> n1
        \\  cell β f => g
        \\issue e0 zone G
        \\
    );
}

test "two names for one side keep both cells, and mark the later" {
    try expectGraph("G :: +(f, g, h, k)+ | f/α/g h/β/k",
        \\zone G
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\  edge g n0 -> n1
        \\  edge h n0 -> n1
        \\  edge k n0 -> n1
        \\  cell α f => g
        \\  cell β h => k
        \\issue e0 cell β
        \\
    );
}

test "a cell between cells that are not parallel is drawn, and marked" {
    try expectGraph("Sq :: +(f h, g k)+ | f/α/h",
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

test "parallel is judged on the final graph: a later diagram can make it so" {
    try expectTags("A :: f, g | f/α/g", &.{.cells_not_parallel});
    try expectTags("A :: f, g | f/α/g\nB :: +(A.+f/x/A.f+, A.+g/y/A.g+)+", &.{});
}

test "a hole says nothing more about parallel" {
    try expectTags("H :: f, g/+k | f/α/g", &.{.reference_not_declared});
}

test "a cell above level 2 is checked on its own sides" {
    try expectTags("G :: +(f, g, h)+ | f/(α, β)/g, f/γ/h | α/m/β, α/n/γ", &.{.cells_not_parallel});
}

test "an undirected side may be read either way" {
    try expectTags("U :: +(f/, g/)+ | f/α/g", &.{});
    try expectTags("U :: #A/f/#B/, #B/g/#A | f/α/g", &.{});
    try expectTags("U :: #A/f/#B, #B/g/#A | f/α/g", &.{.cells_not_parallel});
}

test "a cell is undirected with a trailing slash on a chain of one cell" {
    try expectGraph("G :: +(f, g)+ | f/α/g/, f/β/g",
        \\zone G
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\  edge g n0 -> n1
        \\  cell α f == g
        \\  cell β f => g
        \\
    );
    try expectTags("G :: +(f, g)+ | f/α/", &.{.unnamed_side});
}

test "a cycle of cells is undirected with a trailing slash" {
    try expectGraph("G :: +(f, g)+ | f/α/g/β/",
        \\zone G
        \\  node n0 canon +f
        \\  node n1 canon f+
        \\  edge f n0 -> n1
        \\  edge g n0 -> n1
        \\  cell α f == g
        \\  cell β g == f
        \\
    );
}

test "a cell declared twice keeps the first, and points back to it" {
    var a = try analyse("G :: +(f, g)+ | f/α/g, g/α/f");
    defer a.deinit();
    try testing.expectEqualSlices(Analyser.Error.Tag, &.{.edge_declared_twice}, a.tags());
    try testing.expectEqual(@as(usize, 1), a.result.ir.cells.len);
    try testing.expectEqualStrings("α", a.cst.tokenText(a.result.errors[0].related.?));
}

// ---------------------------------------------------------------------------
// Operators

test "a mixed run is reported once, at the first different operator" {
    var a = try analyse("G :: a\nG :prove { :axiom (a == b ~= c == d ~= e) }");
    defer a.deinit();
    // In source order: the layer's descriptor comes first.
    try testing.expectEqualSlices(Analyser.Error.Tag, &.{ .unsupported_layer, .mixed_operators }, a.tags());
    try testing.expectEqualStrings("~=", a.cst.tokenText(a.result.errors[1].token));
}

test "each diagram's kind is kept, by zone" {
    // No prelude here: the kinds are declared first.
    var a = try analyse(
        \\:Kind :: [flow], [git]
        \\&zone :kind :: :Kind
        \\A :: f
        \\B :: g
        \\C :: h
        \\C :kind [git]
        \\A :kind [flow]
    );
    defer a.deinit();
    try testing.expectEqual(@as(usize, 0), a.result.errors.len);
    try testing.expectEqual(@as(usize, 2), a.result.kinds.len);
    try testing.expectEqual(@as(u32, 0), @backingInt(a.result.kinds[0].zone));
    try testing.expectEqualStrings("flow", a.result.kinds[0].label);
    try testing.expectEqual(@as(u32, 2), @backingInt(a.result.kinds[1].zone));
    try testing.expectEqualStrings("git", a.result.kinds[1].label);
}

/// Kinds and a vocabulary to case on, since there is no prelude here.
const kinds =
    \\:Kind :: [flow], [git]
    \\&zone :kind :: :Kind
    \\:Style :: { &node :fill :: :Flag }
    \\&zone :style :: :Style
    \\
;

test "a case declares for its kind; another kind's case may declare the name again" {
    const cases = kinds ++
        \\&zone :kind [flow] :> { :Style :: { &node :knob :: :Flag } }
        \\&zone :kind [git] :> { :Style :: { (&node, &edge) :knob :: :Flag } }
        \\G :: f
        \\
    ;
    try expectTags(cases ++ "G :kind [flow]\nG :style { +f :knob }", &.{});
    try expectTags(cases ++ "G :kind [git]\nG :style { f :knob }", &.{});
    // Each kind's declaration is its own: a flow's knob is a node's only.
    try expectTags(cases ++ "G :kind [flow]\nG :style { f :knob }", &.{.does_not_apply});
    // No kind, or another, admits only what every kind shares.
    try expectTags(cases ++ "G :style { +f :knob }", &.{.not_admitted_by_kind});
    try expectTags(cases ++ "G :style { :nob }", &.{.unknown_attribute});
    // Where no diagram is known, nor is a kind.
    try expectTags(cases ++ ":k := :knob", &.{.not_admitted_by_kind});
    // For every kind and in a case is twice, either way round; so is twice
    // in one kind's case.
    try expectTags(cases ++ ":Style :: { &node :knob :: :Flag }", &.{.name_defined_twice});
    try expectTags(kinds ++ "&zone :kind [flow] :> { :Style :: { &node :fill :: :Flag } }", &.{.name_defined_twice});
    try expectTags(kinds ++ "&zone :kind [flow] :> { :Style :: { &node :a :: :Flag }, :Style :: { &node :a :: :Flag } }", &.{.name_defined_twice});
}

test "a group's diagrams admit a kind's descriptor when they share the kind" {
    const cases = kinds ++
        \\&zone :kind [flow] :> { :Style :: { &node :knob :: :Flag } }
        \\A :: f
        \\B :: g
        \\A :kind [flow]
        \\
    ;
    try expectTags(cases ++ "B :kind [flow]\n(A, B) :style { &node :knob }", &.{});
    try expectTags(cases ++ "B :kind [git]\n(A, B) :style { &node :knob }", &.{.not_admitted_by_kind});
}

test "a case tests &zone :kind, and holds declarations and records of types" {
    try expectTags(kinds ++ "&node :kind [flow] :> { :Style :: { &node :b :: :Flag } }", &.{.case_on_another_descriptor});
    try expectTags(kinds ++ "&zone :fill :> { :Style :: { &node :b :: :Flag } }", &.{.case_on_another_descriptor});
    try expectTags(kinds ++ "G :: f\nG :kind [flow] :> { :Style :: { &node :b :: :Flag } }", &.{.case_on_another_descriptor});
    try expectTags(kinds ++ "&zone :kind [dark] :> { :Style :: { &node :b :: :Flag } }", &.{.undefined_name});
    try expectTags(kinds ++ "&zone :kind [flow] :> { :Kind :: [blob] }", &.{.case_item_of_no_form});
    try expectTags(kinds ++ "&zone :kind [flow] :> { #A :fill }", &.{.case_item_of_no_form});
    try expectTags(kinds ++ "&zone :kind [flow] :> { :Style :: { [x] } }", &.{.case_item_of_no_form});
    // A kind's theme, one per kind; a record of another type waits for its
    // layer (plan step 11d).
    try expectTags(kinds ++ "&zone :kind [flow] :> { :Style := { &node :fill } }", &.{});
    try expectTags(kinds ++ "&zone :kind [flow] :> { :Style := { &node :fill } }\n&zone :kind [flow] :> { :Style := { &node :fill } }", &.{.name_defined_twice});
    try expectTags(kinds ++ ":Proof :: { &zone :strict :: :Flag }\n&zone :kind [flow] :> { :Proof := { :strict } }", &.{.unsupported_case});
}

test "runs inside groups are checked on their own" {
    try expectTags("G :: a\nG :prove { :axiom ((a == b ~= c) == d) }", &.{ .unsupported_layer, .mixed_operators });
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
