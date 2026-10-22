//! A compilation as JSON: the core's output contract.
//!
//! The JSON is lossless: it holds the whole IR and every diagnostic, so the
//! IR can be rebuilt from it. Views of the diagram (SVG, DOT, tikz-cd, …) are
//! not made here; they belong to renderers and transpilers.
//!
//! Format, version 1. A compilation:
//!
//!   { "version": 1,
//!     "status": "ok" | "warning" | "promoted" | "error",
//!     "diagnostics": [Diagnostic],
//!     "ir": IR | null }               null when the tolerance withholds it
//!
//!   Diagnostic:
//!     { "code": "edge_declared_twice",
//!       "stage": "syntax" | "analysis",
//!       "severity": "warning" | "promoted" | "error",
//!       "span": Span, "related": Span | null,
//!       "message": "…", "explanation": "…", "hint": "…" }
//!
//!   Span: a piece of the source, in three forms.
//!     { "bytes": [start, end],         byte offsets, end exclusive
//!       "utf16": [start, end],         UTF-16 offsets, as JavaScript indexes
//!       "range": { "start": {"line": 0, "character": 4},
//!                  "end":   {"line": 0, "character": 5} } }
//!     Lines and characters count from 0, characters in UTF-16 code units,
//!     as in the Language Server Protocol. Lines end at "\n".
//!
//!   IR: the tables of Ir.zig. Every reference is an index into a table.
//!     { "zones": [{"name": "G", "own": null | node}],
//!       "nodes": [{"kind": "plain" | "choice" | "parallel" | "null_node" | "hole",
//!                  "name": null | "#A", "zone": zone,
//!                  "canonical": null | {"edge": edge, "side": "dom" | "cod"}}],
//!       "edges": [{"name": "f", "source": node, "target": node,
//!                  "directed": true, "zone": zone}],
//!       "cells": [{"name": "α", "source": edge, "target": edge, "zone": zone}],
//!       "issues": [{"subject": {"node" | "edge" | "cell" | "zone": index},
//!                   "diagnostic": index into "diagnostics"}] }
//!
//! Tokens, for syntax highlighting:
//!
//!   { "version": 1, "tokens": [{"tag": "edge_id", "bytes": [s, e], "utf16": [s, e]}] }
//!
//! Strings are UTF-8. Bytes in the source that are not valid UTF-8 are
//! written as U+FFFD.

const std = @import("std");
const Token = @import("../lex/Token.zig");
const Ir = @import("../analyse/Ir.zig");
const Compilation = @import("../compile/Compilation.zig");
const Diagnostic = @import("../compile/Diagnostic.zig");
const messages = @import("../compile/messages.zig");

const Writer = std.Io.Writer;

pub const version = 1;

pub const Error = Writer.Error || error{OutOfMemory};

/// Writes the whole compilation: status, diagnostics and IR.
pub fn writeCompilation(c: *Compilation, w: *Writer) Error!void {
    const status = try c.status();
    const diagnostics = try c.diagnostics();
    const ir = try c.ir();
    var lines = try Lines.init(c.gpa, c.source);
    defer lines.deinit(c.gpa);

    try w.print("{{\"version\":{d},\"status\":", .{version});
    try string(w, @tagName(status));
    try w.writeAll(",\"diagnostics\":[");
    for (diagnostics, 0..) |d, i| {
        if (i > 0) try w.writeByte(',');
        try writeDiagnostic(c, &lines, d, w);
    }
    try w.writeAll("],\"ir\":");
    if (ir) |graph| try writeIr(c, graph, w) else try w.writeAll("null");
    try w.writeByte('}');
}

/// Writes the tokens, `eol` and `eof` included.
pub fn writeTokens(c: *Compilation, w: *Writer) Error!void {
    const tokens = try c.tokens();
    var lines = try Lines.init(c.gpa, c.source);
    defer lines.deinit(c.gpa);

    try w.print("{{\"version\":{d},\"tokens\":[", .{version});
    for (tokens.items(.tag), tokens.items(.start), tokens.items(.end), 0..) |tag, start, end, i| {
        if (i > 0) try w.writeByte(',');
        try w.writeAll("{\"tag\":");
        try string(w, @tagName(tag));
        try w.print(",\"bytes\":[{d},{d}],\"utf16\":[{d},{d}]}}", .{ start, end, lines.utf16(start), lines.utf16(end) });
    }
    try w.writeAll("]}");
}

