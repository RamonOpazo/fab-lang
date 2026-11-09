//! Formatting (plan step L4d): the document in its canonical layout, as
//! `fab fmt` prints it. One edit replaces the whole text, or none when it is
//! formatted already. The editor's options (tab size, spaces) are ignored:
//! the layout is fAB's own. A document with syntax errors is refused, since
//! the printer would lose what recovery skipped.

const std = @import("std");
const fab = @import("fab_core");
const Message = @import("Message.zig");

pub const Outcome = union(enum) {
    edits: []const Message.TextEdit,
    refused: []const u8,
};

pub fn of(arena: std.mem.Allocator, text: []const u8) error{OutOfMemory}!Outcome {
    const source = try arena.dupeSentinel(u8, text, 0);
    var tree = try fab.Parser.parse(arena, source);
    if (tree.errors.len > 0) return .{ .refused = "the document has syntax errors; fix them to format it" };
    var out: std.Io.Writer.Allocating = .init(arena);
    fab.print.program(arena, &tree, &out.writer) catch |e| switch (e) {
        error.SyntaxError => unreachable, // checked above
        error.OutOfMemory, error.WriteFailed => return error.OutOfMemory,
    };
    if (std.mem.eql(u8, out.written(), text)) return .{ .edits = &.{} };

    var lines = try fab.Lines.init(arena, text);
    const end = lines.position(@intCast(text.len));
    const edit: Message.TextEdit = .{
        .range = .{ .start = .{ .line = 0, .character = 0 }, .end = .{ .line = end.line, .character = end.character } },
        .newText = out.written(),
    };
    return .{ .edits = try arena.dupe(Message.TextEdit, &.{edit}) };
}

test {
    _ = @import("formatting.test.zig");
}
