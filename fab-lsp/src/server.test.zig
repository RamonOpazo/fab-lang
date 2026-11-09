//! A scripted session: messages in, what the server writes out.

const std = @import("std");
const Io = std.Io;
const Server = @import("Server.zig");
const Transport = @import("Transport.zig");

const gpa = std.testing.allocator;

/// Sends each body, then returns the bodies written, in order.
const Session = struct {
    server: Server,
    out: Io.Writer.Allocating,

    fn init() Session {
        return .{ .server = .init(gpa), .out = .init(gpa) };
    }

    fn deinit(s: *Session) void {
        s.server.deinit();
        s.out.deinit();
    }

    fn send(s: *Session, body: []const u8) !void {
        try s.server.handle(body, &s.out.writer);
    }

    /// The messages written since the last call, parsed, owned by `arena`.
    fn received(s: *Session, arena: std.mem.Allocator) ![]std.json.Value {
        var r: Io.Reader = .fixed(s.out.written());
        var list: std.ArrayList(std.json.Value) = .empty;
        while (try Transport.read(arena, &r)) |body| {
            try list.append(arena, try std.json.parseFromSliceLeaky(std.json.Value, arena, body, .{}));
        }
        s.out.clearRetainingCapacity();
        return list.items;
    }
};

fn field(v: std.json.Value, path: []const []const u8) ?std.json.Value {
    var cur = v;
    for (path) |name| cur = (if (cur == .object) cur.object.get(name) else null) orelse return null;
    return cur;
}

const initialize =
    \\{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
;

test "initialize answers with the capabilities" {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var s: Session = .init();
    defer s.deinit();

    try s.send(initialize);
    const got = try s.received(arena.allocator());
    try std.testing.expectEqual(1, got.len);
    try std.testing.expectEqual(1, field(got[0], &.{"id"}).?.integer);
    try std.testing.expectEqual(1, field(got[0], &.{ "result", "capabilities", "textDocumentSync" }).?.integer);
    try std.testing.expect(field(got[0], &.{ "result", "capabilities", "semanticTokensProvider", "legend", "tokenTypes" }) != null);
    try std.testing.expectEqualStrings("fab", field(got[0], &.{ "result", "serverInfo", "name" }).?.string);
}

test "a request before initialize is refused" {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var s: Session = .init();
    defer s.deinit();

    try s.send(
        \\{"jsonrpc":"2.0","id":7,"method":"textDocument/semanticTokens/full","params":{}}
    );
    const got = try s.received(arena.allocator());
    try std.testing.expectEqual(-32002, field(got[0], &.{ "error", "code" }).?.integer);
}

test "opening a document publishes its diagnostics" {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var s: Session = .init();
    defer s.deinit();

    try s.send(initialize);
    _ = try s.received(arena.allocator());
    try s.send(
        \\{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///a.fab","languageId":"fab","version":1,"text":"G :: f/f/f"}}}
    );
    const got = try s.received(arena.allocator());
    try std.testing.expectEqual(1, got.len);
    try std.testing.expectEqualStrings("textDocument/publishDiagnostics", field(got[0], &.{"method"}).?.string);
    try std.testing.expectEqual(1, field(got[0], &.{ "params", "version" }).?.integer);
    const ds = field(got[0], &.{ "params", "diagnostics" }).?.array.items;
    try std.testing.expect(ds.len > 0);
    try std.testing.expectEqual(1, field(ds[0], &.{"severity"}).?.integer);
    try std.testing.expectEqualStrings("fab", field(ds[0], &.{"source"}).?.string);

    // Fixed, the list empties.
    try s.send(
        \\{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"file:///a.fab","version":2},"contentChanges":[{"text":"G :: f/g"}]}}
    );
    const fixed = try s.received(arena.allocator());
    try std.testing.expectEqual(2, field(fixed[0], &.{ "params", "version" }).?.integer);
    try std.testing.expectEqual(0, field(fixed[0], &.{ "params", "diagnostics" }).?.array.items.len);

    // Closed, too.
    try s.send(
        \\{"jsonrpc":"2.0","method":"textDocument/didClose","params":{"textDocument":{"uri":"file:///a.fab"}}}
    );
    const closed = try s.received(arena.allocator());
    try std.testing.expectEqual(0, field(closed[0], &.{ "params", "diagnostics" }).?.array.items.len);
}

test "semantic tokens of an open document" {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var s: Session = .init();
    defer s.deinit();

    try s.send(initialize);
    try s.send(
        \\{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///a.fab","version":1,"text":"G :: f"}}}
    );
    _ = try s.received(arena.allocator());
    try s.send(
        \\{"jsonrpc":"2.0","id":2,"method":"textDocument/semanticTokens/full","params":{"textDocument":{"uri":"file:///a.fab"}}}
    );
    const got = try s.received(arena.allocator());
    try std.testing.expectEqual(2, field(got[0], &.{"id"}).?.integer);
    try std.testing.expectEqual(15, field(got[0], &.{ "result", "data" }).?.array.items.len);
}

test "unknown requests fail, unknown notifications are ignored, bad JSON is a parse error" {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var s: Session = .init();
    defer s.deinit();

    try s.send(initialize);
    _ = try s.received(arena.allocator());
    try s.send(
        \\{"jsonrpc":"2.0","id":"x","method":"textDocument/hover","params":{}}
    );
    try s.send(
        \\{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":1}}
    );
    try s.send("{not json");
    const got = try s.received(arena.allocator());
    try std.testing.expectEqual(2, got.len);
    try std.testing.expectEqualStrings("x", field(got[0], &.{"id"}).?.string);
    try std.testing.expectEqual(-32601, field(got[0], &.{ "error", "code" }).?.integer);
    try std.testing.expectEqual(.null, std.meta.activeTag(field(got[1], &.{"id"}).?));
    try std.testing.expectEqual(-32700, field(got[1], &.{ "error", "code" }).?.integer);
}

test "exit after shutdown is 0, without it 1" {
    var s: Session = .init();
    defer s.deinit();
    try s.send(initialize);
    try s.send(
        \\{"jsonrpc":"2.0","id":9,"method":"shutdown"}
    );
    try s.send(
        \\{"jsonrpc":"2.0","method":"exit"}
    );
    try std.testing.expectEqual(0, s.server.exit_code.?);

    var t: Session = .init();
    defer t.deinit();
    try t.send(initialize);
    try t.send(
        \\{"jsonrpc":"2.0","method":"exit"}
    );
    try std.testing.expectEqual(1, t.server.exit_code.?);
}
