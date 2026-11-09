//! Tests for the parser and the concrete syntax tree: source in, tree out.
//!
//! Most tests parse source and compare the tree's dump, one node per line.
//! Errors are checked by tag and by the text of the token they point at.

const std = @import("std");
const testing = std.testing;
const Parser = @import("Parser.zig");
const Cst = @import("Cst.zig");

const parse = Parser.parse;
const Node = Cst.Node;

fn expectDump(source: [:0]const u8, expected: []const u8) !void {
    var cst = try parse(testing.allocator, source);
    defer cst.deinit(testing.allocator);
    for (cst.errors) |e| std.debug.print("unexpected {s} at '{s}'\n", .{ @tagName(e.tag), cst.tokenText(e.token) });
    try testing.expectEqual(@as(usize, 0), cst.errors.len);
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try cst.dump(&out.writer);
    try testing.expectEqualStrings(expected, out.written());
}

const ExpectedError = struct { Cst.Error.Tag, []const u8 };

/// Checks every error's tag and the text of the token it points at.
fn expectErrors(source: [:0]const u8, expected: []const ExpectedError) !void {
    var cst = try parse(testing.allocator, source);
    defer cst.deinit(testing.allocator);
    testing.expectEqual(expected.len, cst.errors.len) catch |err| {
        for (cst.errors) |e| std.debug.print("got {s} at '{s}'\n", .{ @tagName(e.tag), cst.tokenText(e.token) });
        return err;
    };
    for (cst.errors, expected) |got, want| {
        try testing.expectEqual(want[0], got.tag);
        try testing.expectEqualStrings(want[1], cst.tokenText(got.token));
    }
}

/// Checks the errors, and the tree that recovery leaves.
fn expectRecovery(source: [:0]const u8, errors: []const ExpectedError, expected: []const u8) !void {
    try expectErrors(source, errors);
    var cst = try parse(testing.allocator, source);
    defer cst.deinit(testing.allocator);
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try cst.dump(&out.writer);
    try testing.expectEqualStrings(expected, out.written());
}

/// Checks the first error only, for sources whose recovery isn't the point.
fn expectFirstError(source: [:0]const u8, tag: Cst.Error.Tag, at: []const u8) !void {
    var cst = try parse(testing.allocator, source);
    defer cst.deinit(testing.allocator);
    if (cst.errors.len == 0) return error.TestExpectedError;
    testing.expectEqual(tag, cst.errors[0].tag) catch |err| {
        std.debug.print("source: {s}\ngot {s} at '{s}'\n", .{ source, @tagName(cst.errors[0].tag), cst.tokenText(cst.errors[0].token) });
        return err;
    };
    try testing.expectEqualStrings(at, cst.tokenText(cst.errors[0].token));
}

// ---------------------------------------------------------------------------
// Chains

test "a single edge is a leaf, not a chain" {
    try expectDump("G :: f",
        \\root
        \\  statement ::
        \\    leaf zone_id G
        \\    leaf edge_id f
        \\
    );
}

test "an open chain is flat" {
    try expectDump("G :: f g h",
        \\root
        \\  statement ::
        \\    leaf zone_id G
        \\    o_chain
        \\      leaf edge_id f
        \\      leaf edge_id g
        \\      leaf edge_id h
        \\
    );
}

test "a closed chain is flat" {
    try expectDump("G :: f/g/h",
        \\root
        \\  statement ::
        \\    leaf zone_id G
        \\    c_chain
        \\      leaf edge_id f
        \\      leaf edge_id g
        \\      leaf edge_id h
        \\
    );
}

test "a comma is looser than a chain" {
    try expectDump("G :: f g, h",
        \\root
        \\  statement ::
        \\    leaf zone_id G
        \\    items
        \\      o_chain
        \\        leaf edge_id f
        \\        leaf edge_id g
        \\      leaf edge_id h
        \\
    );
}