fn writeDiagnostic(c: *Compilation, lines: *const Lines, d: Diagnostic, w: *Writer) Error!void {
    try w.writeAll("{\"code\":");
    try string(w, d.code.name());
    try w.writeAll(",\"stage\":");
    try string(w, @tagName(d.code));
    try w.writeAll(",\"severity\":");
    try string(w, @tagName(d.severity));
    try w.writeAll(",\"span\":");
    try writeSpan(lines, d.span, w);
    try w.writeAll(",\"related\":");
    if (d.related) |related| try writeSpan(lines, related, w) else try w.writeAll("null");
    inline for (.{ .message, .explanation, .hint }) |layer| {
        try w.print(",\"{s}\":", .{@tagName(layer)});
        var text: Writer.Allocating = .init(c.gpa);
        defer text.deinit();
        try d.write(layer, c.source, &text.writer);
        try string(w, text.written());
    }
    try w.writeByte('}');
}

fn writeSpan(lines: *const Lines, span: Diagnostic.Span, w: *Writer) Writer.Error!void {
    const start = lines.position(span.start);
    const end = lines.position(span.end);
    try w.print(
        "{{\"bytes\":[{d},{d}],\"utf16\":[{d},{d}],\"range\":{{\"start\":{{\"line\":{d},\"character\":{d}}},\"end\":{{\"line\":{d},\"character\":{d}}}}}}}",
        .{ span.start, span.end, lines.utf16(span.start), lines.utf16(span.end), start.line, start.character, end.line, end.character },
    );
}

fn writeIr(c: *Compilation, ir: *const Ir, w: *Writer) Error!void {
    try w.writeAll("{\"zones\":[");
    for (ir.zones.items(.name), ir.zones.items(.own), 0..) |name, own, i| {
        if (i > 0) try w.writeByte(',');
        try w.writeAll("{\"name\":");
        try string(w, ir.string(name));
        try w.writeAll(",\"own\":");
        try optionalIndex(w, own);
        try w.writeByte('}');
    }

    try w.writeAll("],\"nodes\":[");
    for (0..ir.nodes.len) |i| {
        const node = ir.nodes.get(i);
        if (i > 0) try w.writeByte(',');
        try w.writeAll("{\"kind\":");
        try string(w, @tagName(node.kind));
        try w.writeAll(",\"name\":");
        if (node.name) |name| try string(w, ir.string(name)) else try w.writeAll("null");
        try w.print(",\"zone\":{d},\"canonical\":", .{@backingInt(node.zone)});
        if (node.canonical) |end| {
            try w.print("{{\"edge\":{d},\"side\":\"{s}\"}}", .{ @backingInt(end.edge), @tagName(end.side) });
        } else try w.writeAll("null");
        try w.writeByte('}');
    }

    try w.writeAll("],\"edges\":[");
    for (0..ir.edges.len) |i| {
        const edge = ir.edges.get(i);
        if (i > 0) try w.writeByte(',');
        try w.writeAll("{\"name\":");
        try string(w, ir.string(edge.name));
        try w.print(",\"source\":{d},\"target\":{d},\"directed\":{},\"zone\":{d}}}", .{
            @backingInt(edge.source), @backingInt(edge.target), edge.directed, @backingInt(edge.zone),
        });
    }

    try w.writeAll("],\"cells\":[");
    for (0..ir.cells.len) |i| {
        const cell = ir.cells.get(i);
        if (i > 0) try w.writeByte(',');
        try w.writeAll("{\"name\":");
        try string(w, ir.string(cell.name));
        try w.print(",\"source\":{d},\"target\":{d},\"zone\":{d}}}", .{
            @backingInt(cell.source), @backingInt(cell.target), @backingInt(cell.zone),
        });
    }

    try w.writeAll("],\"issues\":[");
    for (0..ir.issues.len) |i| {
        const issue = ir.issues.get(i);
        if (i > 0) try w.writeByte(',');
        const kind, const index: u32 = switch (issue.subject) {
            .node => |x| .{ "node", @backingInt(x) },
            .edge => |x| .{ "edge", @backingInt(x) },
            .cell => |x| .{ "cell", @backingInt(x) },
            .zone => |x| .{ "zone", @backingInt(x) },
        };
        try w.print("{{\"subject\":{{\"{s}\":{d}}},\"diagnostic\":{d}}}", .{ kind, index, try c.diagnosticIndex(issue) });
    }
    try w.writeAll("]}");
}

fn optionalIndex(w: *Writer, index: anytype) Writer.Error!void {
    if (index) |x| try w.print("{d}", .{@backingInt(x)}) else try w.writeAll("null");
}

