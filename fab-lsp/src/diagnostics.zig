//! fab-core's diagnostics, then the layers' (statements.md §29: the place
//! layer's), as the protocol's (`textDocument/publishDiagnostics`).
//!
//!   error, promoted   Error (1)
//!   warning           Warning (2)
//!   unsupported       Information (3): read, not drawn, so not a fault
//!
//! The message is the diagnostic's message, then its explanation; the code
//! is its stable name (`edge_declared_twice`); `related` becomes related
//! information in the same document.

const std = @import("std");
const fab = @import("fab_core");
const place = @import("fab_layer_place");
const Message = @import("Message.zig");

/// The diagnostics of `source`, allocated in `arena`.
pub fn of(arena: std.mem.Allocator, uri: []const u8, source: []const u8) error{OutOfMemory}![]Message.Diagnostic {
    var c = try fab.Compilation.init(arena, source, .{ .warnings = .warn, .ir = .keep });
    defer c.deinit();
    var lines = try fab.Lines.init(arena, source);
    defer lines.deinit(arena);

    var all: std.ArrayList(fab.Diagnostic) = .empty;
    try all.appendSlice(arena, try c.diagnostics());
    if (try place.of(arena, &c)) |p| {
        var placed = p;
        defer placed.deinit();
        try all.appendSlice(arena, placed.diagnostics);
    }
    const out = try arena.alloc(Message.Diagnostic, all.items.len);
    for (all.items, out) |d, *o| {
        const related: ?[]const Message.Related = if (d.related) |span| try arena.dupe(Message.Related, &.{.{
            .location = .{ .uri = uri, .range = range(&lines, span) },
            .message = "first here",
        }}) else null;
        o.* = .{
            .range = range(&lines, d.span),
            .severity = severity(d.severity),
            .code = d.code.name(),
            .message = try text(arena, d, source),
            .relatedInformation = related,
        };
    }
    return out;
}

pub fn severity(s: fab.Diagnostic.Severity) u8 {
    return switch (s) {
        .@"error", .promoted => 1,
        .warning => 2,
        .unsupported => 3,
    };
}

fn range(lines: *const fab.Lines, span: fab.Diagnostic.Span) Message.Range {
    const start = lines.position(span.start);
    const end = lines.position(span.end);
    return .{
        .start = .{ .line = start.line, .character = start.character },
        .end = .{ .line = end.line, .character = end.character },
    };
}

/// The message, then the explanation, placeholders filled in.
fn text(arena: std.mem.Allocator, d: fab.Diagnostic, source: []const u8) error{OutOfMemory}![]const u8 {
    var out: std.Io.Writer.Allocating = .init(arena);
    d.write(.message, source, &out.writer) catch return error.OutOfMemory;
    out.writer.writeAll("\n\n") catch return error.OutOfMemory;
    d.write(.explanation, source, &out.writer) catch return error.OutOfMemory;
    return out.written();
}
