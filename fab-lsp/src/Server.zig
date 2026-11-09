//! The language server's state and dispatch: one message in, the messages it
//! causes out, written framed to the writer given. No I/O of its own.
//!
//! Lifecycle: `initialize` first, then documents opened, changed and closed,
//! each change recompiling the whole document and publishing its
//! diagnostics; `shutdown`, then `exit`.

const std = @import("std");
const Io = std.Io;
const Message = @import("Message.zig");
const Transport = @import("Transport.zig");
const diagnostics = @import("diagnostics.zig");
const tokens = @import("tokens.zig");
const navigation = @import("navigation.zig");

const Server = @This();

pub const version = "0.0.0";

pub const Error = Io.Writer.Error || error{OutOfMemory};

gpa: std.mem.Allocator,
options: Options,
/// Open documents by URI. Keys and texts are owned.
documents: std.StringHashMapUnmanaged(Document) = .empty,
state: enum { waiting, running, shutting_down } = .waiting,
/// Set by `exit`: 0 after `shutdown`, 1 otherwise. The loop stops then.
exit_code: ?u8 = null,

pub const Document = struct { text: []u8, version: i64 };

pub const Options = struct {
    /// A file holding the prelude, as a URI: definitions in the prelude land
    /// there. `fab lsp` writes it; without one, they are not found.
    prelude_uri: ?[]const u8 = null,
};

pub fn init(gpa: std.mem.Allocator, options: Options) Server {
    return .{ .gpa = gpa, .options = options };
}

pub fn deinit(s: *Server) void {
    var it = s.documents.iterator();
    while (it.next()) |entry| {
        s.gpa.free(entry.key_ptr.*);
        s.gpa.free(entry.value_ptr.text);
    }
    s.documents.deinit(s.gpa);
    s.* = undefined;
}

