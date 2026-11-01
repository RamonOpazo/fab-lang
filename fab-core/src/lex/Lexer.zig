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
        '"' => self.delimited('"', .str),
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
        '(' => self.one(.l_par),
        ')' => self.one(.r_par),
        ']' => self.one(.r_brack),
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

test {
    _ = @import("lex.test.zig");
}
