//! Tests for the parser and the concrete syntax tree: source in, tree out.
//!
//! The parser's tests parse source and compare the tree's dump. The tree's
//! own tests, at the end, build trees by hand, to test the dump and the token
//! spans apart from the parser.

const std = @import("std");
const testing = std.testing;
const Lexer = @import("../lex/Lexer.zig");
const Parser = @import("Parser.zig");
const Cst = @import("Cst.zig");

const parse = Parser.parse;
const Node = Cst.Node;
const TokenIndex = Cst.TokenIndex;

fn expectDump(source: [:0]const u8, expected: []const u8) !void {
    var cst = try parse(testing.allocator, source);
    defer cst.deinit(testing.allocator);
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try cst.dump(&out.writer);
    try testing.expectEqualStrings(expected, out.written());
    try testing.expectEqual(@as(usize, 0), cst.errors.len);
}

const ExpectedError = struct { Cst.Error.Tag, []const u8 };

/// Checks each error's tag and the text of the token it points at.
fn expectErrors(source: [:0]const u8, expected: []const ExpectedError) !void {
    var cst = try parse(testing.allocator, source);
    defer cst.deinit(testing.allocator);
    try testing.expectEqual(expected.len, cst.errors.len);
    for (cst.errors, expected) |got, want| {
        try testing.expectEqual(want[0], got.tag);
        try testing.expectEqualStrings(want[1], cst.tokenText(got.token));
    }
}

test "a path" {
    try expectDump("G :: f g h",
        \\root
        \\  relations G
        \\    path
        \\      leaf edge_id f
        \\      leaf edge_id g
        \\      leaf edge_id h
        \\
    );
}

test "a single edge is a leaf, not a path" {
    try expectDump("G :: f",
        \\root
        \\  relations G
        \\    leaf edge_id f
        \\
    );
}

test "comma is looser than juxtaposition" {
    try expectDump("G :: f (g, h) k",
        \\root
        \\  relations G
        \\    path
        \\      leaf edge_id f
        \\      group
        \\        sum
        \\          leaf edge_id g
        \\          leaf edge_id h
        \\      leaf edge_id k
        \\
    );
}

test "slashes chain to the left" {
    try expectDump("Tri :: f g, +f/h/g+",
        \\root
        \\  relations Tri
        \\    sum
        \\      path
        \\        leaf edge_id f
        \\        leaf edge_id g
        \\      slash /
        \\        slash /
        \\          prefix +
        \\            leaf edge_id f
        \\          leaf edge_id h
        \\        postfix +
        \\          leaf edge_id g
        \\
    );
}

test "whitespace decides what a slash does" {
    // f/g: a back edge.  f/ g: undirected f, then g.
    try expectDump("G :: f/g, f/ g",
        \\root
        \\  relations G
        \\    sum
        \\      slash /
        \\        leaf edge_id f
        \\        leaf edge_id g
        \\      path
        \\        postfix /
        \\          leaf edge_id f
        \\        leaf edge_id g
        \\
    );
}

test "a postfix touching a group does not join it" {
    try expectDump("G :: f?(g, h)",
        \\root
        \\  relations G
        \\    path
        \\      postfix ?
        \\        leaf edge_id f
        \\      group
        \\        sum
        \\          leaf edge_id g
        \\          leaf edge_id h
        \\
    );
}

test "markers on groups, and postfix binding tighter than prefix" {
    try expectDump("G :: *(f, g)* h, +k?",
        \\root
        \\  relations G
        \\    sum
        \\      path
        \\        prefix *
        \\          postfix *
        \\            group
        \\              sum
        \\                leaf edge_id f
        \\                leaf edge_id g
        \\        leaf edge_id h
        \\      prefix +
        \\        postfix ?
        \\          leaf edge_id k
        \\
    );
}

test "qualified names, named nodes and the own node" {
    try expectDump("B :: h/A.+f, @ (id T.#UUID7)",
        \\root
        \\  relations B
        \\    sum
        \\      slash /
        \\        leaf edge_id h
        \\        qualified A
        \\          prefix +
        \\            leaf edge_id f
        \\      path
        \\        leaf at @
        \\        group
        \\          path
        \\            leaf edge_id id
        \\            qualified T
        \\              leaf node_id #UUID7
        \\
    );
}

test "edge-to-edge relations" {
    try expectDump("Nat :: f, +f/g/f+, [f α/β g]",
        \\root
        \\  relations Nat
        \\    sum
        \\      leaf edge_id f
        \\      slash /
        \\        slash /
        \\          prefix +
        \\            leaf edge_id f
        \\          leaf edge_id g
        \\        postfix +
        \\          leaf edge_id f
        \\      cells
        \\        path
        \\          leaf edge_id f
        \\          slash /
        \\            leaf edge_id α
        \\            leaf edge_id β
        \\          leaf edge_id g
        \\
    );
}