/// Writes `s` as a JSON string. Invalid UTF-8 becomes U+FFFD.
pub fn string(w: *Writer, s: []const u8) Writer.Error!void {
    try w.writeByte('"');
    var i: usize = 0;
    while (i < s.len) {
        const c = s[i];
        if (c < 0x80) {
            switch (c) {
                '"' => try w.writeAll("\\\""),
                '\\' => try w.writeAll("\\\\"),
                '\n' => try w.writeAll("\\n"),
                '\r' => try w.writeAll("\\r"),
                '\t' => try w.writeAll("\\t"),
                0x08 => try w.writeAll("\\b"),
                0x0c => try w.writeAll("\\f"),
                0...0x07, 0x0b, 0x0e...0x1f => try w.print("\\u{x:0>4}", .{c}),
                else => try w.writeByte(c),
            }
            i += 1;
            continue;
        }
        const len = utf8Length(s[i..]);
        if (len == 0) {
            try w.writeAll("\\ufffd");
            i += 1;
        } else {
            try w.writeAll(s[i .. i + len]);
            i += len;
        }
    }
    try w.writeByte('"');
}

/// The length of the valid UTF-8 sequence at the start of `s`, or 0.
fn utf8Length(s: []const u8) usize {
    const len = std.unicode.utf8ByteSequenceLength(s[0]) catch return 0;
    if (len > s.len) return 0;
    _ = std.unicode.utf8Decode(s[0..len]) catch return 0;
    return len;
}

/// Converts byte offsets into UTF-16 offsets and LSP positions.
pub const Lines = struct {
    source: []const u8,
    /// The byte offset where each line starts.
    starts: []const u32,
    /// The UTF-16 offset where each line starts.
    utf16_starts: []const u32,

    pub const Position = struct { line: u32, character: u32 };

    pub fn init(gpa: std.mem.Allocator, source: []const u8) error{OutOfMemory}!Lines {
        var starts: std.ArrayList(u32) = .empty;
        defer starts.deinit(gpa);
        var utf16_starts: std.ArrayList(u32) = .empty;
        defer utf16_starts.deinit(gpa);

        try starts.append(gpa, 0);
        try utf16_starts.append(gpa, 0);
        var units: u32 = 0;
        var i: usize = 0;
        while (i < source.len) {
            const step, const width = unitAt(source, i);
            i += step;
            units += width;
            if (source[i - step] == '\n') {
                try starts.append(gpa, @intCast(i));
                try utf16_starts.append(gpa, units);
            }
        }
        const owned_starts = try starts.toOwnedSlice(gpa);
        errdefer gpa.free(owned_starts);
        return .{ .source = source, .starts = owned_starts, .utf16_starts = try utf16_starts.toOwnedSlice(gpa) };
    }

    pub fn deinit(lines: *Lines, gpa: std.mem.Allocator) void {
        gpa.free(lines.starts);
        gpa.free(lines.utf16_starts);
        lines.* = undefined;
    }

    /// The line and UTF-16 character of a byte offset.
    pub fn position(lines: *const Lines, offset: u32) Position {
        const line = lines.lineOf(offset);
        return .{ .line = line, .character = lines.unitsBetween(lines.starts[line], offset) };
    }

    /// The UTF-16 offset of a byte offset.
    pub fn utf16(lines: *const Lines, offset: u32) u32 {
        const line = lines.lineOf(offset);
        return lines.utf16_starts[line] + lines.unitsBetween(lines.starts[line], offset);
    }

    fn lineOf(lines: *const Lines, offset: u32) u32 {
        // The last line starting at or before `offset`.
        var lo: usize = 0;
        var hi: usize = lines.starts.len;
        while (hi - lo > 1) {
            const mid = (lo + hi) / 2;
            if (lines.starts[mid] <= offset) lo = mid else hi = mid;
        }
        return @intCast(lo);
    }

    fn unitsBetween(lines: *const Lines, from: u32, to: u32) u32 {
        var units: u32 = 0;
        var i: usize = from;
        while (i < to) {
            const step, const width = unitAt(lines.source, i);
            i += step;
            units += width;
        }
        return units;
    }

    /// The bytes and UTF-16 units of the character at `i`. An invalid byte
    /// counts as one byte and one unit, as U+FFFD does.
    fn unitAt(source: []const u8, i: usize) struct { usize, u32 } {
        const len = utf8Length(source[i..]);
        if (len == 0) return .{ 1, 1 };
        return .{ len, if (len == 4) 2 else 1 };
    }
};

test {
    _ = @import("json.test.zig");
}
