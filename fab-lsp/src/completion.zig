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
//!   G.f :   the descriptors applying at the context: the entry's, or the
//!           owner of its block (`G :style { :`), by the subjects' classes;
//!           in a record's block, its type's; in a bundle's, any
//!   :f [    the labels and named values fitting the descriptor's type, or
//!           the slot's after a `/`; after `:T [x] :=`, fitting `:T`

const std = @import("std");
const fab = @import("fab_core");
const Message = @import("Message.zig");
const Item = Message.CompletionItem;
const Tag = fab.Token.Tag;

/// The completions at `position` in `text`, from `base`'s names.
pub fn of(arena: std.mem.Allocator, text: []const u8, base: []const u8, position: Message.Position) error{OutOfMemory}![]const Item {
    var lines = try fab.Lines.init(arena, text);
    const offset = lines.byteOffset(.{ .line = position.line, .character = position.character });
    const typed = bracket(text[0..offset]) orelse try context(arena, text[0..offset]);

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
        .descriptors => |at| if (need(&result.ir, at.paths)) |classes_| {
            try descriptors(&out, &result.env, classes_, at);
        },
        .values => |in| try values(&out, &result.env, in),
    }
    return out.items.items;
}

/// What the cursor is in: what to offer, the name typed so far, and the
/// diagram of the statement, if it has one.
const Typed = struct {
    what: union(enum) { nothing, parts: []const u8, nodes, edges, diagrams, classes, types, descriptors: At, values: In },
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
    const t: Tokens = .{ .source = source, .tags = tags[0..n], .starts = starts, .ends = ends };
    const first = statementStart(t.tags);
    const zone = if (first < n and tags[first] == .zone_id) t.text(first) else null;

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
        .attr_id => described(arena, t, first, w, word),
        .invalid => if (std.mem.eql(u8, word, "#"))
            .{ .what = .nodes, .prefix = word, .zone = zone }
        else if (std.mem.eql(u8, word, "&"))
            .{ .what = .classes, .prefix = word, .zone = zone }
        else if (std.mem.eql(u8, word, ":") and w > 0 and (tags[w - 1] == .decl or tags[w - 1] == .defn))
            .{ .what = .types, .prefix = word, .zone = zone }
        else if (std.mem.eql(u8, word, ":"))
            described(arena, t, first, w, word)
        else
            .{ .what = .nothing },
        else => .{ .what = .nothing },
    };
}

/// The tokens before the cursor, the end of the input aside.
const Tokens = struct {
    source: []const u8,
    tags: []const Tag,
    starts: []const u32,
    ends: []const u32,

    fn text(t: Tokens, i: usize) []const u8 {
        return t.source[t.starts[i]..t.ends[i]];
    }
};

/// Where the statement at the end of the tokens begins. A line end ends a
/// statement, except inside braces.
fn statementStart(tags: []const Tag) usize {
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
    return first;
}

// ---------------------------------------------------------------------------
// Descriptors

/// A subject as written, before it is looked up: a diagram, a part of one,
/// or a class.
const Path = struct {
    zone: ?[]const u8 = null,
    part: union(enum) { whole, edge: []const u8, start: []const u8, end: []const u8, node: []const u8, own, class: []const u8 },
};

/// What a descriptor is written at, and whether at the top level, where a
/// layer can be opened. In a record's block, only its type's descriptors
/// are offered (`record`, the type's name); in a bundle's, any.
const At = struct { paths: []const Path, top: bool, record: ?[]const u8 = null, any: bool = false };

/// A block being read: its owner (null at the top level), where its current
/// entry begins, and how deep in parentheses.
const Frame = struct { owner: ?[]const Path, entry: usize, parens: usize = 0 };