test "a slash is tighter than a space" {
    // f g/h is f (g/h); +f/α β/g+ is (+f/α) (β/g+): a path through a fresh node
    try expectDump("G :: f g/h, +f/α β/g+",
        \\root
        \\  statement ::
        \\    leaf zone_id G
        \\    items
        \\      o_chain
        \\        leaf edge_id f
        \\        c_chain
        \\          leaf edge_id g
        \\          leaf edge_id h
        \\      o_chain
        \\        c_chain
        \\          prefix +
        \\            leaf edge_id f
        \\          leaf edge_id α
        \\        c_chain
        \\          leaf edge_id β
        \\          postfix +
        \\            leaf edge_id g
        \\
    );
}

test "postfix, then juxtafix, then prefix" {
    // A.f+ is A.(f+); +A.f is +(A.f); A.+f qualifies a reference
    try expectDump("G :: A.f+, +A.f, A.+f",
        \\root
        \\  statement ::
        \\    leaf zone_id G
        \\    items
        \\      juxtafix
        \\        leaf zone_id A
        \\        postfix +
        \\          leaf edge_id f
        \\      prefix +
        \\        juxtafix
        \\          leaf zone_id A
        \\          leaf edge_id f
        \\      juxtafix
        \\        leaf zone_id A
        \\        prefix +
        \\          leaf edge_id f
        \\
    );
}

test "a slash touching only its left side is postfix" {
    try expectDump("G :: f/ g/, #A/f/#B/",
        \\root
        \\  statement ::
        \\    leaf zone_id G
        \\    items
        \\      o_chain
        \\        postfix /
        \\          leaf edge_id f
        \\        postfix /
        \\          leaf edge_id g
        \\      c_chain
        \\        leaf node_id #A
        \\        leaf edge_id f
        \\        postfix /
        \\          leaf node_id #B
        \\
    );
}

test "markers on groups: postfix binds tighter than prefix" {
    try expectDump("G :: f/? +(g, h)? k",
        \\root
        \\  statement ::
        \\    leaf zone_id G
        \\    o_chain
        \\      c_chain
        \\        leaf edge_id f
        \\        leaf quid ?
        \\      prefix +
        \\        postfix ?
        \\          group
        \\            items
        \\              leaf edge_id g
        \\              leaf edge_id h
        \\      leaf edge_id k
        \\
    );
}

test "node terms: named nodes, @, *, diagram names and classes are leaves" {
    try expectDump("G :: */f/#A, @/id/T.#UUID7, &node",
        \\root
        \\  statement ::
        \\    leaf zone_id G
        \\    items
        \\      c_chain
        \\        leaf star *
        \\        leaf edge_id f
        \\        leaf node_id #A
        \\      c_chain
        \\        leaf at @
        \\        leaf edge_id id
        \\        juxtafix
        \\          leaf zone_id T
        \\          leaf node_id #UUID7
        \\      leaf class_id &node
        \\
    );
}

// ---------------------------------------------------------------------------
// Statements, levels and lines

test "levels" {
    try expectDump("Nat :: +(f, g)+ | f/α/g",
        \\root
        \\  statement ::
        \\    leaf zone_id Nat
        \\    levels
        \\      prefix +
        \\        postfix +
        \\          group
        \\            items
        \\              leaf edge_id f
        \\              leaf edge_id g
        \\      c_chain
        \\        leaf edge_id f
        \\        leaf edge_id α
        \\        leaf edge_id g
        \\
    );
}

test "braces let a statement span lines; inside them a newline is a space" {
    try expectDump("G :: {\n  f\n  g,\n  h\n}\nH :: k",
        \\root
        \\  statement ::
        \\    leaf zone_id G
        \\    block
        \\      items
        \\        o_chain
        \\          leaf edge_id f
        \\          leaf edge_id g
        \\        leaf edge_id h
        \\  statement ::
        \\    leaf zone_id H
        \\    leaf edge_id k
        \\
    );
}