/// Handles one message's body, writing any responses and notifications.
pub fn handle(s: *Server, body: []const u8, out: *Io.Writer) Error!void {
    var arena_state: std.heap.ArenaAllocator = .init(s.gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const envelope = std.json.parseFromSliceLeaky(Message.Envelope, arena, body, .{ .ignore_unknown_fields = true }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return fail(arena, out, .null, Message.Code.parse_error, "the message is not valid JSON"),
    };
    const method = envelope.method orelse return; // a response to us: none expected
    const id = envelope.id;

    if (s.state == .waiting and !std.mem.eql(u8, method, "initialize")) {
        if (std.mem.eql(u8, method, "exit")) s.exit_code = 1;
        if (id) |i| return fail(arena, out, i, Message.Code.server_not_initialized, "initialize first");
        return;
    }

    if (std.mem.eql(u8, method, "initialize")) {
        s.state = .running;
        return respond(arena, out, id orelse .null, Message.InitializeResult{
            .capabilities = .{ .semanticTokensProvider = .{ .legend = .{ .tokenTypes = &tokens.types, .tokenModifiers = &tokens.modifiers } } },
            .serverInfo = .{ .version = version },
        });
    }
    if (std.mem.eql(u8, method, "initialized")) return;
    if (std.mem.eql(u8, method, "shutdown")) {
        s.state = .shutting_down;
        return respond(arena, out, id orelse .null, null);
    }
    if (std.mem.eql(u8, method, "exit")) {
        s.exit_code = if (s.state == .shutting_down) 0 else 1;
        return;
    }

    if (std.mem.eql(u8, method, "textDocument/didOpen")) {
        const p = params(Message.DidOpen, arena, envelope.params) orelse return;
        try s.store(p.textDocument.uri, p.textDocument.text, p.textDocument.version);
        return s.publish(arena, out, p.textDocument.uri);
    }
    if (std.mem.eql(u8, method, "textDocument/didChange")) {
        const p = params(Message.DidChange, arena, envelope.params) orelse return;
        if (p.contentChanges.len == 0) return;
        try s.store(p.textDocument.uri, p.contentChanges[p.contentChanges.len - 1].text, p.textDocument.version);
        return s.publish(arena, out, p.textDocument.uri);
    }
    if (std.mem.eql(u8, method, "textDocument/didClose")) {
        const p = params(Message.DidClose, arena, envelope.params) orelse return;
        if (s.documents.fetchRemove(p.textDocument.uri)) |entry| {
            s.gpa.free(entry.key);
            s.gpa.free(entry.value.text);
        }
        // Closed, its problems leave the editor's list.
        return notify(arena, out, "textDocument/publishDiagnostics", Message.PublishDiagnostics{ .uri = p.textDocument.uri, .diagnostics = &.{} });
    }
    if (std.mem.eql(u8, method, "textDocument/semanticTokens/full")) {
        const i = id orelse return;
        const p = params(Message.SemanticTokensParams, arena, envelope.params) orelse
            return fail(arena, out, i, Message.Code.invalid_params, "expected a textDocument");
        const doc = s.documents.get(p.textDocument.uri) orelse return respond(arena, out, i, Message.SemanticTokens{ .data = &.{} });
        return respond(arena, out, i, Message.SemanticTokens{ .data = try tokens.encode(arena, doc.text) });
    }

    if (std.mem.eql(u8, method, "textDocument/definition")) {
        const i = id orelse return;
        const p = params(Message.PositionParams, arena, envelope.params) orelse
            return fail(arena, out, i, Message.Code.invalid_params, "expected a textDocument and a position");
        const doc = s.navigable(p.textDocument.uri) orelse return respond(arena, out, i, null);
        return respond(arena, out, i, try navigation.definition(arena, doc, p.position));
    }
    if (std.mem.eql(u8, method, "textDocument/references")) {
        const i = id orelse return;
        const p = params(Message.ReferenceParams, arena, envelope.params) orelse
            return fail(arena, out, i, Message.Code.invalid_params, "expected a textDocument and a position");
        const doc = s.navigable(p.textDocument.uri) orelse return respond(arena, out, i, &[_]Message.Location{});
        return respond(arena, out, i, try navigation.references(arena, doc, p.position, p.context.includeDeclaration));
    }
    if (std.mem.eql(u8, method, "textDocument/documentHighlight")) {
        const i = id orelse return;
        const p = params(Message.PositionParams, arena, envelope.params) orelse
            return fail(arena, out, i, Message.Code.invalid_params, "expected a textDocument and a position");
        const doc = s.navigable(p.textDocument.uri) orelse return respond(arena, out, i, &[_]Message.DocumentHighlight{});
        return respond(arena, out, i, try navigation.highlights(arena, doc, p.position));
    }

    // Requests must be answered; unknown notifications are ignored.
    if (id) |i| return fail(arena, out, i, Message.Code.method_not_found, method);
}

/// Keeps a document's latest text.
fn store(s: *Server, uri: []const u8, text: []const u8, version_: i64) error{OutOfMemory}!void {
    const owned_text = try s.gpa.dupe(u8, text);
    errdefer s.gpa.free(owned_text);
    const gop = try s.documents.getOrPut(s.gpa, uri);
    if (gop.found_existing) {
        s.gpa.free(gop.value_ptr.text);
    } else {
        gop.key_ptr.* = s.gpa.dupe(u8, uri) catch |err| {
            s.documents.removeByPtr(gop.key_ptr);
            return err;
        };
    }
    gop.value_ptr.* = .{ .text = owned_text, .version = version_ };
}

/// An open document, for navigation.
fn navigable(s: *Server, uri: []const u8) ?navigation.Document {
    const doc = s.documents.get(uri) orelse return null;
    return .{ .uri = uri, .source = doc.text, .prelude_uri = s.options.prelude_uri };
}

/// Publishes a document's diagnostics. The prelude's file has none: it is
/// the compiler's own, read before every program, so read as one it would
/// define every name twice.
fn publish(s: *Server, arena: std.mem.Allocator, out: *Io.Writer, uri: []const u8) Error!void {
    const doc = s.documents.get(uri).?;
    const prelude = if (s.options.prelude_uri) |p| std.mem.eql(u8, p, uri) else false;
    try notify(arena, out, "textDocument/publishDiagnostics", Message.PublishDiagnostics{
        .uri = uri,
        .version = doc.version,
        .diagnostics = if (prelude) &.{} else try diagnostics.of(arena, uri, doc.text),
    });
}

/// A request's or a notification's params as `T`, or null when they don't
/// fit: the message is dropped.
fn params(comptime T: type, arena: std.mem.Allocator, value: ?std.json.Value) ?T {
    return std.json.parseFromValueLeaky(T, arena, value orelse return null, .{ .ignore_unknown_fields = true }) catch null;
}

fn respond(arena: std.mem.Allocator, out: *Io.Writer, id: std.json.Value, result: anytype) Error!void {
    // A response always has a result: an empty optional is `null`, not left
    // out as null fields are.
    if (@typeInfo(@TypeOf(result)) == .optional) {
        if (result) |r| return respond(arena, out, id, r);
        return send(arena, out, .{ .jsonrpc = "2.0", .id = id, .result = null });
    }
    try send(arena, out, .{ .jsonrpc = "2.0", .id = id, .result = result });
}

fn notify(arena: std.mem.Allocator, out: *Io.Writer, method: []const u8, p: anytype) Error!void {
    try send(arena, out, .{ .jsonrpc = "2.0", .method = method, .params = p });
}

fn fail(arena: std.mem.Allocator, out: *Io.Writer, id: std.json.Value, code: i32, message: []const u8) Error!void {
    try send(arena, out, .{ .jsonrpc = "2.0", .id = id, .@"error" = Message.ResponseError{ .code = code, .message = message } });
}

fn send(arena: std.mem.Allocator, out: *Io.Writer, message: anytype) Error!void {
    var body: Io.Writer.Allocating = .init(arena);
    std.json.Stringify.value(message, .{ .emit_null_optional_fields = false }, &body.writer) catch return error.OutOfMemory;
    try Transport.write(out, body.written());
}

test {
    _ = @import("server.test.zig");
}
