//! Turns fAB source into tokens.
//!
//! The lexer is pure: `next` allocates nothing and does no I/O. It never
//! fails either. Anything it doesn't recognise becomes an `.invalid` token,
//! and the parser decides what to report. Names are classified by their first
//! character only; naming conventions are checked later, by the analyser.

const std = @import("std");
const Token = @import("Token.zig");
const Tag = Token.Tag;

const Lexer = @This();

source: [:0]const u8,
index: u32 = 0,

pub fn init(source: [:0]const u8) Lexer {
    std.debug.assert(source.len <= std.math.maxInt(u32));
    return .{ .source = source };
}

/// Lexes the whole source into a struct-of-arrays token list, ending in `.eof`.
pub fn tokenize(gpa: std.mem.Allocator, source: [:0]const u8) error{OutOfMemory}!std.MultiArrayList(Token) {
    var tokens: std.MultiArrayList(Token) = .empty;
    errdefer tokens.deinit(gpa);
    // Roughly one token per 8 bytes of source, the same estimate Zig's own parser uses.
    try tokens.ensureTotalCapacity(gpa, source.len / 8 + 1);

    var lexer = init(source);
    while (true) {
        const token = lexer.next();
        try tokens.append(gpa, token);
        if (token.tag == .eof) return tokens;
    }
}

/// Returns the next token. After the end of the source it keeps returning `.eof`.
pub fn next(self: *Lexer) Token {
    self.skipTrivia();
    const start = self.index;
    const tag: Tag = switch (self.peek(0)) {
        0 => if (self.atEnd()) .eof else self.one(.invalid), // a NUL byte inside the source

        '\n' => self.one(.eol),

        // names
        'a'...'z', '_', 0x80...0xff => self.name(.edge_id, true),
        'A'...'Z' => self.name(.zone_id, false),
        '#' => if (isUpper(self.peek(1))) blk: {
            self.index += 1;
            break :blk self.name(.node_id, false);
        } else self.one(.invalid),
        ':' => switch (self.peek(1)) {
            ':' => self.two(.decl),
            '=' => self.two(.defn),
            'a'...'z' => blk: {
                self.index += 1;
                break :blk self.name(.attr_id, true);
            },
            else => self.one(.invalid),
        },

        // literals
        '0'...'9' => self.number(),
        '"' => self.delimited('"', .string),
        '$' => self.delimited('$', .math),
        '[' => self.bracket(),

        // operators
        '/' => self.one(.slash),
        '+' => self.one(.plus),
        '*' => self.one(.star),
        '?' => self.one(.quid),
        '!' => self.one(.bang),
        '@' => self.one(.at),
        '.' => if (self.peek(1) == '.') self.two(.range) else self.one(.dot),
        '=' => if (self.peek(1) == '=') self.two(.iden) else self.one(.invalid),
        '~' => if (self.peek(1) == '=') self.two(.cong) else self.one(.invalid),

        // structure
        ',' => self.one(.comma),
        '(' => self.one(.l_paren),
        ')' => self.one(.r_paren),
        ']' => self.one(.r_brack),
        '{' => self.one(.l_brace),
        '}' => self.one(.r_brace),

        else => self.one(.invalid),
    };
    return .{ .tag = tag, .start = start, .end = self.index };
}

// ---------------------------------------------------------------------------
// Scanning helpers. Each one advances `index` past what it consumed and
// returns the tag of the token it found.

/// Spaces, tabs, carriage returns and `//` comments. Newlines are tokens.
fn skipTrivia(self: *Lexer) void {
    while (true) switch (self.peek(0)) {
        ' ', '\t', '\r' => self.index += 1,
        '/' => {
            if (self.peek(1) != '/') return;
            while (self.peek(0) != '\n' and !self.atEnd()) self.index += 1;
        },
        else => return,
    };
}

fn one(self: *Lexer, tag: Tag) Tag {
    self.index += 1;
    return tag;
}

fn two(self: *Lexer, tag: Tag) Tag {
    self.index += 2;
    return tag;
}

/// A name whose first character has already been checked by the caller.
/// Edge and attribute names may also contain `-` (`double-circle`, `:label-start`).
fn name(self: *Lexer, tag: Tag, allow_hyphen: bool) Tag {
    self.index += 1;
    while (true) {
        const c = self.peek(0);
        if (isNameBody(c) or (allow_hyphen and c == '-')) self.index += 1 else return tag;
    }
}

