//! Tests for the lexer: source in, tokens out.

const std = @import("std");
const testing = std.testing;
const Token = @import("Token.zig");
const Lexer = @import("Lexer.zig");

const Tag = Token.Tag;

/// Lexes `source` into `buf`, excluding the final `.eof`.
fn lexAll(source: [:0]const u8, buf: []Token) []Token {
    var lexer = Lexer.init(source);
    var n: usize = 0;
    while (true) {
        const token = lexer.next();
        if (token.tag == .eof) return buf[0..n];
        buf[n] = token;
        n += 1;
    }
}

fn expectTags(source: [:0]const u8, expected: []const Tag) !void {
    var buf: [128]Token = undefined;
    const tokens = lexAll(source, &buf);
    var tags: [128]Tag = undefined;
    for (tokens, 0..) |t, i| tags[i] = t.tag;
    try testing.expectEqualSlices(Tag, expected, tags[0..tokens.len]);
}

fn expectTexts(source: [:0]const u8, expected: []const []const u8) !void {
    var buf: [128]Token = undefined;
    const tokens = lexAll(source, &buf);
    try testing.expectEqual(expected.len, tokens.len);
    for (tokens, expected) |t, want| try testing.expectEqualStrings(want, t.slice(source));
}

test "a diagram declaration" {
    try expectTags("G :: f g h", &.{ .zone_id, .decl, .edge_id, .edge_id, .edge_id });
}

test "the commutative square" {
    try expectTags("Sq :: f h, +f/g k/h+", &.{
        .zone_id, .decl,    .edge_id, .edge_id, .comma,
        .plus,    .edge_id, .slash,   .edge_id, .edge_id,
        .slash,   .edge_id, .plus,
    });
}

test "whitespace decides attachment" {
    var buf: [8]Token = undefined;

    // f/g: binary, touching both sides
    var t = lexAll("f/g", &buf);
    try testing.expect(t[0].touches(t[1]) and t[1].touches(t[2]));

    // f/ g: postfix, touching only f
    t = lexAll("f/ g", &buf);
    try testing.expect(t[0].touches(t[1]) and !t[1].touches(t[2]));

    // f /g: touching only g (the analyser rejects prefix /)
    t = lexAll("f /g", &buf);
    try testing.expect(!t[0].touches(t[1]) and t[1].touches(t[2]));

    // +f is a reference; + f is not
    t = lexAll("+f", &buf);
    try testing.expect(t[0].touches(t[1]));
    t = lexAll("+ f", &buf);
    try testing.expect(!t[0].touches(t[1]));

    // *(f, g): prefix star on a group
    t = lexAll("*(f, g)", &buf);
    try testing.expectEqual(Tag.star, t[0].tag);
    try testing.expect(t[0].touches(t[1]));
}

test "names are classified by their first character" {
    const source = "h' merge' user_id α _id #UUID7 #A User T A'";
    try expectTags(source, &.{
        .edge_id, .edge_id, .edge_id, .edge_id, .edge_id,
        .node_id, .node_id, .zone_id, .zone_id, .zone_id,
    });
    try expectTexts(source, &.{ "h'", "merge'", "user_id", "α", "_id", "#UUID7", "#A", "User", "T", "A'" });
}

test "an edge name ends at a hyphen" {
    try expectTags("double-circle", &.{ .edge_id, .invalid, .edge_id });
}

test "a # not followed by an uppercase letter is invalid" {
    try expectTags("#a # #1", &.{ .invalid, .edge_id, .invalid, .invalid, .invalid });
}

test "an & not followed by a lowercase letter is invalid" {
    try expectTags("&a &A & &1", &.{ .class_id, .invalid, .zone_id, .invalid, .invalid, .invalid });
}

test "classes" {
    try expectTags("&node.id &edge :label", &.{ .class_id, .dot, .edge_id, .class_id, .attr_id });
    try expectTexts("&node &edge_end", &.{ "&node", "&edge_end" });
}

