//! Completion (plan step L3): what may be written at the cursor.
//!
//! The context is read from the tokens of the text as it is, up to the
//! cursor, since the tree of a line being typed is broken there. The
//! candidates come from the last version of the document with no syntax
//! errors (`base`), so names declared further up stay offered while the
//! current line is broken.
//!
//!   G.      G's parts: edges, cells, named nodes, `@`, classes
//!   #       the named nodes of the statement's diagram
//!   f       the edges and cells of the statement's diagram
//!   G       the diagrams
//!   &       the classes
//!   :T      the types; `:` alone after `::` or `:=`

const std = @import("std");
const fab = @import("fab_core");
const Message = @import("Message.zig");
const Item = Message.CompletionItem;
const Tag = fab.Token.Tag;

/// The completions at `position` in `text`, from `base`'s names.
pub fn of(arena: std.mem.Allocator, text: []const u8, base: []const u8, position: Message.Position) error{OutOfMemory}![]const Item {
    var lines = try fab.Lines.init(arena, text);
    const offset = lines.byteOffset(.{ .line = position.line, .character = position.character });
    const typed = try context(arena, text[0..offset]);

    var c = try fab.Compilation.init(arena, base, .{ .warnings = .warn, .ir = .keep });
    const result = try c.analysis();
    var out: Collector = .{
        .arena = arena,
        .prefix = typed.prefix,
        .edit = .{ .start = toPosition(&lines, offset - @as(u32, @intCast(typed.prefix.len))), .end = toPosition(&lines, offset) },
    };
    switch (typed.what) {
        .nothing => {},
        .parts => |zone| if (zoneNamed(&result.ir, zone)) |z| {
            try edges(&out, &result.ir, z);
            try nodes(&out, &result.ir, z);
            try classes(&out);
        },
        .nodes => if (typed.zone) |zone| if (zoneNamed(&result.ir, zone)) |z| try nodes(&out, &result.ir, z),
        .edges => if (typed.zone) |zone| if (zoneNamed(&result.ir, zone)) |z| try edges(&out, &result.ir, z),
        .diagrams => try diagrams(&out, &result.ir),
        .classes => try classes(&out),
        .types => try types(&out, &result.env),
    }
    return out.items.items;
}

/// What the cursor is in: what to offer, the name typed so far, and the
/// diagram of the statement, if it has one.
const Typed = struct {
    what: union(enum) { nothing, parts: []const u8, nodes, edges, diagrams, classes, types },
    prefix: []const u8 = "",
    zone: ?[]const u8 = null,
};

fn context(arena: std.mem.Allocator, before: []const u8) error{OutOfMemory}!Typed {
    const source = try arena.dupeSentinel(u8, before, 0);
    const toks = try fab.Lexer.tokenize(arena, source);
    const tags = toks.items(.tag);
    const starts = toks.items(.start);
    const ends = toks.items(.end);
    const n = tags.len - 1; // the end of the input aside
    const zone = statementZone(source, tags[0..n], starts, ends);

    // The token being typed touches the cursor.
    if (n == 0 or ends[n - 1] != before.len) return .{ .what = .nothing };
    const w = n - 1;
    const word = before[starts[w]..ends[w]];

    // `G.` and `G.f`: after a diagram's name and a dot, touching.
    if (tags[w] == .dot and w > 0 and tags[w - 1] == .zone_id and ends[w - 1] == starts[w])
        return .{ .what = .{ .parts = before[starts[w - 1]..ends[w - 1]] }, .zone = zone };
    if (w > 1 and tags[w - 1] == .dot and ends[w - 1] == starts[w] and tags[w - 2] == .zone_id and ends[w - 2] == starts[w - 1])
        return .{ .what = .{ .parts = before[starts[w - 2]..ends[w - 2]] }, .prefix = word, .zone = zone };

    return switch (tags[w]) {
        .node_id => .{ .what = .nodes, .prefix = word, .zone = zone },
        .edge_id => .{ .what = .edges, .prefix = word, .zone = zone },
        .zone_id => .{ .what = .diagrams, .prefix = word, .zone = zone },
        .class_id => .{ .what = .classes, .prefix = word, .zone = zone },
        .type_id => .{ .what = .types, .prefix = word, .zone = zone },
        .invalid => if (std.mem.eql(u8, word, "#"))
            .{ .what = .nodes, .prefix = word, .zone = zone }
        else if (std.mem.eql(u8, word, "&"))
            .{ .what = .classes, .prefix = word, .zone = zone }
        else if (std.mem.eql(u8, word, ":") and w > 0 and (tags[w - 1] == .decl or tags[w - 1] == .defn))
            .{ .what = .types, .prefix = word, .zone = zone }
        else
            .{ .what = .nothing },
        else => .{ .what = .nothing },
    };
}

