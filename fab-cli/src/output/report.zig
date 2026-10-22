//! Diagnostics for the terminal. Pure: writes to a Writer.
//!
//!   error: Edge `k` is not declared before this point
//!     --> diagram.fab:1:11
//!      |
//!    1 | G :: f g/+k h
//!      |           ^
//!      = why: References point left: …          (full only)
//!      = hint: Declare `k` earlier, or …        (full only)
//!
//! Columns count characters (code points) from 1. Colours are red for
//! errors, magenta for promoted warnings and yellow for warnings.

const std = @import("std");
const fab = @import("fab_core");
const Note = @import("fab_render").Note;
const Command = @import("../command/Args.zig").Command;

const Diagnostic = fab.Diagnostic;
const Writer = std.Io.Writer;

pub const Options = struct {
    verbosity: Command.Verbosity,
    color: bool,
    /// How the input is named in locations: its path, or "<stdin>".
    path: []const u8,
};

/// Writes every diagnostic, then a one-line summary. Writes nothing for
/// quiet verbosity, or when there are no diagnostics.
pub fn write(w: *Writer, source: []const u8, diagnostics: []const Diagnostic, options: Options) Writer.Error!void {
    if (options.verbosity == .quiet or diagnostics.len == 0) return;
    for (diagnostics) |d| try writeOne(w, source, d, options);
    try writeSummary(w, diagnostics, options);
}

fn writeOne(w: *Writer, source: []const u8, d: Diagnostic, o: Options) Writer.Error!void {
    const main = locate(source, d.span.start);
    const related = if (o.verbosity == .full) if (d.related) |r| locate(source, r.start) else null else null;
    const gutter = digits(@max(main.line, if (related) |r| r.line else 0));

    // error: message
    try style(w, o, severityColor(d.severity));
    try style(w, o, bold);
    try w.writeAll(severityLabel(d.severity));
    try style(w, o, reset);
    try style(w, o, bold);
    try w.writeAll(": ");
    try d.write(.message, source, w);
    try style(w, o, reset);
    try w.writeByte('\n');

    try writeExcerpt(w, source, d.span, main, gutter, '^', severityColor(d.severity), o);

    if (o.verbosity == .full) {
        if (d.related) |r| {
            try writeNote(w, gutter, "note", o);
            try w.writeAll("first declared here\n");
            try writeExcerpt(w, source, r, related.?, gutter, '-', blue, o);
        }
        try writeNote(w, gutter, "why", o);
        try d.write(.explanation, source, w);
        try w.writeByte('\n');
        try writeNote(w, gutter, "hint", o);
        try d.write(.hint, source, w);
        try w.writeByte('\n');
    }
    try w.writeByte('\n');
}

/// `  --> path:line:column`, then the source line with a mark under the span.
fn writeExcerpt(w: *Writer, source: []const u8, span: Diagnostic.Span, at: Location, gutter: usize, mark: u8, mark_color: []const u8, o: Options) Writer.Error!void {
    try pad(w, gutter);
    try style(w, o, blue);
    try w.writeAll("--> ");
    try style(w, o, reset);
    try w.print("{s}:{d}:{d}\n", .{ o.path, at.line, at.column });

    try pad(w, gutter + 1);
    try style(w, o, blue);
    try w.writeAll("|\n");
    try w.print("{d: >[1]} | ", .{ at.line, gutter });
    try style(w, o, reset);
    try w.writeAll(source[at.line_start..at.line_end]);
    try w.writeByte('\n');

    try pad(w, gutter + 1);
    try style(w, o, blue);
    try w.writeAll("| ");
    try style(w, o, reset);
    // Copy tabs, so the mark lines up however the terminal expands them.
    const mark_start = @min(span.start, at.line_end);
    var i = at.line_start;
    while (i < mark_start) {
        if (source[i] == '\t') try w.writeByte('\t') else try w.writeByte(' ');
        i += charLength(source[i..]);
    }
    const mark_end = @min(span.end, at.line_end);
    const width = @max(1, codePoints(source[mark_start..mark_end]));
    try style(w, o, mark_color);
    try w.splatByteAll(mark, width);
    try style(w, o, reset);
    try w.writeByte('\n');
}

fn writeNote(w: *Writer, gutter: usize, label: []const u8, o: Options) Writer.Error!void {
    try pad(w, gutter + 1);
    try style(w, o, blue);
    try w.writeAll("= ");
    try style(w, o, reset);
    try style(w, o, bold);
    try w.print("{s}: ", .{label});
    try style(w, o, reset);
}

