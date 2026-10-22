//! A token: its tag and its span in the source.
//!
//! Spans are byte offsets, `start` inclusive and `end` exclusive. Whitespace
//! and comments are never stored: they are exactly the gaps between spans.
//! Two tokens touch when there is no gap, which is how the parser decides
//! whether a tight operator is binary, prefix or postfix.

const Token = @This();

tag: Tag,
start: u32,
end: u32,

pub const Tag = enum(u8) {
    // control
    eof,
    eol,
    invalid,

    // names, classified by their first character only
    zone_id, // Uppercase first:        G, User, T, A'
    node_id, // # then uppercase first: #A, #UUID7
    edge_id, // lowercase, _ or non-ASCII first: f, h', user_id, α, double-circle
    attr_id, // : then lowercase first: :label, :label-start

    // literals
    number, // 20, 0.5, 0xffffff
    string, // "..."
    math, // $...$
    arrow, // [...]: arrow glyphs only, enclosed in brackets, no whitespace

    // operators
    slash, // /
    plus, // +
    star, // *
    quid, // ?
    bang, // !
    at, // @
    dot, // .
    range, // ..
    iden, // == (for identity.)
    cong, // ~= (for congruency.)
    decl, // :: (for any declaration.)
    defn, // := (for any definition.)

    // structure
    comma, // ,
    l_paren, // (
    r_paren, // )
    l_brack, // [
    r_brack, // ]
    l_brace, // {
    r_brace, // }
};

/// The token's text.
pub fn slice(self: Token, source: []const u8) []const u8 {
    return source[self.start..self.end];
}

/// True when `next` begins exactly where `self` ends, with nothing between.
pub fn touches(self: Token, next: Token) bool {
    return self.end == next.start;
}