/// The diagram the statement at the end of the tokens is about: its first
/// token, if a diagram's name. A line end ends a statement, except inside
/// braces.
fn statementZone(source: []const u8, tags: []const Tag, starts: []const u32, ends: []const u32) ?[]const u8 {
    var depth: usize = 0;
    var first: usize = 0;
    for (tags, 0..) |t, i| switch (t) {
        .l_cur => depth += 1,
        .r_cur => depth -|= 1,
        .eol => if (depth == 0) {
            first = i + 1;
        },
        else => {},
    };
    if (first >= tags.len or tags[first] != .zone_id) return null;
    return source[starts[first]..ends[first]];
}

fn zoneNamed(ir: *const fab.Ir, name: []const u8) ?fab.Ir.ZoneIndex {
    for (ir.zones.items(.name), ir.zones.items(.placeholder), 0..) |n, placeholder, i| {
        if (!placeholder and std.mem.eql(u8, ir.string(n), name)) return @fromBackingInt(@as(u32, @intCast(i)));
    }
    return null;
}

/// Items, once each, those starting with the typed name.
const Collector = struct {
    arena: std.mem.Allocator,
    prefix: []const u8,
    edit: Message.Range,
    items: std.ArrayList(Item) = .empty,
    seen: std.StringHashMapUnmanaged(void) = .empty,

    fn add(c: *Collector, label: []const u8, kind: u8, detail: ?[]const u8) error{OutOfMemory}!void {
        if (!std.mem.startsWith(u8, label, c.prefix)) return;
        if ((try c.seen.getOrPut(c.arena, label)).found_existing) return;
        try c.items.append(c.arena, .{ .label = label, .kind = kind, .detail = detail, .textEdit = .{ .range = c.edit, .newText = label } });
    }
};

fn edges(out: *Collector, ir: *const fab.Ir, zone: fab.Ir.ZoneIndex) error{OutOfMemory}!void {
    for (ir.edges.items(.name), ir.edges.items(.zone)) |name, z| {
        if (z == zone) try out.add(ir.string(name), Item.Kind.function, "edge");
    }
    for (ir.cells.items(.name), ir.cells.items(.zone), ir.cells.items(.level)) |name, z, level| {
        if (z == zone) try out.add(ir.string(name), Item.Kind.function, try std.fmt.allocPrint(out.arena, "{d}-cell", .{level}));
    }
}

fn nodes(out: *Collector, ir: *const fab.Ir, zone: fab.Ir.ZoneIndex) error{OutOfMemory}!void {
    for (ir.nodes.items(.name), ir.nodes.items(.zone)) |name, z| {
        if (z == zone) if (name) |n| try out.add(ir.string(n), Item.Kind.variable, "node");
    }
    if (ir.zones.items(.own)[@backingInt(zone)] != null) try out.add("@", Item.Kind.variable, "the diagram's own node");
}

fn diagrams(out: *Collector, ir: *const fab.Ir) error{OutOfMemory}!void {
    for (ir.zones.items(.name), ir.zones.items(.placeholder)) |name, placeholder| {
        if (!placeholder) try out.add(ir.string(name), Item.Kind.module, "diagram");
    }
}

fn classes(out: *Collector) error{OutOfMemory}!void {
    for (std.enums.values(fab.Analyser.Env.Class)) |c| {
        try out.add(try std.fmt.allocPrint(out.arena, "&{s}", .{@tagName(c)}), Item.Kind.@"enum", "class");
    }
}

fn types(out: *Collector, env: *const fab.Analyser.Env) error{OutOfMemory}!void {
    var it = env.type_table.iterator();
    while (it.next()) |entry| {
        const detail: []const u8 = if (entry.value_ptr.token == null) "built-in type" else if (entry.value_ptr.prelude) "type, from the prelude" else "type";
        try out.add(entry.key_ptr.*, Item.Kind.class, detail);
    }
    std.mem.sort(Item, out.items.items, {}, byLabel);
}

fn byLabel(_: void, x: Item, y: Item) bool {
    return std.mem.lessThan(u8, x.label, y.label);
}

fn toPosition(lines: *const fab.Lines, offset: u32) Message.Position {
    const p = lines.position(offset);
    return .{ .line = p.line, .character = p.character };
}

test {
    _ = @import("completion.test.zig");
}
