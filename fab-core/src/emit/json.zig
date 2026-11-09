//! A compilation as JSON: the core's output contract.
//!
//! The JSON is lossless: it holds the whole IR and every diagnostic, so the
//! IR can be rebuilt from it. Views of the diagram (SVG, DOT, tikz-cd, …) are
//! not made here; they belong to renderers and transpilers.
//!
//! Names are written without sigils (statements.md §22.13): where a name
//! stands says its sort, so the node `#A` is "A", the class `&node` "node",
//! the descriptor `:label` "label". Diagnostics quote the source as written.
//!
//! Format, version 2. A compilation:
//!
//!   { "version": 2,
//!     "status": "ok" | "warning" | "promoted" | "error",
//!     "diagnostics": [Diagnostic],
//!     "ir": IR | null,                null when the tolerance withholds it
//!     "sheet": Sheet | null }         null when "ir" is
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
//!     { "zones": [{"name": "G", "own": null | node, "placeholder": false}],
//!       "nodes": [{"kind": "plain" | "choice" | "parallel" | "null_node" | "hole",
//!                  "name": null | "A", "zone": zone,
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
//!   Sheet: every element's style, resolved (statements.md §22.12). A rule
//!   holds what a set of classes makes; an element names its rule and holds
//!   only its own entries, which win over the rule's, and those over its
//!   parent's.
//!     { "rules": [{"zone": null | zone, "classes": ["node", "plain"],
//!                  "parent": null | rule, "style": Style}],
//!                                       a base rule, [base]'s, has no zone and
//!                                       no parent; a diagram's names its base
//!                                       rule, written before it, and holds what
//!                                       differs from it (statements.md §22.14)
//!       "nodes" | "edges" | "cells" | "zones":
//!               [{"rule": rule, "style": Style,
//!                 "mark": null | "unsupported" | "warning" | "error"}],
//!                                       indexed as the IR's tables
//!       "tokens": {"base": {"ink": Value, …}, "zones": [{"ink": Value, …}]} }
//!
//!   Style: descriptors in :Style's order, each with the layer that bound it.
//!     { "label": {"layer": "computed" | "base" | "theme" | "program" | "mark",
//!                 "value": Value}, … }
//!
//!   Value:
//!     null | true | false | [Value]            nil, a flag, elements
//!     {"text": "…"}  {"math": "…"}  {"color": "#rrggbbaa"}
//!     {"number": "0.85"}  {"range": ["1", "2" | null]}    normal forms
//!     {"label": "circle", "inverted": false}
//!
//! Tokens, for syntax highlighting:
//!
//!   { "version": 2, "tokens": [{"tag": "edge_id", "bytes": [s, e], "utf16": [s, e]}] }
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
const Sheet = @import("../style/Sheet.zig");
const decoded = @import("../analyse/decoded.zig");
const Decimal = @import("../analyse/Decimal.zig");

const Writer = std.Io.Writer;

