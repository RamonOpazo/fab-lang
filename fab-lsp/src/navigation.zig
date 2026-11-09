//! Navigation by name (plan step L2b): where a name is defined, where it is
//! used, and its uses highlighted, all from fab-core's references
//! (`Compilation.references`).
//!
//! A name is found at the cursor, or just before it, as an editor puts the
//! cursor after a word. Uses of one thing share its definition; built-ins,
//! which have none, share their text. A definition in the prelude lands in
//! the prelude's file, when the server has one (`prelude_uri`).

const std = @import("std");
const fab = @import("fab_core");
const Message = @import("Message.zig");
const Reference = fab.Analyser.Reference;

/// A document to navigate, compiled once per request.
pub const Document = struct {
    uri: []const u8,
    source: []const u8,
    /// The file holding the prelude, for definitions in it; null when the
    /// server has none.
    prelude_uri: ?[]const u8,
};

/// A compiled document, and the reference at a position: what navigation
/// and hover read.
pub const Context = struct {
    c: fab.Compilation,
    lines: fab.Lines,
    all: []const Reference,
    /// The reference at the position, if any.
    at: ?Reference,

    pub fn init(arena: std.mem.Allocator, doc: Document, position: Message.Position) error{OutOfMemory}!Context {
        var c = try fab.Compilation.init(arena, doc.source, .{ .warnings = .warn, .ir = .keep });
        const lines = try fab.Lines.init(arena, c.source);
        const all = try c.references();
        const offset = lines.byteOffset(.{ .line = position.line, .character = position.character });
        return .{ .c = c, .lines = lines, .all = all, .at = find(all, offset) };
    }

    /// Whether `r` names what `target` names.
    fn same(ctx: *const Context, r: Reference, target: Reference) bool {
        if (target.definition) |t| {
            const d = r.definition orelse return false;
            return d.token == t.token and d.prelude == t.prelude;
        }
        return r.definition == null and r.sort == target.sort and
            std.mem.eql(u8, ctx.text(r), ctx.text(target));
    }

    pub fn text(ctx: *const Context, r: Reference) []const u8 {
        return ctx.c.source[r.span.start..r.span.end];
    }

    /// Whether `r` is its own definition: within the definition's token, as
    /// `red` is within `[red]`.
    fn defines(ctx: *Context, r: Reference) error{OutOfMemory}!bool {
        const site = r.definition orelse return false;
        if (site.prelude) return false;
        const span = try ctx.c.definitionSpan(site);
        return span.start <= r.span.start and r.span.end <= span.end;
    }

    pub fn range(ctx: *const Context, start: u32, end: u32) Message.Range {
        return rangeIn(&ctx.lines, start, end);
    }
};

/// The reference whose span holds `offset`, or ends at it.
fn find(all: []const Reference, offset: u32) ?Reference {
    var before: ?Reference = null;
    for (all) |r| {
        if (r.span.start <= offset and offset < r.span.end) return r;
        if (r.span.end == offset) before = r;
        if (r.span.start > offset) break;
    }
    return before;
}

fn rangeIn(lines: *const fab.Lines, start: u32, end: u32) Message.Range {
    const from = lines.position(start);
    const to = lines.position(end);
    return .{ .start = .{ .line = from.line, .character = from.character }, .end = .{ .line = to.line, .character = to.character } };
}

/// Where the name at `position` is defined, or null: no name there, a
/// built-in, or the prelude with no file for it.
pub fn definition(arena: std.mem.Allocator, doc: Document, position: Message.Position) error{OutOfMemory}!?Message.Location {
    var ctx = try Context.init(arena, doc, position);
    const at = ctx.at orelse return null;
    const site = at.definition orelse return null;
    return try locate(arena, &ctx, doc, site);
}

fn locate(arena: std.mem.Allocator, ctx: *Context, doc: Document, site: Reference.Site) error{OutOfMemory}!?Message.Location {
    const span = try ctx.c.definitionSpan(site);
    if (!site.prelude) return .{ .uri = doc.uri, .range = ctx.range(span.start, span.end) };
    const uri = doc.prelude_uri orelse return null;
    var lines = try fab.Lines.init(arena, fab.Compilation.prelude_source);
    return .{ .uri = uri, .range = rangeIn(&lines, span.start, span.end) };
}

/// Every use of the name at `position` in the document; with
/// `include_declaration`, its definition too, wherever it is.
pub fn references(arena: std.mem.Allocator, doc: Document, position: Message.Position, include_declaration: bool) error{OutOfMemory}![]const Message.Location {
    var ctx = try Context.init(arena, doc, position);
    const at = ctx.at orelse return &.{};
    var out: std.ArrayList(Message.Location) = .empty;
    for (ctx.all) |r| {
        if (!ctx.same(r, at)) continue;
        if (!include_declaration and try ctx.defines(r)) continue;
        try out.append(arena, .{ .uri = doc.uri, .range = ctx.range(r.span.start, r.span.end) });
    }
    // A definition outside the document: the prelude's.
    if (include_declaration) if (at.definition) |site| if (site.prelude) {
        if (try locate(arena, &ctx, doc, site)) |l| try out.append(arena, l);
    };
    return out.items;
}

/// The uses of the name at `position` in the document, its definition
/// written, the others read.
pub fn highlights(arena: std.mem.Allocator, doc: Document, position: Message.Position) error{OutOfMemory}![]const Message.DocumentHighlight {
    var ctx = try Context.init(arena, doc, position);
    const at = ctx.at orelse return &.{};
    var out: std.ArrayList(Message.DocumentHighlight) = .empty;
    for (ctx.all) |r| {
        if (!ctx.same(r, at)) continue;
        const kind = if (try ctx.defines(r)) Message.DocumentHighlight.write else Message.DocumentHighlight.read;
        try out.append(arena, .{ .range = ctx.range(r.span.start, r.span.end), .kind = kind });
    }
    return out.items;
}

test {
    _ = @import("navigation.test.zig");
}
