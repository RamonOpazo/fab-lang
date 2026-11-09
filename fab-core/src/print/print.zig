//! The printer (plan step L4): a program in its canonical layout, from its
//! tree's tokens and comments. It changes whitespace only, so the program
//! means what it meant:
//!
//!   - What touches stays touching, and what doesn't is one space apart:
//!     `f/g`, `+f`, `G.f` and `f (g, h)` are kept as written. Only around
//!     structure, where touching means nothing, is the space decided: none
//!     before a comma or inside parentheses, one after a comma, one around
//!     `::`, `:=`, `|`, `==`, `~=`, and inside braces holding something.
//!   - Line breaks are the author's: each is kept, a run of blank lines
//!     becomes one, and the file ends with one line end.
//!   - A line is indented by what is open at its start, after the closers
//!     it begins with: four spaces per brace or parenthesis alike, and two
//!     fewer when it begins with a comma, so that the item after `, ` lines
//!     up with the one above:
//!
//!       G :: {
//!           f/? +(
//!               a b
//!             , c
//!           )
//!       }
//!
//!   - A comment stays where it was: at the end of its line, one space
//!     after the code, or on a line of its own, indented as the code is.
//!
//! A program with syntax errors is not printed: what recovery skipped would
//! be lost.

const std = @import("std");
const Cst = @import("../parse/Cst.zig");
const Tag = @import("../lex/Token.zig").Tag;
const Writer = std.Io.Writer;

pub const Error = Writer.Error || error{SyntaxError};

/// Writes the program of `cst` in its canonical layout.
pub fn program(cst: *const Cst, w: *Writer) Error!void {
    if (cst.errors.len > 0) return error.SyntaxError;
    const tags = cst.tokens.items(.tag);
    const starts = cst.tokens.items(.start);
    const ends = cst.tokens.items(.end);

    var open: Open = .{};
    // Line ends since something was last printed, and whether anything was.
    var breaks: u32 = 0;
    var printed = false;
    // The last token printed on this line, if any.
    var last: ?usize = null;
    var comment: usize = 0;

    for (tags, 0..) |tag, i| {
        // A comment comes before a line end or the end.
        if (comment < cst.comments.len and cst.comments[comment].token == i) {
            const c = cst.comments[comment];
            comment += 1;
            if (last == null) {
                try newLine(w, &breaks, printed, open.indent(false));
            } else try w.writeByte(' ');
            try w.writeAll(cst.source[c.start..c.end]);
            printed = true;
        }
        switch (tag) {
            .eol => {
                if (printed) breaks += 1;
                last = null;
                continue;
            },
            .eof => break,
            else => {},
        }

        if (last) |l| {
            if (spaced(tags[l], tag, ends[l] == starts[i])) try w.writeByte(' ');
        } else {
            var at_start = open;
            var j = i;
            while (tags[j] == .r_cur or tags[j] == .r_par) : (j += 1) {
                at_start.depth -|= 1;
            }
            try newLine(w, &breaks, printed, at_start.indent(tag == .comma));
        }
        try w.writeAll(cst.source[starts[i]..ends[i]]);
        printed = true;
        last = i;
        switch (tag) {
            .l_cur, .l_par => open.depth += 1,
            .r_cur, .r_par => open.depth -|= 1,
            else => {},
        }
    }
    if (printed) try w.writeByte('\n');
}

/// How many braces and parentheses are open: each indents alike.
const Open = struct {
    depth: u32 = 0,

    fn indent(o: Open, comma: bool) u32 {
        const width = 4 * o.depth;
        return if (comma) width -| 2 else width;
    }
};

/// Begins a line: the breaks before it (one, or two for a blank line), and
/// its indentation.
fn newLine(w: *Writer, breaks: *u32, printed: bool, indent: u32) Writer.Error!void {
    if (printed) try w.splatByteAll('\n', @max(1, @min(breaks.*, 2)));
    breaks.* = 0;
    try w.splatByteAll(' ', indent);
}

/// Whether one space goes between two tokens on a line. Around structure
/// the layout decides; elsewhere touching is meaning, kept as written.
fn spaced(left: Tag, right: Tag, touching: bool) bool {
    if (right == .comma) return false;
    if (left == .comma) return true;
    if (left == .l_par or right == .r_par) return false;
    if (left == .l_cur) return right != .r_cur;
    if (right == .r_cur or right == .l_cur) return true;
    return switch (left) {
        .decl, .defn, .bar, .iden, .cong => true,
        else => switch (right) {
            .decl, .defn, .bar, .iden, .cong => true,
            else => !touching,
        },
    };
}

test {
    _ = @import("print.test.zig");
}
