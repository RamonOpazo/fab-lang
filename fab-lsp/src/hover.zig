//! What a name is, shown on hover (plan step L2c): one line in Markdown, by
//! its sort, then the line that defines it.
//!
//!   diagram   G · 3 nodes, 2 edges
//!   edge      f in G: +f → #B; the nodes by name, or by canonical end
//!   cell      α in G, a 2-cell: f ⇒ g
//!   node      #X in G
//!   descriptor :fill: :Color, on &node, &zone, in :Style
//!   type      :Color, built-in
//!   label     [calm], of :Mood
//!   value     [warn]: :Color

const std = @import("std");
const fab = @import("fab_core");
const Message = @import("Message.zig");
const navigation = @import("navigation.zig");
const Ir = fab.Ir;
const Env = fab.Analyser.Env;
const Reference = fab.Analyser.Reference;
const Writer = std.Io.Writer;

/// The hover at `position`, or null where no name is.
pub fn of(arena: std.mem.Allocator, doc: navigation.Document, position: Message.Position) error{OutOfMemory}!?Message.Hover {
    var ctx = try navigation.Context.init(arena, doc, position);
    const at = ctx.at orelse return null;
    var out: Writer.Allocating = .init(arena);
    write(&ctx, at, &out.writer) catch return error.OutOfMemory;
    return .{ .contents = .{ .value = out.written() }, .range = ctx.range(at.span.start, at.span.end) };
}

fn write(ctx: *navigation.Context, at: Reference, w: *Writer) (Writer.Error || error{OutOfMemory})!void {
    const result = try ctx.c.analysis();
    const ir = &result.ir;
    const env = &result.env;
    const text = ctx.text(at);
    switch (at.sort) {
        .zone => {
            try w.print("**diagram** `{s}`", .{text});
            if (at.subject) |s| try counts(ir, s.zone, w);
        },
        .edge => {
            try w.print("**edge** `{s}`", .{text});
            if (at.subject) |s| {
                const e = ir.edges.get(@backingInt(s.edge));
                try w.print(" in `{s}`: ", .{ir.string(ir.zones.items(.name)[@backingInt(e.zone)])});
                try node(ir, e.source, w);
                try w.writeAll(if (e.directed) " → " else " — ");
                try node(ir, e.target, w);
            }
        },
        .cell => {
            try w.print("**cell** `{s}`", .{text});
            if (at.subject) |s| {
                const c = ir.cells.get(@backingInt(s.cell));
                try w.print(" in `{s}`, a {d}-cell: ", .{ ir.string(ir.zones.items(.name)[@backingInt(c.zone)]), c.level });
                try side(ir, c.source, w);
                try w.writeAll(if (c.directed) " ⇒ " else " ⇔ ");
                try side(ir, c.target, w);
            }
        },
        .node => {
            try w.writeAll("**node** ");
            if (at.subject) |s| {
                try node(ir, s.node, w);
                try w.print(" in `{s}`", .{ir.string(ir.zones.items(.name)[@backingInt(ir.nodes.items(.zone)[@backingInt(s.node)])])});
            } else try w.print("`{s}`", .{text});
        },
        .descriptor => if (env.functions.get(text)) |f| {
            try w.print("**{s}** `{s}`", .{ if (f.bundle) "bundle" else "descriptor", text });
            if (!f.bundle) {
                try w.writeAll(": `");
                try env.writeType(f.type, w);
                try w.writeByte('`');
            }
            try classes(f.classes, w);
            if (f.record) |r| {
                try w.writeAll(", in `");
                try env.writeType(r, w);
                try w.writeByte('`');
            }
            if (f.table) try w.writeAll(", a table: it takes a key");
        } else try w.print("**descriptor** `{s}`", .{text}),
        .type => {
            try w.print("**type** `{s}`", .{text});
            if (at.definition == null) try w.writeAll(", built-in");
        },
        .label, .value => if (env.values.get(text)) |v| {
            if (v.body == null) {
                try w.print("**label** `[{s}]`, of `", .{text});
            } else try w.print("**value** `[{s}]`: `", .{text});
            try env.writeType(v.type, w);
            try w.writeByte('`');
        } else try w.print("**{s}** `[{s}]`", .{ @tagName(at.sort), text }),
    }
    if (at.definition) |site| {
        if (site.prelude) try w.writeAll(", from the prelude");
        try definitionLine(ctx, site, w);
    }
}