test "newlines inside parentheses are insignificant" {
    try expectDump(
        \\G :: f? (
        \\    g
        \\  , h
        \\)
        \\H :: k
    ,
        \\root
        \\  relations G
        \\    path
        \\      postfix ?
        \\        leaf edge_id f
        \\      group
        \\        sum
        \\          leaf edge_id g
        \\          leaf edge_id h
        \\  relations H
        \\    leaf edge_id k
        \\
    );
}

test "a format layer" {
    try expectDump(
        \\G :format {
        \\  .iso { :arrow [->]  :label $\cong$ }
        \\  f, g :class iso  :bend left 30
        \\  +f {
        \\    :label $\mathbb{R}$
        \\  }
        \\}
    ,
        \\root
        \\  layer G :format
        \\    block
        \\      entry
        \\        class .iso
        \\        attr_block
        \\          attr :arrow
        \\            leaf arrow [->]
        \\          attr :label
        \\            leaf math $\cong$
        \\      entry
        \\        sum
        \\          leaf edge_id f
        \\          leaf edge_id g
        \\        attrs
        \\          attr :class
        \\            leaf edge_id iso
        \\          attr :bend
        \\            leaf edge_id left
        \\            leaf number 30
        \\      entry
        \\        prefix +
        \\          leaf edge_id f
        \\        attr_block
        \\          attr :label
        \\            leaf math $\mathbb{R}$
        \\
    );
}

test "a proof layer" {
    try expectDump(
        \\Db :proof {
        \\  .edge :by {.edge+ :snakecase}_id  :card 0..* 1
        \\  User.(email, nick)! :unique
        \\  reply_to on == on
        \\}
    ,
        \\root
        \\  layer Db :proof
        \\    block
        \\      entry
        \\        class .edge
        \\        attrs
        \\          attr :by
        \\            ref
        \\              interp
        \\                postfix +
        \\                  class .edge
        \\                attr :snakecase
        \\              leaf edge_id _id
        \\          attr :card
        \\            card 0..*
        \\            leaf number 1
        \\      entry
        \\        qualified User
        \\          postfix !
        \\            group
        \\              sum
        \\                leaf edge_id email
        \\                leaf edge_id nick
        \\        attrs
        \\          attr :unique
        \\      equation ==
        \\        path
        \\          leaf edge_id reply_to
        \\          leaf edge_id on
        \\        leaf edge_id on
        \\
    );
}

test "the superset: shapes the analyser will reject still parse" {
    // a bare reference, a self-reference, a path used as a key
    try expectErrors("G :: k +f", &.{});
    try expectErrors("G :: (f g)/f", &.{});
    try expectErrors("G :: f\nG :proof {\n  User.(email nick) :unique\n}", &.{});
}

test "operator attachment errors" {
    try expectErrors("G :: f /g", &.{.{ .slash_has_no_prefix_form, "/" }});
    try expectErrors("G :: f / g", &.{.{ .operator_touches_nothing, "/" }});
    try expectErrors("G :: + f", &.{.{ .operator_touches_nothing, "+" }});
    try expectErrors("G :: A. f", &.{.{ .detached_dot, "f" }});
}

test "other syntax errors" {
    try expectErrors("G :: f $x", &.{.{ .invalid_token, "$x" }});
    try expectErrors("G f", &.{.{ .expected_token, "f" }});
    try expectErrors("f :: g", &.{.{ .expected_statement, "f" }});
    try expectErrors("G :: (f g", &.{.{ .expected_token, "" }});
    try expectErrors("G :format {\n  f\n}", &.{.{ .expected_attrs_or_relation, "\n" }});
    try expectErrors("G :format {\n  f :card 0..\n}", &.{.{ .expected_token, "\n" }});
}

test "recovery: one bad statement doesn't hide the next" {
    var cst = try parse(testing.allocator,
        \\G :: f /g h
        \\H :: (k
        \\  l / m)
        \\J :: n
    );
    defer cst.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 2), cst.errors.len);
    try testing.expectEqual(Cst.Error.Tag.slash_has_no_prefix_form, cst.errors[0].tag);
    try testing.expectEqual(Cst.Error.Tag.operator_touches_nothing, cst.errors[1].tag);

    // G parsed up to the error and kept; H became invalid; J is intact.
    const statements = cst.children(.root);
    try testing.expectEqual(@as(usize, 3), statements.len);
    try testing.expectEqual(Node.Tag.relations, cst.tag(statements[0]));
    try testing.expectEqual(Node.Tag.invalid, cst.tag(statements[1]));
    try testing.expectEqual(Node.Tag.relations, cst.tag(statements[2]));
    try testing.expectEqualStrings("J", cst.tokenText(cst.mainToken(statements[2])));
}