pub const version = 2;

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
    try w.writeAll(",\"sheet\":");
    if (try c.sheet()) |s| try writeSheet(s, w) else try w.writeAll("null");
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
    for (ir.zones.items(.name), ir.zones.items(.own), ir.zones.items(.placeholder), 0..) |name, own, placeholder, i| {
        if (i > 0) try w.writeByte(',');
        try w.writeAll("{\"name\":");
        try string(w, ir.string(name));
        try w.writeAll(",\"own\":");
        try optionalIndex(w, own);
        try w.print(",\"placeholder\":{}", .{placeholder});
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

fn writeSheet(s: *const Sheet, w: *Writer) Writer.Error!void {
    try w.writeAll("{\"rules\":[");
    for (s.rules, 0..) |r, i| {
        if (i > 0) try w.writeByte(',');
        try w.writeAll("{\"zone\":");
        try optionalIndex(w, r.zone);
        try w.writeAll(",\"classes\":[");
        var it = r.classes.iterator();
        var first = true;
        while (it.next()) |class| : (first = false) {
            if (!first) try w.writeByte(',');
            try string(w, @tagName(class));
        }
        try w.writeAll("],\"parent\":");
        try optionalIndex(w, r.parent);
        try w.writeAll(",\"style\":");
        try writeStyle(s, s.slice(r.entries), w);
        try w.writeByte('}');
    }
    try w.writeByte(']');
    inline for (.{ "nodes", "edges", "cells", "zones" }) |table| {
        try w.print(",\"{s}\":[", .{table});
        for (@field(s.elements, table), 0..) |e, i| {
            if (i > 0) try w.writeByte(',');
            try w.print("{{\"rule\":{d},\"style\":", .{@backingInt(e.rule)});
            try writeStyle(s, s.slice(e.own), w);
            try w.writeAll(",\"mark\":");
            if (e.mark) |m| try string(w, @tagName(m)) else try w.writeAll("null");
            try w.writeByte('}');
        }
        try w.writeByte(']');
    }
    try w.writeAll(",\"tokens\":{\"base\":");
    try writeTokenMap(s.base_tokens, w);
    try w.writeAll(",\"zones\":[");
    for (s.tokens, 0..) |tokens, i| {
        if (i > 0) try w.writeByte(',');
        try writeTokenMap(tokens, w);
    }
    try w.writeAll("]}}");
}

fn writeStyle(s: *const Sheet, entries: []const Sheet.Entry, w: *Writer) Writer.Error!void {
    try w.writeByte('{');
    for (entries, 0..) |e, i| {
        if (i > 0) try w.writeByte(',');
        try string(w, unsigiled(s.descriptors[@backingInt(e.descriptor)]));
        try w.writeAll(":{\"layer\":");
        try string(w, @tagName(e.layer));
        try w.writeAll(",\"value\":");
        try writeValue(e.value, w);
        try w.writeByte('}');
    }
    try w.writeByte('}');
}

fn writeTokenMap(tokens: []const decoded.Token, w: *Writer) Writer.Error!void {
    try w.writeByte('{');
    for (tokens, 0..) |t, i| {
        if (i > 0) try w.writeByte(',');
        try string(w, t.label);
        try w.writeByte(':');
        try writeValue(t.value, w);
    }
    try w.writeByte('}');
}

/// A value, tagged by its shape (statements.md §22.13).
fn writeValue(v: decoded.Value, w: *Writer) Writer.Error!void {
    switch (v) {
        .nil => try w.writeAll("null"),
        .flag => |on| try w.print("{}", .{on}),
        .text => |t| {
            try w.writeAll("{\"text\":");
            try string(w, t);
            try w.writeByte('}');
        },
        .math => |m| {
            try w.writeAll("{\"math\":");
            try string(w, m);
            try w.writeByte('}');
        },
        .color => |c| try w.print("{{\"color\":\"#{x:0>2}{x:0>2}{x:0>2}{x:0>2}\"}}", .{ c.r, c.g, c.b, c.a }),
        .number => |n| {
            try w.writeAll("{\"number\":");
            try number(n, w);
            try w.writeByte('}');
        },
        .range => |r| {
            try w.writeAll("{\"range\":[");
            try number(r.lo, w);
            try w.writeByte(',');
            if (r.hi) |hi| try number(hi, w) else try w.writeAll("null");
            try w.writeAll("]}");
        },
        .label => |l| {
            try w.writeAll("{\"label\":");
            try string(w, l.name);
            try w.print(",\"inverted\":{}}}", .{l.inverted});
        },
        .elements => |es| {
            try w.writeByte('[');
            for (es, 0..) |e, i| {
                if (i > 0) try w.writeByte(',');
                try writeValue(e, w);
            }
            try w.writeByte(']');
        },
        // Only `:theme` takes a record, and it is no element's style.
        .record => unreachable,
    }
}

/// A number in its normal form, as a string: `"0.85"`.
fn number(n: Decimal, w: *Writer) Writer.Error!void {
    try w.writeByte('"');
    try n.format(w);
    try w.writeByte('"');
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