fn writeSummary(w: *Writer, diagnostics: []const Diagnostic, o: Options) Writer.Error!void {
    var counts = [_]usize{ 0, 0, 0 };
    for (diagnostics) |d| counts[@backingInt(d.severity)] += 1;
    const parts = [_]struct { usize, []const u8, []const u8, Diagnostic.Severity }{
        .{ counts[@backingInt(Diagnostic.Severity.@"error")], "error", "errors", .@"error" },
        .{ counts[@backingInt(Diagnostic.Severity.promoted)], "promoted warning", "promoted warnings", .promoted },
        .{ counts[@backingInt(Diagnostic.Severity.warning)], "warning", "warnings", .warning },
    };
    var first = true;
    for (parts) |part| {
        const n, const one, const many, const severity = part;
        if (n == 0) continue;
        if (!first) try w.writeAll(", ");
        first = false;
        try style(w, o, severityColor(severity));
        try style(w, o, bold);
        try w.print("{d} {s}", .{ n, if (n == 1) one else many });
        try style(w, o, reset);
    }
    try w.writeByte('\n');
}

// ---------------------------------------------------------------------------
// Notes: what the engine drew less than fully. Not diagnostics: they never
// change the exit code, and they come after the summary.
//
//   note: cells are not drawn by the graphviz engine (×2)     brief
//   note: cells are not drawn by the graphviz engine (cell 0)  full, one each

pub fn writeNotes(w: *Writer, notes: []const Note, o: Options) Writer.Error!void {
    if (o.verbosity == .quiet) return;
    if (o.verbosity == .full) {
        for (notes) |n| {
            try noteLabel(w, o);
            try w.writeAll(n.message());
            if (n.subject) |subject| {
                const kind, const index = switch (subject) {
                    inline else => |i, tag| .{ @tagName(tag), @backingInt(i) },
                };
                try w.print(" ({s} {d})", .{ kind, index });
            }
            try w.writeByte('\n');
        }
        return;
    }
    // Brief: one line per kind of note, in order of first appearance.
    for (notes, 0..) |n, i| {
        var seen = false;
        for (notes[0..i]) |earlier| seen = seen or earlier.tag == n.tag;
        if (seen) continue;
        var count: usize = 0;
        for (notes[i..]) |later| count += @intFromBool(later.tag == n.tag);
        try noteLabel(w, o);
        try w.writeAll(n.message());
        if (count > 1) try w.print(" (×{d})", .{count});
        try w.writeByte('\n');
    }
}

fn noteLabel(w: *Writer, o: Options) Writer.Error!void {
    try style(w, o, cyan);
    try style(w, o, bold);
    try w.writeAll("note");
    try style(w, o, reset);
    try style(w, o, bold);
    try w.writeAll(": ");
    try style(w, o, reset);
}

// ---------------------------------------------------------------------------
// Locations

pub const Location = struct {
    /// From 1.
    line: usize,
    /// From 1, in characters.
    column: usize,
    /// The line's bytes, without its line break.
    line_start: usize,
    line_end: usize,
};

pub fn locate(source: []const u8, offset: usize) Location {
    var line: usize = 1;
    var line_start: usize = 0;
    for (source[0..offset], 0..) |c, i| {
        if (c == '\n') {
            line += 1;
            line_start = i + 1;
        }
    }
    var line_end = std.mem.indexOfScalarPos(u8, source, line_start, '\n') orelse source.len;
    if (line_end > line_start and source[line_end - 1] == '\r') line_end -= 1;
    return .{
        .line = line,
        .column = codePoints(source[line_start..@min(offset, line_end)]) + 1 + (offset -| line_end),
        .line_start = line_start,
        .line_end = line_end,
    };
}

fn codePoints(s: []const u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < s.len) : (n += 1) i += charLength(s[i..]);
    return n;
}

/// The length of the character at the start of `s`; an invalid byte is one.
fn charLength(s: []const u8) usize {
    const len = std.unicode.utf8ByteSequenceLength(s[0]) catch return 1;
    return if (len <= s.len) len else 1;
}

fn digits(n: usize) usize {
    var d: usize = 1;
    var x = n;
    while (x >= 10) : (x /= 10) d += 1;
    return d;
}

fn pad(w: *Writer, n: usize) Writer.Error!void {
    try w.splatByteAll(' ', n);
}

// ---------------------------------------------------------------------------
// Colour

const reset = "\x1b[0m";
const bold = "\x1b[1m";
const blue = "\x1b[34m";
const cyan = "\x1b[36m";

fn style(w: *Writer, o: Options, code: []const u8) Writer.Error!void {
    if (o.color) try w.writeAll(code);
}

fn severityColor(s: Diagnostic.Severity) []const u8 {
    return switch (s) {
        .@"error" => "\x1b[31m",
        .promoted => "\x1b[35m",
        .warning => "\x1b[33m",
    };
}

fn severityLabel(s: Diagnostic.Severity) []const u8 {
    return switch (s) {
        .@"error" => "error",
        .promoted => "promoted warning",
        .warning => "warning",
    };
}

test {
    _ = @import("report.test.zig");
}
