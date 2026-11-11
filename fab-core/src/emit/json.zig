//! A compilation as JSON: the core's output contract.
//!
//! The JSON is fab-core's analysis, and nothing else (statements.md §26): the
//! whole IR and every diagnostic, so the IR can be rebuilt from it. No
//! layer's result is written: the Sheet stays in memory, where renderers
//! read it. Views of the diagram (SVG, DOT, tikz-cd, …) are not made here;
//! they belong to renderers and transpilers.
//!
//! Names are written without sigils (statements.md §22.13): where a name
//! stands says its sort, so the node `#A` is "A". Diagnostics quote the
//! source as written.
//!
//! Format, version 1. It stays 1 while the language is being formalised,
//! however the format changes (release.md §3). A compilation:
//!
//!   { "format": 1,
//!     "version": "0.1.0-dev.97+e3ee815",   the build (release.md §2)
//!     "status": "ok" | "warning" | "promoted" | "error",
//!     "diagnostics": [Diagnostic],
//!     "ir": IR | null }               null when the tolerance withholds it
//!
//!   Diagnostic:
//!     { "code": "edge_declared_twice",
//!       "stage": "syntax" | "analysis",
//!       "severity": "unsupported" | "warning" | "promoted" | "error",
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
//!     { "zones": [{"name": "G", "container": null | zone, "members": [zone],
//!                  "placeholder": false}],             members in naming order
//!       "nodes": [{"kind": "plain" | "choice" | "parallel" | "null_node" | "hole",
//!                  "name": null | "A", "zone": zone, "diagram": null | zone,
//!                  "canonical": null | {"edge": edge, "side": "dom" | "cod"}}],
//!       "edges": [{"name": "f", "source": node, "target": node,
//!                  "directed": true, "zone": zone}],
//!       "cells": [{"name": "α", "level": 2,
//!                  "source": {"node" | "edge" | "cell": index},
//!                  "target": {"node" | "edge" | "cell": index},
//!                  "directed": true, "zone": zone}],
//!       "issues": [{"subject": {"node" | "edge" | "cell" | "zone": index},
//!                   "diagnostic": index into "diagnostics"}] }
//!
//! Tokens, for syntax highlighting:
//!
//!   { "format": 1, "version": "…", "tokens": [{"tag": "edge_id", "bytes": [s, e], "utf16": [s, e]}] }
//!
//! Strings are UTF-8. Bytes in the source that are not valid UTF-8 are
//! written as U+FFFD.

const std = @import("std");
const Token = @import("../lex/Token.zig");
const Ir = @import("../analyse/Ir.zig");
const Compilation = @import("../compile/Compilation.zig");
const Diagnostic = @import("../compile/Diagnostic.zig");
const messages = @import("../compile/messages.zig");
const Lines = @import("../compile/Lines.zig");
const build = @import("../version.zig");

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

    try w.print("{{\"format\":{d},\"version\":\"{s}\",\"status\":", .{ version, build.string });
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

    try w.print("{{\"format\":{d},\"version\":\"{s}\",\"tokens\":[", .{ version, build.string });
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
    for (ir.zones.items(.name), ir.zones.items(.container), ir.zones.items(.placeholder), 0..) |name, container, placeholder, i| {
        if (i > 0) try w.writeByte(',');
        try w.writeAll("{\"name\":");
        try string(w, ir.string(name));
        try w.writeAll(",\"container\":");
        try optionalIndex(w, container);
        try w.writeAll(",\"members\":[");
        var first = true;
        for (ir.members.items(.container), ir.members.items(.member)) |holder, m| {
            if (@backingInt(holder) != i) continue;
            if (!first) try w.writeByte(',');
            first = false;
            try w.print("{d}", .{@backingInt(m)});
        }
        try w.print("],\"placeholder\":{}", .{placeholder});
        try w.writeByte('}');
    }

    try w.writeAll("],\"nodes\":[");
    for (0..ir.nodes.len) |i| {
        const node = ir.nodes.get(i);
        if (i > 0) try w.writeByte(',');
        try w.writeAll("{\"kind\":");
        try string(w, @tagName(node.kind));
        try w.writeAll(",\"name\":");
        if (node.name) |name| try string(w, unsigiled(ir.string(name))) else try w.writeAll("null");
        try w.print(",\"zone\":{d},\"diagram\":", .{@backingInt(node.zone)});
        try optionalIndex(w, node.diagram);
        try w.writeAll(",\"canonical\":");
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
        try w.print(",\"level\":{d},\"source\":", .{cell.level});
        try side(w, cell.source);
        try w.writeAll(",\"target\":");
        try side(w, cell.target);
        try w.print(",\"directed\":{},\"zone\":{d}}}", .{ cell.directed, @backingInt(cell.zone) });
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

/// A name as JSON writes it: `#A` is "A", `:label` "label".
fn unsigiled(name: []const u8) []const u8 {
    return if (name.len > 0 and (name[0] == '#' or name[0] == ':')) name[1..] else name;
}

/// A cell's side: `{"edge": 3}`.
fn side(w: *Writer, s: Ir.Cell.Side) Writer.Error!void {
    const kind, const index: u32 = switch (s) {
        .node => |x| .{ "node", @backingInt(x) },
        .edge => |x| .{ "edge", @backingInt(x) },
        .cell => |x| .{ "cell", @backingInt(x) },
    };
    try w.print("{{\"{s}\":{d}}}", .{ kind, index });
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
        const len = Lines.utf8Length(s[i..]);
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

test {
    _ = @import("json.test.zig");
}
