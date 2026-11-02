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
    try expectDump("G :: f ?(g, h)? k",
        \\root
        \\  statement ::
        \\    leaf zone_id G
        \\    o_chain
        \\      leaf edge_id f
        \\      prefix ?
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

test "definitions: entries, groups of subjects, and blocks as factored subjects" {
    try expectDump(
        \\G :style := { #Done :label "x", (yes, paid) :label "yes", +f { :shape [circle] } }
    ,
        \\root
        \\  statement :=
        \\    entry
        \\      leaf zone_id G
        \\      attr :style
        \\    block
        \\      items
        \\        entry
        \\          leaf node_id #Done
        \\          attr :label
        \\            leaf str "x"
        \\        entry
        \\          group
        \\            items
        \\              leaf edge_id yes
        \\              leaf edge_id paid
        \\          attr :label
        \\            leaf str "yes"
        \\        entry
        \\          prefix +
        \\            leaf edge_id f
        \\          block
        \\            entry
        \\              attr :shape
        \\                leaf val [circle]
        \\
    );
}

test "the heads of definitions: a value, a bundle, an attribute at a subject" {
    try expectDump(
        \\[red] := [#ff0000]
        \\:terminal := :shape [circle] :fill [red]
        \\G.f :arrow := [epi]
    ,
        \\root
        \\  statement :=
        \\    leaf val [red]
        \\    leaf val [#ff0000]
        \\  statement :=
        \\    entry
        \\      attr :terminal
        \\    entry
        \\      attr :shape
        \\        leaf val [circle]
        \\      attr :fill
        \\        leaf val [red]
        \\  statement :=
        \\    entry
        \\      juxtafix
        \\        leaf zone_id G
        \\        leaf edge_id f
        \\      attr :arrow
        \\    leaf val [epi]
        \\
    );
}

test "operations: one level, a flat run, groups to mix" {
    try expectDump("Sq :prove := { f h == g k == d, (f == g) ~= h, +f :pullback }",
        \\root
        \\  statement :=
        \\    entry
        \\      leaf zone_id Sq
        \\      attr :prove
        \\    block
        \\      items
        \\        operation == ==
        \\          o_chain
        \\            leaf edge_id f
        \\            leaf edge_id h
        \\          o_chain
        \\            leaf edge_id g
        \\            leaf edge_id k
        \\          leaf edge_id d
        \\        operation ~=
        \\          group
        \\            operation ==
        \\              leaf edge_id f
        \\              leaf edge_id g
        \\          leaf edge_id h
        \\        entry
        \\          prefix +
        \\            leaf edge_id f
        \\          attr :pullback
        \\
    );
}

test "the superset: shapes the analyser will reject still parse" {
    try expectErrors("G :: f == g ~= h", &.{}); // mixed operators
    try expectErrors("G :style := f g", &.{}); // a bare term in a definition
    try expectErrors("G :: f (g :label \"x\")", &.{}); // an entry in a declaration
    try expectErrors("f :: g", &.{}); // an edge's declaration
    try expectErrors("G :: f (g | h)", &.{.{ .bar_in_group, "|" }}); // but not this
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
// Errors

test "statement errors" {
    try expectFirstError("Db :: (\n  f\n)", .statement_spans_lines, "\n");
    try expectFirstError("G :style := #Done :terminal f :label \"x\"", .missing_comma, "f");
    try expectFirstError("G :: (f, g,)", .trailing_comma, ",");
    try expectFirstError("G :style := { a :x, }", .trailing_comma, ",");
    try expectFirstError("G :: {}", .empty_braces, "{");
    try expectFirstError("G :style := {}", .empty_braces, "{");
    try expectFirstError("Db :: (f,\n  g)", .statement_spans_lines, "\n");
    try expectFirstError("G :: f | | m", .empty_level, "|");
    try expectFirstError(") f", .expected_statement, ")");
    try expectFirstError("G f", .expected_token, "");
}

test "touching errors" {
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

test "recovery: a failure inside braces skips to the line after them" {
    var cst = try parse(testing.allocator, "G :: {\n  f /g,\n  h\n}\nJ :: n");
    defer cst.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 1), cst.errors.len);
    const statements = cst.children(.root);
    try testing.expectEqual(@as(usize, 2), statements.len);
    try testing.expectEqual(Node.Tag.invalid, cst.tag(statements[0]));
    try testing.expectEqual(Node.Tag.statement, cst.tag(statements[1]));
}

// ---------------------------------------------------------------------------
// The examples

test "the examples parse with no errors" {
    const examples = [_][:0]const u8{
        \\G :: f
        ,
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
        ,
        \\If    :: f ?(fg g, fh h)? k              // decision, two branches, merge
        \\While :: f ?(b/b, e) k                   // body b loops on the test; e exits to k
        \\Exit  :: f ?(fg g/*, fh h) k             // g's branch stops; only h continues to k
        \\Loop  :: f ?(fg g, fh h k/+f)            // k : cod(h) → dom(f), back before the test
        \\Par   :: */s !(a, b)! t/*                // start, fork, two parallel branches, join, stop
        ,
        \\Order :: {
        \\  */receive/#Received validate ?(
        \\      yes/#Accepted fork !(
        \\          charge ?(paid, declined/#Waiting/retry)
        \\        , reserve ?(reserved, short/#Backorder/restock)
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
        ,
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
        ,
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
    };
    for (examples) |source| {
        var cst = try parse(testing.allocator, source);
        defer cst.deinit(testing.allocator);
        for (cst.errors) |e| {
            std.debug.print("unexpected {s} at '{s}'\n", .{ @tagName(e.tag), cst.tokenText(e.token) });
        }
        try testing.expectEqual(@as(usize, 0), cst.errors.len);
    }
}