test "descriptions: entries, groups of contexts, and blocks as factored contexts" {
    try expectDump(
        \\G :style { #Done :label "x", (yes, paid) :label "yes", +f { :shape [circle] } }
    ,
        \\root
        \\  entry
        \\    leaf zone_id G
        \\    attr :style
        \\      block
        \\        items
        \\          entry
        \\            leaf node_id #Done
        \\            attr :label
        \\              leaf str "x"
        \\          entry
        \\            group
        \\              items
        \\                leaf edge_id yes
        \\                leaf edge_id paid
        \\            attr :label
        \\              leaf str "yes"
        \\          entry
        \\            prefix +
        \\              leaf edge_id f
        \\            block
        \\              entry
        \\                attr :shape
        \\                  leaf val [circle]
        \\
    );
}

test "namings and a description: a value, a bundle, a descriptor at a context" {
    try expectDump(
        \\[red] := [#ff0000]
        \\:terminal := :shape [circle], :fill [red]
        \\G.f :arrow [epi]
    ,
        \\root
        \\  statement :=
        \\    leaf val [red]
        \\    leaf val [#ff0000]
        \\  statement :=
        \\    entry
        \\      attr :terminal
        \\    items
        \\      entry
        \\        attr :shape
        \\          leaf val [circle]
        \\      entry
        \\        attr :fill
        \\          leaf val [red]
        \\  entry
        \\    juxtafix
        \\      leaf zone_id G
        \\      leaf edge_id f
        \\    attr :arrow
        \\      leaf val [epi]
        \\
    );
}

test "operations: one level, a flat run, groups to mix" {
    try expectDump("Sq :prove { :axiom (f h == g k == d, (f == g) ~= h, +f :pullback) }",
        \\root
        \\  entry
        \\    leaf zone_id Sq
        \\    attr :prove
        \\      block
        \\        entry
        \\          attr :axiom
        \\            group
        \\              items
        \\                operation == ==
        \\                  o_chain
        \\                    leaf edge_id f
        \\                    leaf edge_id h
        \\                  o_chain
        \\                    leaf edge_id g
        \\                    leaf edge_id k
        \\                  leaf edge_id d
        \\                operation ~=
        \\                  group
        \\                    operation ==
        \\                      leaf edge_id f
        \\                      leaf edge_id g
        \\                  leaf edge_id h
        \\                entry
        \\                  prefix +
        \\                    leaf edge_id f
        \\                  attr :pullback
        \\
    );
}

test "the superset: shapes the analyser will reject still parse" {
    try expectErrors("G :: f == g ~= h", &.{}); // mixed operators
    try expectErrors("G :style { f g }", &.{}); // a bare term in a record
    try expectErrors("G :style := { f }", &.{}); // a description with an operator
    try expectErrors(":fill [red]", &.{}); // a description with no context
    try expectErrors(":R [x] := { [ink] :: :Color }", &.{}); // a declaration in a record
    try expectErrors("G :: f (g :label \"x\")", &.{}); // an entry in a declaration
    try expectErrors("f :: g", &.{}); // an edge's declaration
    try expectErrors("G :: f (g | h)", &.{.{ .bar_in_group, "|" }}); // but not this
}

// ---------------------------------------------------------------------------
// Kinds: a `?` or `!` touching an atom is a prefix; otherwise a node. Where
// either may stand is the analyser's call.

test "kinds: a node after an edge" {
    try expectDump("G :: f/! +(a, b)",
        \\root
        \\  statement ::
        \\    leaf zone_id G
        \\    o_chain
        \\      c_chain
        \\        leaf edge_id f
        \\        leaf bang !
        \\      prefix +
        \\        group
        \\          items
        \\            leaf edge_id a
        \\            leaf edge_id b
        \\
    );
}

test "kinds: a node before a comma or a closing parenthesis" {
    try expectDump("G :: f/?, (g/!)",
        \\root
        \\  statement ::
        \\    leaf zone_id G
        \\    items
        \\      c_chain
        \\        leaf edge_id f
        \\        leaf quid ?
        \\      group
        \\        c_chain
        \\          leaf edge_id g
        \\          leaf bang !
        \\
    );
}

test "kinds: a node on the left, or after a group" {
    try expectDump("G :: ?/f, (a, b)/!",
        \\root
        \\  statement ::
        \\    leaf zone_id G
        \\    items
        \\      c_chain
        \\        leaf quid ?
        \\        leaf edge_id f
        \\      c_chain
        \\        group
        \\          items
        \\            leaf edge_id a
        \\            leaf edge_id b
        \\        leaf bang !
        \\
    );
}

test "kinds: a prefix, touching an atom" {
    try expectDump("G :: ?(a, b)",
        \\root
        \\  statement ::
        \\    leaf zone_id G
        \\    prefix ?
        \\      group
        \\        items
        \\          leaf edge_id a
        \\          leaf edge_id b
        \\
    );
}

test "kinds: a node beside a space" {
    try expectDump("G :: ? f",
        \\root
        \\  statement ::
        \\    leaf zone_id G
        \\    o_chain
        \\      leaf quid ?
        \\      leaf edge_id f
        \\
    );
}

// ---------------------------------------------------------------------------
// Spans

test "first and last tokens" {
    var cst = try parse(testing.allocator, "G :: +f/(g h)? k");
    defer cst.deinit(testing.allocator);
    const statement = cst.children(.root)[0];
    const body = cst.children(statement)[1];
    const closed = cst.children(body)[0];
    try testing.expectEqualStrings("G", cst.tokenText(cst.firstToken(statement)));
    try testing.expectEqualStrings("k", cst.tokenText(cst.lastToken(statement)));
    try testing.expectEqualStrings("+", cst.tokenText(cst.firstToken(closed)));
    try testing.expectEqualStrings("?", cst.tokenText(cst.lastToken(closed)));
}

// ---------------------------------------------------------------------------
// Types, labels and signatures (statements.md §21). The parser reads every
// head as an item; which head means what is the analyser's call.

test "a type declares its labels" {
    try expectDump(":Shape :: [circle], [box]",
        \\root
        \\  statement ::
        \\    leaf type_id :Shape
        \\    items
        \\      leaf val [circle]
        \\      leaf val [box]
        \\
    );
}

test "a signature: classes, a function, a type" {
    try expectDump("(&node, &zone) :fill :: :Color",
        \\root
        \\  statement ::
        \\    entry
        \\      group
        \\        items
        \\          leaf class_id &node
        \\          leaf class_id &zone
        \\      attr :fill
        \\    leaf type_id :Color
        \\
    );
}

test "a typed name is a type and a value side by side" {
    try expectDump(":Color [red] := [#d1242f]",
        \\root
        \\  statement :=
        \\    o_chain
        \\      leaf type_id :Color
        \\      leaf val [red]
        \\    leaf val [#d1242f]
        \\
    );
}

test "types are spelled like their values: a choice, a twin, a bracket, a group" {
    try expectDump(
        \\:Tip :: :Head, :Hook!, :Nil
        \\:Arrow :: [:Tip/:Stroke/:Tip]
        \\&node :fill :: (:Color, :Nil)
    ,
        \\root
        \\  statement ::
        \\    leaf type_id :Tip
        \\    items
        \\      leaf type_id :Head
        \\      postfix !
        \\        leaf type_id :Hook
        \\      leaf type_id :Nil
        \\  statement ::
        \\    leaf type_id :Arrow
        \\    leaf val [:Tip/:Stroke/:Tip]
        \\  statement ::
        \\    entry
        \\      leaf class_id &node
        \\      attr :fill
        \\    group
        \\      items
        \\        leaf type_id :Color
        \\        leaf type_id :Nil
        \\
    );
}

test "a record names a token: a naming inside braces" {
    try expectDump(":Record [dark] := { [ink] := [#dddddd], &zone :fill [#1e1e1e] }",
        \\root
        \\  statement :=
        \\    o_chain
        \\      leaf type_id :Record
        \\      leaf val [dark]
        \\    block
        \\      items
        \\        statement :=
        \\          leaf val [ink]
        \\          leaf val [#dddddd]
        \\        entry
        \\          leaf class_id &zone
        \\          attr :fill
        \\            leaf val [#1e1e1e]
        \\
    );
}

test "the empty list" {
    try expectDump("G :theme []",
        \\root
        \\  entry
        \\    leaf zone_id G
        \\    attr :theme
        \\      leaf val []
        \\
    );
}

test "a ! touching a flag turns it off" {
    try expectDump("G :style { f :hide!, g :hide! [x] }",
        \\root
        \\  entry
        \\    leaf zone_id G
        \\    attr :style
        \\      block
        \\        items
        \\          entry
        \\            leaf edge_id f
        \\            attr :hide!
        \\          entry
        \\            leaf edge_id g
        \\            attr :hide!
        \\              leaf val [x]
        \\
    );

    var cst = try parse(testing.allocator, "G.f :hide!");
    defer cst.deinit(testing.allocator);
    const entry = cst.children(.root)[0];
    const attr = cst.children(entry)[1];
    try testing.expect(cst.inverted(attr));
    try testing.expectEqualStrings("!", cst.tokenText(cst.lastToken(entry)));
}

test "a table's key touches its descriptor, before any !" {
    try expectDump("R :prove { :lemma.[clean] (#M :pushout), :axiom.[a]! }",
        \\root
        \\  entry
        \\    leaf zone_id R
        \\    attr :prove
        \\      block
        \\        items
        \\          entry
        \\            attr :lemma.[clean]
        \\              group
        \\                entry
        \\                  leaf node_id #M
        \\                  attr :pushout
        \\          entry
        \\            attr :axiom.[a]!
        \\
    );

    var cst = try parse(testing.allocator, "R.f :axiom.[a]!");
    defer cst.deinit(testing.allocator);
    const entry = cst.children(.root)[0];
    const attr = cst.children(entry)[1];
    try testing.expectEqualStrings("[a]", cst.tokenText(cst.key(attr).?));
    try testing.expect(cst.inverted(attr));
    try testing.expectEqualStrings("!", cst.tokenText(cst.lastToken(entry)));
    // Apart, the dot is detached.
    try expectFirstError("R :prove { :lemma .[b] }", .detached_dot, ".");
}

test "a ! apart from a flag is a node" {
    try expectErrors("G :style { g :hide ! }", &.{.{ .missing_comma, "!" }});
}

// ---------------------------------------------------------------------------
// Errors

test "statement errors" {
    try expectFirstError("Db :: (\n  f\n)", .statement_spans_lines, "\n");
    try expectFirstError(":t := #Done :terminal f :label \"x\"", .missing_comma, "f");
    try expectFirstError("G :: (f, g,)", .trailing_comma, ",");
    try expectFirstError("G :style { a :x, }", .trailing_comma, ",");
    try expectFirstError("G :: {}", .empty_braces, "{");
    try expectFirstError("G :style { f {} }", .empty_braces, "{");
    try expectFirstError(":Style :: {}", .empty_braces, "{");
    try expectFirstError("Db :: (f,\n  g)", .statement_spans_lines, "\n");
    try expectFirstError("G :: f | | m", .empty_level, "|");
    try expectFirstError(") f", .expected_statement, ")");
    try expectFirstError("G f", .expected_token, "");
}

test "touching errors" {
    try expectFirstError("G :: f+(g, h)", .marker_touches_both_sides, "+");
    try expectFirstError("G :: f?(g, h)", .marker_touches_both_sides, "?");
    try expectFirstError("G :: (a, b)!(c, d)", .marker_touches_both_sides, "!");
    try expectFirstError("G :: f(g)", .atoms_touch, "(");
    try expectFirstError("G :: */f, *f", .atoms_touch, "f");
    try expectFirstError("G :: f / g", .operator_touches_nothing, "/");
    try expectFirstError("G :: + f", .operator_touches_nothing, "+");
    try expectFirstError("G :: f /g", .slash_has_no_prefix_form, "/");
    try expectFirstError("G :: A. f", .detached_dot, ".");
    try expectFirstError("G :: A .f", .detached_dot, ".");
}

test "lexical errors" {
    try expectFirstError("G :: f 30", .invalid_token, "30");
    try expectFirstError("G :: f [g h]", .invalid_token, "[");
}

// ---------------------------------------------------------------------------
// Recovery

test "recovery: one bad statement doesn't hide the next" {
    var cst = try parse(testing.allocator, "G :: f /g h\nH :: (k\nJ :: n");
    defer cst.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 2), cst.errors.len);
    try testing.expectEqual(Cst.Error.Tag.slash_has_no_prefix_form, cst.errors[0].tag);
    try testing.expectEqual(Cst.Error.Tag.statement_spans_lines, cst.errors[1].tag);

    // G parsed up to the error and kept; H became invalid; J is intact.
    const statements = cst.children(.root);
    try testing.expectEqual(@as(usize, 3), statements.len);
    try testing.expectEqual(Node.Tag.statement, cst.tag(statements[0]));
    try testing.expectEqual(Node.Tag.invalid, cst.tag(statements[1]));
    try testing.expectEqual(Node.Tag.statement, cst.tag(statements[2]));
    try testing.expectEqualStrings("J", cst.tokenText(cst.firstToken(statements[2])));
}

test "recovery: inside braces, a failed item becomes invalid and the others survive" {
    try expectRecovery("G :: {\n  f /g,\n  h\n}\nJ :: n", &.{.{ .slash_has_no_prefix_form, "/" }},
        \\root
        \\  statement ::
        \\    leaf zone_id G
        \\    block
        \\      items
        \\        leaf edge_id f
        \\        invalid '/'
        \\        leaf edge_id h
        \\  statement ::
        \\    leaf zone_id J
        \\    leaf edge_id n
        \\
    );
    try expectRecovery("G :: { (f, g | h), k }", &.{.{ .bar_in_group, "|" }},
        \\root
        \\  statement ::
        \\    leaf zone_id G
        \\    block
        \\      items
        \\        invalid '('
        \\        leaf edge_id k
        \\
    );
}

test "recovery: a stray token after the first item of a group in braces keeps the list" {
    // Found by fab-render's random programs: the list had no main token.
    const sources = [_][:0]const u8{
        "A :: {(B :: ",
        "A :: A.?{B :: #Ag)+f g)",
        "A :: {!α /h(#A",
        "A :: #A{f/({(g+/}g ",
        "A :: h{B :: ?f",
    };
    for (sources) |source| {
        var cst = try parse(testing.allocator, source);
        defer cst.deinit(testing.allocator);
        try testing.expect(cst.errors.len > 0);
    }
}

test "an entry has one attribute; several go in braces" {
    try expectDump("G :style { f { :label \"x\", :bend [inner] } }",
        \\root
        \\  entry
        \\    leaf zone_id G
        \\    attr :style
        \\      block
        \\        entry
        \\          leaf edge_id f
        \\          block
        \\            items
        \\              entry
        \\                attr :label
        \\                  leaf str "x"
        \\              entry
        \\                attr :bend
        \\                  leaf val [inner]
        \\
    );
}

test "attributes side by side are an error, never a missing comma" {
    // An assumed comma would make `:bend` bind G.
    try expectErrors("G :style { f :label \"x\" :bend [inner] }", &.{.{ .attributes_side_by_side, ":bend" }});
    try expectErrors("User :style { :label \"users\" :fill [muted] :ink [red] }", &.{.{ .attributes_side_by_side, ":fill" }});
}

test "recovery: a missing comma is assumed, a trailing comma ends the list" {
    try expectRecovery(":t := #Done :terminal f :label \"x\"", &.{.{ .missing_comma, "f" }},
        \\root
        \\  statement :=
        \\    entry
        \\      attr :t
        \\    items
        \\      entry
        \\        leaf node_id #Done
        \\        attr :terminal
        \\      entry
        \\        leaf edge_id f
        \\        attr :label
        \\          leaf str "x"
        \\
    );
    try expectRecovery("G :: (f, g,) h", &.{.{ .trailing_comma, "," }},
        \\root
        \\  statement ::
        \\    leaf zone_id G
        \\    o_chain
        \\      group
        \\        items
        \\          leaf edge_id f
        \\          leaf edge_id g
        \\      leaf edge_id h
        \\
    );
}

test "recovery: a statement spanning lines is skipped until its parentheses balance" {
    try expectRecovery("Db :: (\n  f, g\n)\nH :: k", &.{.{ .statement_spans_lines, "\n" }},
        \\root
        \\  invalid 'Db'
        \\  statement ::
        \\    leaf zone_id H
        \\    leaf edge_id k
        \\
    );
    // a line with `::` or `:=` starts a new statement, balanced or not
    try expectRecovery("H :: (k\nJ :: n", &.{.{ .statement_spans_lines, "\n" }},
        \\root
        \\  invalid 'H'
        \\  statement ::
        \\    leaf zone_id J
        \\    leaf edge_id n
        \\
    );
}