/// A descriptor being typed at token `typed`, in the statement beginning at
/// `first`: the subjects of its entry, or of the block's owner. Only a
/// description has them: a statement with `::` or `:=` declares or names.
fn described(arena: std.mem.Allocator, all: Tokens, first: usize, typed: usize, word: []const u8) error{OutOfMemory}!Typed {
    // Line ends inside the statement are inside braces: whitespace there.
    var tags: std.ArrayList(Tag) = .empty;
    var starts: std.ArrayList(u32) = .empty;
    var ends: std.ArrayList(u32) = .empty;
    for (first..typed) |i| if (all.tags[i] != .eol) {
        try tags.append(arena, all.tags[i]);
        try starts.append(arena, all.starts[i]);
        try ends.append(arena, all.ends[i]);
    };
    const t: Tokens = .{ .source = all.source, .tags = tags.items, .starts = starts.items, .ends = ends.items };
    const w = tags.items.len;

    // A definition holds descriptors in its block: `:T [x] := {`, a record
    // of `:T`, described where it is applied, so a diagram; `:b := {`, a
    // bundle, with no subject.
    var record: ?[]const u8 = null;
    var bundle = false;
    const applied: []const Path = &.{.{ .part = .whole }};

    var frames: std.ArrayList(Frame) = .empty;
    try frames.append(arena, .{ .owner = null, .entry = 0 });
    for (0..w) |i| {
        const top = &frames.items[frames.items.len - 1];
        switch (t.tags[i]) {
            .decl => if (frames.items.len == 1) return .{ .what = .nothing },
            .defn => if (frames.items.len == 1) {
                if (i == 2 and t.tags[0] == .type_id and t.tags[1] == .val)
                    record = t.text(0)
                else if (i == 1 and t.tags[0] == .attr_id)
                    bundle = true
                else
                    return .{ .what = .nothing };
            },
            .l_par => top.parens += 1,
            .r_par => top.parens -|= 1,
            .comma => if (top.parens == 0) {
                top.entry = i + 1;
            },
            .l_cur => if (frames.items.len == 1 and (record != null or bundle)) {
                try frames.append(arena, .{ .owner = applied, .entry = i + 1 });
            } else {
                const owner = try within(arena, top.owner, try entryContext(arena, t, top.entry, i) orelse return .{ .what = .nothing }) orelse
                    return .{ .what = .nothing };
                try frames.append(arena, .{ .owner = owner, .entry = i + 1 });
            },
            .r_cur => if (frames.items.len > 1) {
                _ = frames.pop();
            },
            else => {},
        }
    }
    const top = frames.items[frames.items.len - 1];
    const defined = record != null or bundle;
    // Before the block, a definition names; in a bundle, nothing is a
    // subject.
    if (defined and frames.items.len == 1) return .{ .what = .nothing };
    const context_ = try entryContext(arena, t, top.entry, w) orelse return .{ .what = .nothing };
    if (bundle and context_.len > 0) return .{ .what = .nothing };
    const paths = try within(arena, top.owner, context_) orelse return .{ .what = .nothing };
    return .{
        .what = .{ .descriptors = .{ .paths = paths, .top = frames.items.len == 1, .record = record, .any = bundle } },
        .prefix = word,
    };
}

/// The context of the entry in tokens [from, to): what comes before its
/// first descriptor. Empty when there is none, so the owner is described;
/// null when it is not a subject (a chain, a path, a pinch).
fn entryContext(arena: std.mem.Allocator, t: Tokens, from: usize, to: usize) error{OutOfMemory}!?[]const Path {
    var end = from;
    while (end < to and t.tags[end] != .attr_id) end += 1;
    if (end == from) return &.{};
    var out: std.ArrayList(Path) = .empty;
    if (!try group(arena, t, from, end, &out)) return null;
    return out.items;
}

