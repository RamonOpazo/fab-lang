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
    const source = "h' merge' user_id α double-circle _id #UUID7 #A User T A'";
    try expectTags(source, &.{
        .edge_id, .edge_id, .edge_id, .edge_id, .edge_id, .edge_id,
        .node_id, .node_id, .zone_id, .zone_id, .zone_id,
    });
    try expectTexts(source, &.{
        "h'",            "merge'", "user_id",
        "α",
        "double-circle", "_id",    "#UUID7",
        "#A",            "User",   "T",
        "A'",
    });
}

test "a # not followed by an uppercase letter is invalid" {
    try expectTags("#a # #1", &.{ .invalid, .edge_id, .invalid, .invalid, .number });
}

test "an & not followed by a lowercase letter is invalid" {
    try expectTags("&a &A & &1", &.{ .class_id, .invalid, .zone_id, .invalid, .invalid, .number });
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

test "arrows and 2-cells" {
    try expectTags("[->>] [||-0{] [<@>-] [-/->] [..]", &.{ .arrow, .arrow, .arrow, .arrow, .arrow });
    try expectTexts("[||-0{] [(->]", &.{ "[||-0{]", "[(->]" });

    // 2-cells: brackets around names
    try expectTags("[f α g]", &.{ .l_brack, .edge_id, .edge_id, .edge_id, .r_brack });
    try expectTags("[*f]", &.{ .l_brack, .star, .edge_id, .r_brack });

    // not arrows: empty brackets, whitespace inside
    try expectTags("[]", &.{ .l_brack, .r_brack });
    try expectTags("[- >]", &.{ .l_brack, .invalid, .invalid, .r_brack });
}

test "an arrow's braces don't disturb bracket matching" {
    try expectTags("f { :arrow [||-0{] }", &.{ .edge_id, .l_cur, .attr_id, .arrow, .r_cur });
}

test "numbers and ranges" {
    try expectTags("0..* 0..1 0.5 30 0xc0392b", &.{
        .number, .range, .star, .number, .range, .number, .number, .number, .number,
    });
    try expectTexts("0.5 0xc0392b 0x", &.{ "0.5", "0xc0392b", "0", "x" });
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
    try expectTags("/ + * ? ! @ . .. == ~= , | ( ) ] { }", &.{
        .slash, .plus, .star,  .quid,  .bang,    .at,    .dot,   .range, .iden, .cong,
        .comma, .bar,  .l_par, .r_par, .r_brack, .l_cur, .r_cur,
    });
    try expectTags("= ~ - ; %", &.{ .invalid, .invalid, .invalid, .invalid, .invalid });
}

test "eof repeats" {
    var lexer = Lexer.init("f");
    _ = lexer.next();
    try testing.expectEqual(Tag.eof, lexer.next().tag);
    try testing.expectEqual(Tag.eof, lexer.next().tag);
}

test "the spec's larger examples lex with no invalid tokens" {
    const examples = [_][:0]const u8{
        \\Order :: *receive #Received validate #Valid? (
        \\    yes #Accepted! (
        \\        charge #Charged? (paid, declined #Waiting retry/charge+)
        \\      , reserve #InStock? (reserved, short #Backorder restock/reserve+)
        \\    )! #Ready ship #Shipped close*
        \\  , no #Rejected notify*
        \\)
        \\
        \\Order.format {
        \\  #Received  :label "Order received"
        \\  retry, restock       :arrow [-->]  :label "retry"
        \\}
        ,
        \\Db.proof {
        \\  .node.id :pk
        \\  .edge :by {.edge+ :snakecase}_id  :card 0..* 1
        \\  User.(email, nick)! :unique
        \\  reply_to   :by parent_id  :card 0..* 0..1
        \\  reply_to on == on
        \\}
        ,
        \\Nat :: f, +f/g/f+, [f α g]
        \\Sq.format {
        \\  .iso { :arrow [->]  :label $\cong$ }
        \\  f    :class iso
        \\  g, k :stroke 0x888888
        \\}
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