test "recovery: a failure inside a nested list leaves no stray nodes" {
    // The path inside the group fails at `.#B`, half-built.
    var cst = try parse(testing.allocator, "G :: f* @ (id #A.#B, g)\nH :: k");
    defer cst.deinit(testing.allocator);
    const statements = cst.children(.root);
    try testing.expectEqual(@as(usize, 2), statements.len);
    try testing.expectEqual(Node.Tag.invalid, cst.tag(statements[0]));
    try testing.expectEqual(Node.Tag.relations, cst.tag(statements[1]));
}

test "recovery inside a block keeps the other entries" {
    var cst = try parse(testing.allocator,
        \\G :format {
        \\  f :label "a"
        \\  g h
        \\  k :label "c"
        \\}
    );
    defer cst.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 1), cst.errors.len);
    const block = cst.children(cst.children(.root)[0])[0];
    const entries = cst.children(block);
    try testing.expectEqual(@as(usize, 3), entries.len);
    try testing.expectEqual(Node.Tag.entry, cst.tag(entries[0]));
    try testing.expectEqual(Node.Tag.invalid, cst.tag(entries[1]));
    try testing.expectEqual(Node.Tag.entry, cst.tag(entries[2]));
}

test "the spec's larger examples parse with no errors" {
    const examples = [_][:0]const u8{
        \\Order :: *receive #Received validate #Valid? (
        \\    yes #Accepted! (
        \\        charge #Charged? (paid, declined #Waiting retry/charge+)
        \\      , reserve #InStock? (reserved, short #Backorder restock/reserve+)
        \\    )! #Ready ship #Shipped close*
        \\  , no #Rejected notify*
        \\)
        \\
        \\Order :format {
        \\  #Received  :label "Order received"
        \\  yes, paid, reserved  :label "yes"
        \\  retry, restock       :arrow [-->]  :label "retry"
        \\}
        ,
        \\T :: #UUID7, #DTZ, #String, #Text, #JSONB, #Bool
        \\User    :: @ (id T.#UUID7, email T.#String, nick T.#String)
        \\Comment :: @ (id T.#UUID7, document_id T.#UUID7, parent_id T.#UUID7)
        \\
        \\Db :: (
        \\  Membership (member User, within Organization),
        \\  Comment (on Document, writer User, reply_to Comment)
        \\)
        \\
        \\Db :proof {
        \\  .node.id :pk
        \\  .edge :by {.edge+ :snakecase}_id  :card 0..* 1
        \\  Membership.(user_id, org_id)! :unique
        \\  Comment.(post_id, photo_id)? :required
        \\  reply_to   :by parent_id  :card 0..* 0..1
        \\  reply_to on == on
        \\}
        \\
        \\User :format { User :label "users"  :fill muted }
        ,
        \\Repo :: (
        \\  *init readme #Fork (fix #Main, login session #Feature),
        \\  (#Main merge, #Feature merge') #Merged bump #V1 (hotfix #Head, spike #Spike)
        \\)
        \\
        \\Repo :proof {
        \\  fix merge == login session merge'
        \\  #Merged :pushout
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

// ---------------------------------------------------------------------------
// The tree, built by hand.

/// Builds a Cst from a node list and an extra array, lexing `source` for tokens.
fn build(source: [:0]const u8, nodes: []const Node, extra: []const u32) !Cst {
    const gpa = testing.allocator;
    var tokens = try Lexer.tokenize(gpa, source);
    errdefer tokens.deinit(gpa);
    var node_list: std.MultiArrayList(Node) = .empty;
    errdefer node_list.deinit(gpa);
    for (nodes) |n| try node_list.append(gpa, n);
    return .{
        .source = source,
        .tokens = tokens.toOwnedSlice(),
        .nodes = node_list.toOwnedSlice(),
        .extra = try gpa.dupe(u32, extra),
        .errors = try gpa.alloc(Cst.Error, 0),
    };
}

fn expectTreeDump(cst: Cst, expected: []const u8) !void {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try cst.dump(&out.writer);
    try testing.expectEqualStrings(expected, out.written());
}

fn idx(i: u32) Node.Index {
    return @fromBackingInt(@intCast(i));
}

test "G :: f g" {
    // tokens: 0 G  1 ::  2 f  3 g  4 eof
    var cst = try build("G :: f g", &.{
        .{ .tag = .root, .main_token = 0, .data = .{ .range = .{ .start = 0, .end = 1 } } },
        .{ .tag = .relations, .main_token = 0, .data = .{ .node = idx(2) } },
        .{ .tag = .path, .main_token = 2, .data = .{ .range = .{ .start = 1, .end = 3 } } },
        .{ .tag = .leaf, .main_token = 2, .data = .{ .none = {} } },
        .{ .tag = .leaf, .main_token = 3, .data = .{ .none = {} } },
    }, &.{ 1, 3, 4 });
    defer cst.deinit(testing.allocator);

    try expectTreeDump(cst,
        \\root
        \\  relations G
        \\    path
        \\      leaf edge_id f
        \\      leaf edge_id g
        \\
    );
    try testing.expectEqual(@as(TokenIndex, 2), cst.firstToken(idx(2)));
    try testing.expectEqual(@as(TokenIndex, 3), cst.lastToken(idx(2)));
    try testing.expectEqual(@as(TokenIndex, 0), cst.firstToken(idx(1)));
    try testing.expectEqual(@as(TokenIndex, 3), cst.lastToken(idx(1)));
}

test "back edges, markers and groups: G :: +f/(g h)?" {
    // tokens: 0 G  1 ::  2 +  3 f  4 /  5 (  6 g  7 h  8 )  9 ?  10 eof
    var cst = try build("G :: +f/(g h)?", &.{
        .{ .tag = .root, .main_token = 0, .data = .{ .range = .{ .start = 0, .end = 1 } } },
        .{ .tag = .relations, .main_token = 0, .data = .{ .node = idx(2) } },
        .{ .tag = .slash, .main_token = 4, .data = .{ .nodes = .{ idx(3), idx(5) } } },
        .{ .tag = .prefix, .main_token = 2, .data = .{ .node = idx(4) } },
        .{ .tag = .leaf, .main_token = 3, .data = .{ .none = {} } },
        .{ .tag = .postfix, .main_token = 9, .data = .{ .node = idx(6) } },
        .{ .tag = .group, .main_token = 5, .data = .{ .node_token = .{ idx(7), 8 } } },
        .{ .tag = .path, .main_token = 6, .data = .{ .range = .{ .start = 1, .end = 3 } } },
        .{ .tag = .leaf, .main_token = 6, .data = .{ .none = {} } },
        .{ .tag = .leaf, .main_token = 7, .data = .{ .none = {} } },
    }, &.{ 1, 8, 9 });
    defer cst.deinit(testing.allocator);

    try expectTreeDump(cst,
        \\root
        \\  relations G
        \\    slash /
        \\      prefix +
        \\        leaf edge_id f
        \\      postfix ?
        \\        group
        \\          path
        \\            leaf edge_id g
        \\            leaf edge_id h
        \\
    );
    // the slash spans +f/(g h)?, tokens 2 to 9
    try testing.expectEqual(@as(TokenIndex, 2), cst.firstToken(idx(2)));
    try testing.expectEqual(@as(TokenIndex, 9), cst.lastToken(idx(2)));
}

test "a layer: G :format { +f :label $R$ }" {
    // tokens: 0 G  1 :format  2 {  3 +  4 f  5 :label  6 $R$  7 }  8 eof
    var cst = try build("G :format { +f :label $R$ }", &.{
        .{ .tag = .root, .main_token = 0, .data = .{ .range = .{ .start = 0, .end = 1 } } },
        .{ .tag = .layer, .main_token = 1, .data = .{ .node = idx(2) } },
        .{ .tag = .block, .main_token = 2, .data = .{ .extra = @fromBackingInt(@intCast(1)) } },
        .{ .tag = .entry, .main_token = 3, .data = .{ .nodes = .{ idx(4), idx(6) } } },
        .{ .tag = .prefix, .main_token = 3, .data = .{ .node = idx(5) } },
        .{ .tag = .leaf, .main_token = 4, .data = .{ .none = {} } },
        .{ .tag = .attrs, .main_token = 5, .data = .{ .range = .{ .start = 5, .end = 6 } } },
        .{ .tag = .attr, .main_token = 5, .data = .{ .range = .{ .start = 6, .end = 7 } } },
        .{ .tag = .leaf, .main_token = 6, .data = .{ .none = {} } },
    }, &.{
        1, // root: [layer]
        4, 5, 7, // block: Braced{ start 4, end 5, close token 7 }
        3, // block's entries: [entry]
        7, // attrs: [attr]
        8, // attr's values: [leaf $R$]
    });
    defer cst.deinit(testing.allocator);

    try expectTreeDump(cst,
        \\root
        \\  layer G :format
        \\    block
        \\      entry
        \\        prefix +
        \\          leaf edge_id f
        \\        attrs
        \\          attr :label
        \\            leaf math $R$
        \\
    );
    try testing.expectEqual(@as(TokenIndex, 0), cst.firstToken(idx(1)));
    try testing.expectEqual(@as(TokenIndex, 7), cst.lastToken(idx(1)));
}