/// A context, or a group of them, flattened: false when not a subject.
fn group(arena: std.mem.Allocator, t: Tokens, from: usize, to: usize, out: *std.ArrayList(Path)) error{OutOfMemory}!bool {
    if (from >= to) return false;
    if (t.tags[from] == .l_par and t.tags[to - 1] == .r_par) {
        var depth: usize = 0;
        var start = from + 1;
        for (from + 1..to - 1) |i| switch (t.tags[i]) {
            .l_par => depth += 1,
            .r_par => depth -|= 1,
            .comma => if (depth == 0) {
                if (!try group(arena, t, start, i, out)) return false;
                start = i + 1;
            },
            else => {},
        };
        return group(arena, t, start, to - 1, out);
    }
    try out.append(arena, path(t, from, to) orelse return false);
    return true;
}

/// One context: `G`, `G.f`, `+f`, `f+`, `#A`, `@`, `&c`, each but the first
/// optionally qualified, `G.`.
fn path(t: Tokens, from: usize, to: usize) ?Path {
    var i = from;
    var zone: ?[]const u8 = null;
    if (to - from >= 3 and t.tags[i] == .zone_id and t.tags[i + 1] == .dot) {
        zone = t.text(i);
        i += 2;
    }
    if (to - i == 1) return switch (t.tags[i]) {
        .zone_id => if (zone == null) .{ .zone = t.text(i), .part = .whole } else null,
        .edge_id => .{ .zone = zone, .part = .{ .edge = t.text(i) } },
        .node_id => .{ .zone = zone, .part = .{ .node = t.text(i) } },
        .at => .{ .zone = zone, .part = .own },
        .class_id => .{ .zone = zone, .part = .{ .class = t.text(i)[1..] } },
        else => null,
    };
    if (to - i == 2) {
        if (t.tags[i] == .plus and t.tags[i + 1] == .edge_id) return .{ .zone = zone, .part = .{ .start = t.text(i + 1) } };
        if (t.tags[i] == .edge_id and t.tags[i + 1] == .plus) return .{ .zone = zone, .part = .{ .end = t.text(i) } };
    }
    return null;
}

/// The context inside a block, read relative to its owner: a diagram's
/// parts are its, and the owner itself when the entry has none. Null when
/// there is nothing to describe: no owner at the top level, or parts of an
/// element or a class (element has no parts).
fn within(arena: std.mem.Allocator, owner: ?[]const Path, context_: []const Path) error{OutOfMemory}!?[]const Path {
    if (context_.len == 0) return owner;
    const owners = owner orelse return context_;
    var out: std.ArrayList(Path) = .empty;
    for (owners) |o| {
        if (o.part != .whole) return null;
        for (context_) |c| try out.append(arena, .{ .zone = c.zone orelse o.zone, .part = c.part });
    }
    return out.items;
}

/// The classes of the subjects, as the analyser judges them: a node by its
/// kind. A name the program doesn't have is judged by its sort.
fn need(ir: *const fab.Ir, paths: []const Path) ?Classes {
    var classes_: Classes = .empty;
    for (paths) |p| {
        const zone = if (p.zone) |z| zoneNamed(ir, z) else null;
        classes_.setUnion(switch (p.part) {
            .whole => .initOne(.zone),
            .class => |name| Env.within(.initOne(std.meta.stringToEnum(Env.Class, name) orelse return null)),
            .edge => |name| if (zone) |z| (if (edgeNamed(ir, z, name)) |_| .initOne(.edge) else if (cellNamed(ir, z, name)) .initOne(.cell) else .initOne(.edge)) else .initOne(.edge),
            .start, .end => |name| node: {
                const z = zone orelse break :node any_node;
                const e = edgeNamed(ir, z, name) orelse break :node any_node;
                break :node kindOf(ir, if (p.part == .start) ir.edges.items(.source)[e] else ir.edges.items(.target)[e]);
            },
            .node => |name| node: {
                const z = zone orelse break :node any_node;
                for (ir.nodes.items(.name), ir.nodes.items(.zone), 0..) |n, nz, i| {
                    if (nz == z) if (n) |s| if (std.mem.eql(u8, ir.string(s), name))
                        break :node kindOf(ir, @fromBackingInt(@as(u32, @intCast(i))));
                }
                break :node any_node;
            },
            .own => if (zone) |z| (if (ir.zones.items(.own)[@backingInt(z)]) |n| kindOf(ir, n) else any_node) else any_node,
        });
    }
    return classes_;
}