test "colons" {
    try expectTags(":label :label-start :: := : :A", &.{
        .attr_id, .attr_id, .decl, .defn, .invalid, .invalid, .zone_id,
    });
    try expectTexts(":label :label-start", &.{ ":label", ":label-start" });
}

test "a value is one token" {
    try expectTags("[red] [0..*/1] [/dashed/>] [||-0{] [2] [#ff0000]", &.{ .val, .val, .val, .val, .val, .val });
    try expectTexts("[0..*/0..1] [(->]", &.{ "[0..*/0..1]", "[(->]" });
}

test "not a value: an empty bracket, whitespace, a [ inside, no ]" {
    try expectTags("[]", &.{ .invalid, .invalid });
    try expectTags("[- >]", &.{ .invalid, .invalid, .invalid, .invalid });
    try expectTags("[f α g]", &.{ .invalid, .edge_id, .edge_id, .edge_id, .invalid });
    try expectTags("[a[b]", &.{ .invalid, .edge_id, .val });
    try expectTags("[red", &.{ .invalid, .edge_id });
}

test "a value's braces don't disturb brace matching" {
    try expectTags("f { :arrow [||-0{] }", &.{ .edge_id, .l_cur, .attr_id, .val, .r_cur });
}

test "a number outside a value is invalid" {
    try expectTags("30 0.5 1abc", &.{ .invalid, .invalid, .dot, .invalid, .invalid });
    try expectTexts("30 1abc", &.{ "30", "1abc" });
    try expectTags("0..*", &.{ .invalid, .dot, .dot, .star });
}

test "strings and math" {
    try expectTags(
        \\"Order received" "a \"b\"" $\mathbb{R}$ $\{x\}$ $a\$b$
    , &.{ .str, .str, .math, .math, .math });

    // math may contain braces without closing the format block
    try expectTags("+f { :label $\\}$ }", &.{ .plus, .edge_id, .l_cur, .attr_id, .math, .r_cur });
}

test "unterminated strings and math are invalid" {
    try expectTags("\"abc\nf", &.{ .invalid, .eol, .edge_id });
    try expectTags("$x", &.{.invalid});
    try expectTags("\"a\\", &.{.invalid});
}

test "comments and newlines" {
    try expectTags("f g // a comment\nh", &.{ .edge_id, .edge_id, .eol, .edge_id });
    try expectTags("f\r\ng", &.{ .edge_id, .eol, .edge_id });
    try expectTags("// only a comment", &.{});
}

test "every operator" {
    try expectTags("/ + * ? ! @ . == ~= , | ( ) { }", &.{
        .slash, .plus,  .star, .quid,  .bang,  .at,    .dot,   .iden,
        .cong,  .comma, .bar,  .l_par, .r_par, .l_cur, .r_cur,
    });
    try expectTags("= ~ - ; % ]", &.{ .invalid, .invalid, .invalid, .invalid, .invalid, .invalid });
}

test "eof repeats" {
    var lexer = Lexer.init("f");
    _ = lexer.next();
    try testing.expectEqual(Tag.eof, lexer.next().tag);
    try testing.expectEqual(Tag.eof, lexer.next().tag);
}

test "the spec's larger examples lex with no invalid tokens" {
    const examples = [_][:0]const u8{
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
    };
    for (examples) |source| {
        var lexer = Lexer.init(source);
        while (true) {
            const token = lexer.next();
            if (token.tag == .invalid) {
                std.debug.print("unexpected invalid token: '{s}'\n", .{token.slice(source)});
                return error.TestUnexpectedResult;
            }
            if (token.tag == .eof) break;
        }
    }
}

test "tokenize collects every token, ending in eof" {
    var tokens = try Lexer.tokenize(testing.allocator, "G :: f g");
    defer tokens.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 5), tokens.len);
    try testing.expectEqual(Tag.eof, tokens.items(.tag)[4]);
}