/// A diagram's size: its nodes, edges and cells.
fn counts(ir: *const Ir, zone: Ir.ZoneIndex, w: *Writer) Writer.Error!void {
    var n: [3]usize = .{ 0, 0, 0 };
    for (ir.nodes.items(.zone)) |z| n[0] += @intFromBool(z == zone);
    for (ir.edges.items(.zone)) |z| n[1] += @intFromBool(z == zone);
    for (ir.cells.items(.zone)) |z| n[2] += @intFromBool(z == zone);
    try w.print(" · {d} node{s}, {d} edge{s}", .{ n[0], plural(n[0]), n[1], plural(n[1]) });
    if (n[2] > 0) try w.print(", {d} cell{s}", .{ n[2], plural(n[2]) });
}

fn plural(n: usize) []const u8 {
    return if (n == 1) "" else "s";
}

/// A node as the program refers to it: its name, its diagram's, `*`, or its
/// canonical end (`+f`, `f+`); a choice and a parallel node say so.
fn node(ir: *const Ir, index: Ir.NodeIndex, w: *Writer) Writer.Error!void {
    const n = ir.nodes.get(@backingInt(index));
    if (n.diagram) |d| {
        try w.print("`{s}`", .{ir.string(ir.zones.items(.name)[@backingInt(d)])});
    } else if (n.name) |name| {
        try w.print("`{s}`", .{ir.string(name)});
    } else switch (n.kind) {
        .null_node => try w.writeAll("`*`"),
        .hole => try w.writeAll("a hole"),
        else => if (n.canonical) |end| {
            const edge = ir.string(ir.edges.items(.name)[@backingInt(end.edge)]);
            if (end.side == .dom) try w.print("`+{s}`", .{edge}) else try w.print("`{s}+`", .{edge});
        } else try w.writeAll("a node"),
    }
    switch (n.kind) {
        .choice => try w.writeAll(" (choice)"),
        .parallel => try w.writeAll(" (parallel)"),
        else => {},
    }
}

/// A cell's side: a named node, an edge, or a cell.
fn side(ir: *const Ir, s: Ir.Cell.Side, w: *Writer) Writer.Error!void {
    switch (s) {
        .node => |n| try node(ir, n, w),
        .edge => |e| try w.print("`{s}`", .{ir.string(ir.edges.items(.name)[@backingInt(e)])}),
        .cell => |c| try w.print("`{s}`", .{ir.string(ir.cells.items(.name)[@backingInt(c)])}),
    }
}

/// The classes a descriptor applies to, as declared: the node kinds `&node`
/// brings are left out.
fn classes(set: Env.Classes, w: *Writer) Writer.Error!void {
    var it = set.iterator();
    var first = true;
    while (it.next()) |c| {
        if (set.contains(.node) and c != .node and Env.within(.initOne(.node)).contains(c)) continue;
        try w.print("{s}`&{s}`", .{ if (first) ", on " else ", ", @tagName(c) });
        first = false;
    }
}

/// The line that defines a name, in a code block.
fn definitionLine(ctx: *navigation.Context, site: Reference.Site, w: *Writer) (Writer.Error || error{OutOfMemory})!void {
    const source = if (site.prelude) fab.Compilation.prelude_source else ctx.c.source;
    const span = try ctx.c.definitionSpan(site);
    const start = if (std.mem.lastIndexOfScalar(u8, source[0..span.start], '\n')) |i| i + 1 else 0;
    const end = std.mem.indexOfScalarPos(u8, source, span.start, '\n') orelse source.len;
    try w.print("\n\n```fab\n{s}\n```", .{std.mem.trim(u8, source[start..end], " \t\r")});
}

test {
    _ = @import("hover.test.zig");
}