/// `20`, `0.5`, `0xc0392b`. A `.` is taken only when a digit follows,
/// so `0..1` is `0`, `..`, `1`.
fn number(self: *Lexer) Tag {
    if (self.peek(0) == '0' and (self.peek(1) == 'x' or self.peek(1) == 'X') and isHex(self.peek(2))) {
        self.index += 2;
        while (isHex(self.peek(0))) self.index += 1;
        return .number;
    }
    while (isDigit(self.peek(0))) self.index += 1;
    if (self.peek(0) == '.' and isDigit(self.peek(1))) {
        self.index += 1;
        while (isDigit(self.peek(0))) self.index += 1;
    }
    return .number;
}

/// `"…"` and `$…$`. A backslash escapes the next character, so `\"`, `\$`
/// and `\}` stay inside. Reaching a newline or the end first gives `.invalid`.
fn delimited(self: *Lexer, close: u8, tag: Tag) Tag {
    self.index += 1;
    while (true) {
        const c = self.peek(0);
        if (c == close) {
            self.index += 1;
            return tag;
        }
        if (c == '\n' or c == 0) return .invalid;
        self.index += 1;
        if (c == '\\' and self.peek(0) != '\n' and self.peek(0) != 0) self.index += 1;
    }
}

/// At `[`: if only arrow glyphs follow, up to a `]`, the whole bracket is one
/// `.arrow` token. Otherwise this is an ordinary `[`, as in `[f α g]`.
/// Arrow glyphs never include letters, and every 2-cell term contains a name,
/// so the two cases can't be confused.
fn bracket(self: *Lexer) Tag {
    var i = self.index + 1;
    while (isArrowGlyph(self.at(i))) i += 1;
    if (i > self.index + 1 and self.at(i) == ']') {
        self.index = i + 1;
        return .arrow;
    }
    return self.one(.l_brack);
}

// ---------------------------------------------------------------------------
// Character access and classes.

fn atEnd(self: *const Lexer) bool {
    return self.index >= self.source.len;
}

/// The byte at `index + offset`, or 0 past the end.
fn peek(self: *const Lexer, offset: u32) u8 {
    return self.at(self.index + offset);
}

fn at(self: *const Lexer, i: u32) u8 {
    return if (i < self.source.len) self.source[i] else 0;
}

fn isUpper(c: u8) bool {
    return c >= 'A' and c <= 'Z';
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isHex(c: u8) bool {
    return isDigit(c) or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}

/// Letters, digits, `_`, `'`, and any non-ASCII byte, so UTF-8 names like `α`
/// lex as one name without Unicode tables.
fn isNameBody(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '\'' or c >= 0x80;
}

fn isArrowGlyph(c: u8) bool {
    return switch (c) {
        '-', '=', '~', '.', '>', '<', '|', '0', '@', '*', '(', ')', '{', '}', '/', '\\' => true,
        else => false,
    };
}

// ---------------------------------------------------------------------------
// Tests

const testing = std.testing;

/// Lexes `source` into `buf`, excluding the final `.eof`.
fn lexAll(source: [:0]const u8, buf: []Token) []Token {
    var lexer = init(source);
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
        "h'",     "merge'",        "user_id",
        "α",     "double-circle", "_id",
        "#UUID7", "#A",            "User",
        "T",      "A'",
    });
}

test "a # not followed by an uppercase letter is invalid" {
    try expectTags("#a # #1", &.{ .invalid, .edge_id, .invalid, .invalid, .number });
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
    try expectTags("f { :arrow [||-0{] }", &.{ .edge_id, .l_brace, .attr_id, .arrow, .r_brace });
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
    , &.{ .string, .string, .math, .math, .math });

    // math may contain braces without closing the format block
    try expectTags("+f { :label $\\}$ }", &.{ .plus, .edge_id, .l_brace, .attr_id, .math, .r_brace });
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
    try expectTags("/ + * ? ! @ . .. == ~= , ( ) ] { }", &.{
        .slash, .plus,    .star,    .quid,    .bang,    .at,      .dot, .range, .iden, .cong,
        .comma, .l_paren, .r_paren, .r_brack, .l_brace, .r_brace,
    });
    try expectTags("= ~ - ; %", &.{ .invalid, .invalid, .invalid, .invalid, .invalid });
}

test "eof repeats" {
    var lexer = init("f");
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
        var lexer = init(source);
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
    var tokens = try tokenize(testing.allocator, "G :: f g");
    defer tokens.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 5), tokens.len);
    try testing.expectEqual(Tag.eof, tokens.items(.tag)[4]);
}
