//! Renaming what the program owns (plan step L2d): every use of a name, in
//! the document, its definition included, from fab-core's references.
//!
//! Refused, with a reason: a built-in, the prelude's names, a name also
//! written where the analyser couldn't read it (renaming the rest would
//! change what the program means), a new name of the wrong spelling, or one
//! already naming something of its sort where it would be read: in the same
//! diagram for edges, cells and nodes, anywhere for the others.

const std = @import("std");
const fab = @import("fab_core");
const Message = @import("Message.zig");
const navigation = @import("navigation.zig");
const Reference = fab.Analyser.Reference;
const Tag = fab.Token.Tag;

pub fn Outcome(T: type) type {
    return union(enum) { ok: T, refused: []const u8 };
}

/// The name a rename at `position` would change, or why there is none.
pub fn prepare(arena: std.mem.Allocator, doc: navigation.Document, position: Message.Position) error{OutOfMemory}!Outcome(Message.PrepareRename) {
    var ctx = try navigation.Context.init(arena, doc, position);
    const at = switch (try target(arena, &ctx)) {
        .ok => |r| r,
        .refused => |why| return .{ .refused = why },
    };
    return .{ .ok = .{ .range = ctx.range(at.span.start, at.span.end), .placeholder = ctx.text(at) } };
}

/// The edits renaming the name at `position` to `new_name`, or why not.
pub fn rename(arena: std.mem.Allocator, doc: navigation.Document, position: Message.Position, new_name: []const u8) error{OutOfMemory}!Outcome(Message.WorkspaceEdit) {
    var ctx = try navigation.Context.init(arena, doc, position);
    const at = switch (try target(arena, &ctx)) {
        .ok => |r| r,
        .refused => |why| return .{ .refused = why },
    };
    if (!try spelled(arena, at.sort, new_name)) return .{ .refused = spelling(at.sort) };
    if (!std.mem.eql(u8, new_name, ctx.text(at))) {
        if (try taken(&ctx, at, new_name)) return .{ .refused = try std.fmt.allocPrint(arena, "`{s}` already names {s}.", .{ new_name, where(at.sort) }) };
    }

    var edits: std.ArrayList(Message.TextEdit) = .empty;
    for (ctx.all) |r| {
        if (ctx.same(r, at)) try edits.append(arena, .{ .range = ctx.range(r.span.start, r.span.end), .newText = new_name });
    }
    var changes: std.json.ArrayHashMap([]const Message.TextEdit) = .{};
    try changes.map.put(arena, doc.uri, edits.items);
    return .{ .ok = .{ .changes = changes } };
}

/// The reference at the position, if the program owns it and every use of
/// it was read.
fn target(arena: std.mem.Allocator, ctx: *navigation.Context) error{OutOfMemory}!Outcome(Reference) {
    const at = ctx.at orelse return .{ .refused = "No name here to rename." };
    const text = ctx.text(at);
    const site = at.definition orelse
        return .{ .refused = try std.fmt.allocPrint(arena, "`{s}` is built in: it can't be renamed.", .{text}) };
    if (site.prelude)
        return .{ .refused = try std.fmt.allocPrint(arena, "`{s}` is the prelude's: it can't be renamed here.", .{text}) };
    if (try unread(ctx, at))
        return .{ .refused = try std.fmt.allocPrint(arena, "`{s}` is also written where the program couldn't be read: fix its errors first.", .{text}) };
    return .{ .ok = at };
}

/// Whether a token spelled as `at` is no reference at all: inside a failed
/// term, or a statement with a syntax error. A bracket's elements aren't
/// tokens, so labels and values are not checked this way.
fn unread(ctx: *navigation.Context, at: Reference) error{OutOfMemory}!bool {
    const tag = tagOf(at.sort) orelse return false;
    const toks = try ctx.c.tokens();
    for (toks.items(.tag), toks.items(.start), toks.items(.end)) |t, start, end| {
        if (t != tag or !std.mem.eql(u8, ctx.c.source[start..end], ctx.text(at))) continue;
        const read = for (ctx.all) |r| {
            if (r.span.start == start) break true;
        } else false;
        if (!read) return true;
    }
    return false;
}

