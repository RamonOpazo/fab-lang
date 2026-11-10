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
//!     it begins with: four spaces per brace or parenthesis alike, whatever
//!     the line begins with:
//!
//!       G :: {
//!           f/? +(
//!               a b
//!               , c
//!           )
//!       }
//!
//!   - Columns are aligned, always, across a run: consecutive lines of one
//!     indentation, which a blank line, a comment's own line or another
//!     indentation ends. A line's columns are where its descriptor or block
//!     begins after a context (`#A :fill`, `#A { … }`), its `::` or `:=`,
//!     and its comment; each is placed one space after the widest text
//!     before it in the run, a comment two:
//!
//!       Sq   :: +(f h, g k)+  // a square
//!       Iso  :: f/g           // an isomorphism
//!       Endo :: f/f           // an endomorphism
//!
//!     A long line pushes its run's columns: a blank line before it starts
//!     a run of its own.
//!   - A comment stays where it was: at the end of its line, or on a line
//!     of its own, indented as the code is.
//!
//! A program with syntax errors is not printed: what recovery skipped would
//! be lost.

const std = @import("std");
const Cst = @import("../parse/Cst.zig");
const Tag = @import("../lex/Token.zig").Tag;
const Writer = std.Io.Writer;

pub const Error = Writer.Error || error{ SyntaxError, OutOfMemory };

/// Writes the program of `cst` in its canonical layout. `gpa` holds the
/// lines while their columns are aligned.
pub fn program(gpa: std.mem.Allocator, cst: *const Cst, w: *Writer) Error!void {
    if (cst.errors.len > 0) return error.SyntaxError;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const lines = try layOut(arena.allocator(), cst);
    try alignRuns(arena.allocator(), lines);
    for (lines, 0..) |line, i| {
        if (i > 0) try w.splatByteAll('\n', if (line.blank) 2 else 1);
        try w.splatByteAll(' ', line.indent);
        try w.writeAll(line.code.items);
        if (line.comment) |c| {
            if (line.code.items.len > 0) try w.splatByteAll(' ', line.comment_at - width(line.code.items));
            try w.writeAll(c);
        }
    }
    if (lines.len > 0) try w.writeByte('\n');
}

/// One printed line: its code with spaces settled, and where its columns
/// begin in it.
const Line = struct {
    indent: u32,
    /// A blank line before it.
    blank: bool,
    code: std.ArrayList(u8) = .empty,
    /// Byte offsets in `code`: the descriptor or block after the context,
    /// and the `::` or `:=`.
    columns: [2]?u32 = .{ null, null },
    comment: ?[]const u8 = null,
    /// The width the comment is placed at, once aligned.
    comment_at: u32 = 0,
    /// Its first token, and whether its first entry has ended.
    first: usize = 0,
    entered: bool = false,
};

/// The lines of the program, each token placed, columns found but not yet
/// aligned.
fn layOut(arena: std.mem.Allocator, cst: *const Cst) error{OutOfMemory}![]Line {
    const tags = cst.tokens.items(.tag);
    const starts = cst.tokens.items(.start);
    const ends = cst.tokens.items(.end);
    var lines: std.ArrayList(Line) = .empty;

    var depth: u32 = 0;
    // Line ends since the last line was begun.
    var breaks: u32 = 0;
    // The last token placed on this line, if any, and the depth relative to
    // the line's start, where columns are looked for.
    var last: ?usize = null;
    var relative: i32 = 0;
    var comment: usize = 0;

    for (tags, 0..) |tag, i| {
        // A comment comes before a line end or the end.
        if (comment < cst.comments.len and cst.comments[comment].token == i) {
            const c = cst.comments[comment];
            comment += 1;
            if (last == null) try lines.append(arena, .{ .indent = 4 * depth, .blank = breaks >= 2 and lines.items.len > 0 });
            lines.items[lines.items.len - 1].comment = cst.source[c.start..c.end];
            breaks = 0;
        }
        switch (tag) {
            .eol => {
                breaks += 1;
                last = null;
                continue;
            },
            .eof => break,
            else => {},
        }

        if (last == null) {
            var at_start = depth;
            var j = i;
            while (tags[j] == .r_cur or tags[j] == .r_par) : (j += 1) at_start -|= 1;
            try lines.append(arena, .{ .indent = 4 * at_start, .blank = breaks >= 2 and lines.items.len > 0, .first = i });
            breaks = 0;
            relative = 0;
        }
        const line = &lines.items[lines.items.len - 1];
        if (last) |l| {
            if (spaced(tags[l], tag, ends[l] == starts[i])) try line.code.append(arena, ' ');
            // Columns lie at the line's own depth, after its first token, in
            // its first entry: a comma begins another. A descriptor's or a
            // block's needs a context before it, not a descriptor.
            if (relative == 0 and !line.entered) {
                const at: u32 = @intCast(line.code.items.len);
                switch (tag) {
                    .comma => line.entered = true,
                    .attr_id, .l_cur => if (line.columns[0] == null and line.columns[1] == null and tags[line.first] != .attr_id) {
                        line.columns[0] = at;
                    },
                    .decl, .defn, .then => if (line.columns[1] == null) {
                        line.columns[1] = at;
                    },
                    else => {},
                }
            }
        }
        try line.code.appendSlice(arena, cst.source[starts[i]..ends[i]]);
        last = i;
        switch (tag) {
            .l_cur, .l_par => {
                depth += 1;
                relative += 1;
            },
            .r_cur, .r_par => {
                depth -|= 1;
                relative -= 1;
            },
            else => {},
        }
    }
    return lines.items;
}

/// Aligns each run's columns, in order, then its comments.
fn alignRuns(arena: std.mem.Allocator, lines: []Line) error{OutOfMemory}!void {
    var start: usize = 0;
    while (start < lines.len) {
        var end = start + 1;
        if (lines[start].code.items.len > 0) {
            while (end < lines.len and !lines[end].blank and lines[end].code.items.len > 0 and
                lines[end].indent == lines[start].indent) end += 1;
        }
        const run = lines[start..end];
        for (0..2) |k| {
            var column: u32 = 0;
            for (run) |line| if (line.columns[k]) |at| {
                column = @max(column, width(line.code.items[0..at]));
            };
            for (run) |*line| if (line.columns[k]) |at| try pad(arena, line, at, column - width(line.code.items[0..at]));
        }
        var comment_at: u32 = 0;
        for (run) |line| if (line.comment != null) {
            comment_at = @max(comment_at, width(line.code.items) + 2);
        };
        for (run) |*line| line.comment_at = comment_at;
        start = end;
    }
}

/// Inserts `n` spaces at byte `at`, moving the columns after it.
fn pad(arena: std.mem.Allocator, line: *Line, at: u32, n: u32) error{OutOfMemory}!void {
    if (n == 0) return;
    try line.code.insertSlice(arena, at, try arena.alloc(u8, n));
    @memset(line.code.items[at..][0..n], ' ');
    for (&line.columns) |*c| if (c.*) |*col| {
        if (col.* >= at) col.* += n;
    };
}

/// Text width: one column per code point.
fn width(text: []const u8) u32 {
    return @intCast(std.unicode.utf8CountCodepoints(text) catch text.len);
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
        .decl, .defn, .then, .bar, .iden, .cong => true,
        else => switch (right) {
            .decl, .defn, .then, .bar, .iden, .cong => true,
            else => !touching,
        },
    };
}

test {
    _ = @import("print.test.zig");
}