const Env = fab.Analyser.Env;
const Classes = Env.Classes;
/// A node of no known kind: only what applies to every node fits it.
const any_node = Env.within(.initOne(.node));

fn edgeNamed(ir: *const fab.Ir, zone: fab.Ir.ZoneIndex, name: []const u8) ?usize {
    for (ir.edges.items(.name), ir.edges.items(.zone), 0..) |n, z, i| {
        if (z == zone and std.mem.eql(u8, ir.string(n), name)) return i;
    }
    return null;
}

fn cellNamed(ir: *const fab.Ir, zone: fab.Ir.ZoneIndex, name: []const u8) bool {
    for (ir.cells.items(.name), ir.cells.items(.zone)) |n, z| {
        if (z == zone and std.mem.eql(u8, ir.string(n), name)) return true;
    }
    return false;
}

/// A node's class by its kind: a null node is a start, or an end when an
/// edge arrives at it.
fn kindOf(ir: *const fab.Ir, node: fab.Ir.NodeIndex) Classes {
    return .initOne(switch (ir.nodes.items(.kind)[@backingInt(node)]) {
        .plain => .plain,
        .choice => .choice,
        .parallel => .parallel,
        .hole => .hole,
        .null_node => if (std.mem.indexOfScalar(fab.Ir.NodeIndex, ir.edges.items(.target), node) != null) .end else .start,
    });
}

