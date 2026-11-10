//! Turns fAB source into tokens.
//!
//! The lexer is pure: `next` allocates nothing and does no I/O. It never
//! fails either. Anything it doesn't recognise becomes an `.invalid` token,
//! and the parser decides what to report. Names are classified by their first
//! character only; naming conventions are checked later, by the analyser.
//!
//! Comments are trivia, but they are kept beside the tokens (`Comment`), for
//! the printer, which must give them back (plan step L4).

const std = @import("std");
const Token = @import("Token.zig");
const Tag = Token.Tag;

const Lexer = @This();

source: [:0]const u8,
index: u32 = 0,
/// The comment skipped before the token `next` last returned, if any.
comment: ?Comment = null,

/// A `//` comment: its text, `//` included, without the line end (nor a
/// `\r` before it). A comment runs to the end of its line, so it comes
/// before a line end or the end of the input, `token`, and at most one comes
/// before any token.
pub const Comment = struct {
    start: u32,
    end: u32,
    /// The index of the token after it: an `.eol` or the `.eof`.
    token: u32,
};

pub fn init(source: [:0]const u8) Lexer {
    std.debug.assert(source.len <= std.math.maxInt(u32));
    return .{ .source = source };
}

/// Lexes the whole source into a struct-of-arrays token list, ending in
/// `.eof`. The comments are appended to `comments`, in order, if given.
pub fn tokenize(gpa: std.mem.Allocator, source: [:0]const u8, comments: ?*std.ArrayList(Comment)) error{OutOfMemory}!std.MultiArrayList(Token) {
    var tokens: std.MultiArrayList(Token) = .empty;
    errdefer tokens.deinit(gpa);
    // Roughly one token per 8 bytes of source, the same estimate Zig's own parser uses.
    try tokens.ensureTotalCapacity(gpa, source.len / 8 + 1);

    var lexer = init(source);
    while (true) {
        const token = lexer.next();
        if (comments) |list| if (lexer.comment) |c| {
            var kept = c;
            kept.token = @intCast(tokens.len);
            try list.append(gpa, kept);
        };
        try tokens.append(gpa, token);
        if (token.tag == .eof) return tokens;
    }
}

/// Returns the next token. After the end of the source it keeps returning
/// `.eof`. The comment before it, if any, is left in `comment`, its `token`
/// unset: only `tokenize` counts tokens.
pub fn next(self: *Lexer) Token {
    self.comment = null;
    self.skipTrivia();
    const start = self.index;
    const tag: Tag = switch (self.peek(0)) {
        0 => if (self.atEnd()) .eof else self.one(.invalid), // a NUL byte inside the source

        '\n' => self.one(.eol),

        // names
        'a'...'z', '_', 0x80...0xff => self.name(.edge_id, false),
        'A'...'Z' => self.name(.zone_id, false),
        '#' => if (isUpper(self.peek(1))) blk: {
            self.index += 1;
            break :blk self.name(.node_id, false);
        } else self.one(.invalid),
        '&' => if (isLower(self.peek(1))) blk: {
            self.index += 1;
            break :blk self.name(.class_id, false);
        } else self.one(.invalid),
        ':' => switch (self.peek(1)) {
            ':' => self.two(.decl),
            '=' => self.two(.defn),
            'a'...'z' => blk: {
                self.index += 1;
                break :blk self.name(.attr_id, true);
            },
            // Types are UpperCamel, so no hyphen.
            'A'...'Z' => blk: {
                self.index += 1;
                break :blk self.name(.type_id, false);
            },
            else => self.one(.invalid),
        },

        // a name can't start with a digit, so a number outside a value is invalid
        '0'...'9' => self.name(.invalid, false),

        // literals
        '"' => self.delimited('"', .str),
        '$' => self.delimited('$', .math),
        '[' => self.value(),

        // operators
        '/' => self.one(.slash),
        '+' => self.one(.plus),
        '*' => self.one(.star),
        '?' => self.one(.quid),
        '!' => self.one(.bang),
        '.' => self.one(.dot),
        '=' => if (self.peek(1) == '=') self.two(.iden) else self.one(.invalid),
        '~' => if (self.peek(1) == '=') self.two(.cong) else self.one(.invalid),

        // structure
        ',' => self.one(.comma),
        '|' => self.one(.bar),
        '(' => self.one(.l_par),
        ')' => self.one(.r_par),
        '{' => self.one(.l_cur),
        '}' => self.one(.r_cur),

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
            const start = self.index;
            while (self.peek(0) != '\n' and !self.atEnd()) self.index += 1;
            var end = self.index;
            if (end > start and self.source[end - 1] == '\r') end -= 1;
            self.comment = .{ .start = start, .end = end, .token = undefined };
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
/// Attribute names may also contain `-` (`:label-start`).
fn name(self: *Lexer, tag: Tag, allow_hyphen: bool) Tag {
    self.index += 1;
    while (true) {
        const c = self.peek(0);
        if (isNameBody(c) or (allow_hyphen and c == '-')) self.index += 1 else return tag;
    }
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

/// At `[`: a value, `[red]`, `[0..*/1]`, `[/dashed/>]`, `[]`, is one token
/// up to the first `]`. Its contents are read later, by the attribute that
/// takes it. Whitespace, a `[`, a missing `]`, or fAB's own grouping, `(`,
/// `)` and `,`, make the `[` invalid: a bracket never holds an expression
/// (statements.md §22.8).
fn value(self: *Lexer) Tag {
    var i = self.index + 1;
    while (true) : (i += 1) switch (self.at(i)) {
        ']' => {
            self.index = i + 1;
            return .val;
        },
        0, ' ', '\t', '\r', '\n', '[', '(', ')', ',' => break,
        else => {},
    };
    return self.one(.invalid);
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

fn isLower(c: u8) bool {
    return c >= 'a' and c <= 'z';
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

/// Letters, digits, `_`, `'`, and any non-ASCII byte, so UTF-8 names like `α`
/// lex as one name without Unicode tables.
fn isNameBody(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '\'' or c >= 0x80;
}

test {
    _ = @import("lex.test.zig");
}