/// The token a name of `sort` is, or null for a bracket's element.
fn tagOf(sort: Reference.Sort) ?Tag {
    return switch (sort) {
        .zone => .zone_id,
        .node => .node_id,
        .edge, .cell => .edge_id,
        .type => .type_id,
        .descriptor => .attr_id,
        .label, .value => null,
    };
}

/// Whether `name` is spelled as a name of `sort`: one token of its tag, or
/// one name in a bracket.
fn spelled(arena: std.mem.Allocator, sort: Reference.Sort, name: []const u8) error{OutOfMemory}!bool {
    if (tagOf(sort)) |tag| {
        const source = try arena.dupeSentinel(u8, name, 0);
        const toks = try fab.Lexer.tokenize(arena, source, null);
        const tags = toks.items(.tag);
        return tags.len == 2 and tags[0] == tag and tags[1] == .eof and toks.items(.end)[0] == name.len;
    }
    const bracket = try std.fmt.allocPrint(arena, "[{s}]", .{name});
    var reader = fab.value.read(bracket);
    const element = (reader.next() catch return false) orelse return false;
    if (element.kind != .name or element.inverted) return false;
    return (reader.next() catch return false) == null;
}

fn spelling(sort: Reference.Sort) []const u8 {
    return switch (sort) {
        .zone => "A diagram's name starts with a capital: `G`, `Order`.",
        .node => "A node's name is `#` and a capital: `#A`.",
        .edge, .cell => "An edge's or a cell's name starts with a lowercase letter: `f`, `α`.",
        .type => "A type's name is `:` and a capital: `:Color`.",
        .descriptor => "A descriptor's name is `:` and a lowercase letter: `:fill`.",
        .label, .value => "A label's or a value's name is lowercase letters and digits, with single hyphens: `dark-red`.",
    };
}

fn where(sort: Reference.Sort) []const u8 {
    return switch (sort) {
        .zone => "a diagram",
        .node => "a node in this diagram",
        .edge, .cell => "an edge or a cell in this diagram",
        .type => "a type",
        .descriptor => "a descriptor",
        .label, .value => "a label or a value",
    };
}

/// Whether `name` already names something of `at`'s sort where it would be
/// read: in the same diagram for the graph's names, anywhere for the rest,
/// the prelude's included.
fn taken(ctx: *navigation.Context, at: Reference, name: []const u8) error{OutOfMemory}!bool {
    const result = try ctx.c.analysis();
    const env = &result.env;
    switch (at.sort) {
        .type => return env.type_table.contains(name),
        .descriptor => return env.functions.contains(name),
        .label, .value => return env.values.contains(name),
        .zone, .node, .edge, .cell => {},
    }
    const zone = zoneOf(&result.ir, at.subject);
    for (ctx.all) |r| {
        if (!std.mem.eql(u8, ctx.text(r), name)) continue;
        const same_space = switch (at.sort) {
            .zone => r.sort == .zone,
            .node => r.sort == .node,
            else => r.sort == .edge or r.sort == .cell,
        };
        if (!same_space) continue;
        if (at.sort == .zone or zone == null or zoneOf(&result.ir, r.subject) == zone) return true;
    }
    return false;
}

fn zoneOf(ir: *const fab.Ir, subject: ?fab.Ir.Subject) ?fab.Ir.ZoneIndex {
    return switch (subject orelse return null) {
        .zone => |z| z,
        .edge => |e| ir.edges.items(.zone)[@backingInt(e)],
        .cell => |c| ir.cells.items(.zone)[@backingInt(c)],
        .node => |n| ir.nodes.items(.zone)[@backingInt(n)],
    };
}

test {
    _ = @import("rename.test.zig");
}