/// The descriptors and bundles whose classes hold the subjects'. A layer,
/// `:style`, is opened only at the top level; a record holds its type's.
fn descriptors(out: *Collector, env: *const Env, classes_: Classes, at: At) error{OutOfMemory}!void {
    const record: ?Env.TypeIndex = if (at.record) |name| (env.type_table.get(name) orelse return).index else null;
    var it = env.functions.iterator();
    while (it.next()) |entry| {
        const f = entry.value_ptr;
        if (!at.any and !classes_.subsetOf(f.classes)) continue;
        if (!at.top and f.record == null and !f.bundle and env.isRecord(f.type)) continue;
        if (record) |r| if (f.record != r) continue;
        const detail: []const u8 = if (f.bundle) "bundle" else detail: {
            var w: std.Io.Writer.Allocating = .init(out.arena);
            w.writer.writeAll(":: ") catch return error.OutOfMemory;
            env.writeType(f.type, &w.writer) catch return error.OutOfMemory;
            break :detail w.written();
        };
        try out.add(entry.key_ptr.*, Item.Kind.property, detail);
    }
    std.mem.sort(Item, out.items.items, {}, byLabel);
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

// ---------------------------------------------------------------------------
// Values

/// A bracket being typed: what its value must fit (a descriptor's type, or
/// a contract's), and which slot the cursor is in.
const In = struct {
    descriptor: ?[]const u8 = null,
    contract: ?[]const u8 = null,
    /// The slashes before the cursor, inside the bracket.
    slot: usize,
};

/// An open bracket touching the cursor, after a descriptor (`:fill [`) or
/// a contract (`:Color [x] := [`). An open bracket lexes as no value, so it
/// is read from the text: the last `[` with no `]`, space or grouping
/// after it. A key, `:lemma.[`, is no value.
fn bracket(before: []const u8) ?Typed {
    const open = std.mem.lastIndexOfScalar(u8, before, '[') orelse return null;
    const inside = before[open + 1 ..];
    if (std.mem.indexOfAny(u8, inside, "] \t\r\n(),{}") != null) return null;
    const element = inside[if (std.mem.lastIndexOfScalar(u8, inside, '/')) |s| s + 1 else 0..];
    const slot = std.mem.count(u8, inside, "/");

    // The token before the bracket, read back over spaces.
    var end = open;
    while (end > 0 and (before[end - 1] == ' ' or before[end - 1] == '\t')) end -= 1;
    var start = end;
    while (start > 0 and !std.ascii.isWhitespace(before[start - 1])) start -= 1;
    const word = before[start..end];
    if (word.len > 1 and word[0] == ':' and std.ascii.isLower(word[1]) and std.mem.indexOfScalar(u8, word, '.') == null)
        return .{ .what = .{ .values = .{ .descriptor = word, .slot = slot } }, .prefix = element };
    // `:T [x] := [`
    if (std.mem.eql(u8, word, ":=")) {
        var i = start;
        while (i > 0 and std.ascii.isWhitespace(before[i - 1])) i -= 1;
        const name_end = i;
        while (i > 0 and !std.ascii.isWhitespace(before[i - 1])) i -= 1;
        const name = before[i..name_end];
        if (name.len < 2 or name[0] != '[') return null;
        var j = i;
        while (j > 0 and std.ascii.isWhitespace(before[j - 1])) j -= 1;
        const type_end = j;
        while (j > 0 and !std.ascii.isWhitespace(before[j - 1])) j -= 1;
        const type_name = before[j..type_end];
        if (type_name.len > 1 and type_name[0] == ':' and std.ascii.isUpper(type_name[1]))
            return .{ .what = .{ .values = .{ .contract = type_name, .slot = slot } }, .prefix = element };
    }
    return null;
}

/// The labels and named values fitting the bracket: the whole of the type
/// in its first slot, or the slot's own type.
fn values(out: *Collector, env: *const Env, in: In) error{OutOfMemory}!void {
    const expected: Env.TypeIndex = if (in.descriptor) |name|
        (env.functions.get(name) orelse return).type
    else
        (env.type_table.get(in.contract.?) orelse return).index;
    var it = env.values.iterator();
    while (it.next()) |entry| {
        const v = entry.value_ptr;
        if (v.type == .unknown) continue;
        const whole = in.slot == 0 and env.fits(v.type, expected);
        if (!whole and !fitsSlot(env, v.type, expected, in.slot, 8)) continue;
        // A record has no type, only its structure (statements.md §22.9).
        const detail: []const u8 = if (v.type == .record) "record" else detail: {
            var w: std.Io.Writer.Allocating = .init(out.arena);
            env.writeType(v.type, &w.writer) catch return error.OutOfMemory;
            break :detail w.written();
        };
        const kind = if (v.body == null) Item.Kind.enum_member else Item.Kind.value;
        try out.add(entry.key_ptr.*, kind, detail);
    }
    std.mem.sort(Item, out.items.items, {}, byLabel);
}

/// Whether `actual` fits slot `k` of a bracket of type `expected`: a
/// tuple's slot, a list's element, through declarations and unions.
fn fitsSlot(env: *const Env, actual: Env.TypeIndex, expected: Env.TypeIndex, k: usize, depth: usize) bool {
    if (depth == 0) return false;
    return switch (env.get(expected)) {
        .tuple => |ts| k < ts.len and env.fits(actual, ts[k]),
        .list => |e| env.fits(actual, e),
        .twin => |t| fitsSlot(env, actual, t, k, depth - 1),
        .@"union" => |ts| for (ts) |t| {
            if (fitsSlot(env, actual, t, k, depth - 1)) break true;
        } else false,
        .declared => |id| for (env.declared.items[id].members.items) |m| {
            if (fitsSlot(env, actual, m, k, depth - 1)) break true;
        } else false,
        else => false,
    };
}

fn toPosition(lines: *const fab.Lines, offset: u32) Message.Position {
    const p = lines.position(offset);
    return .{ .line = p.line, .character = p.character };
}

test {
    _ = @import("completion.test.zig");
}
