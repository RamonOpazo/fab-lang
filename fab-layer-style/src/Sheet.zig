//! The product of the style pass: every element's style, resolved, the way
//! a style sheet maps elements to styles (statements.md §22.12).
//!
//! The prelude is its only schema: a style is a list of entries, a
//! descriptor of `:Style` and its value, resolved (tokens as colours,
//! computed defaults filled in). Styles are shared the way the author
//! shares them (§25): rules are a tree of steps, `[base]` class by class,
//! then each layer a diagram adds (the kind's theme, a theme, a diagram's
//! classes), each rule holding only what its step changes; each element
//! names its rule and holds only its own entries. `style` reads the element,
//! then up its rules. A renderer reads what it draws, by descriptor, and
//! reports the rest.
//!
//! Made by Styler.zig, from fab-core's analysis (statements.md §26). A Sheet borrows the IR and the environment, which
//! must outlive it, and owns its tables; what the cascade computes (labels,
//! values with their tokens resolved, each diagram's tokens) is in its
//! arena.

const std = @import("std");
const fab = @import("fab_core");
const Ir = fab.Ir;
const Env = fab.Env;
const Decimal = fab.Decimal;
const value = fab.value;
const decoded = fab.decoded;
const Value = decoded.Value;

const Sheet = @This();

ir: *const Ir,
/// What the cascade computes: canonical labels, resolved values, tokens.
arena: std.heap.ArenaAllocator,

/// `:Style`'s descriptors, in the order they are declared, the prelude's
/// first: what a `Descriptor` indexes. Names borrow the environment's
/// sources.
descriptors: []const []const u8 = &.{},
rules: []const Rule = &.{},
/// Every rule's and element's entries, each list sorted by descriptor.
entries: []const Entry = &.{},
/// Each element's rule and own entries, indexed as the IR's tables.
elements: Elements = .{},
/// Each diagram's tokens, resolved: `[base]`'s, its themes', its own.
tokens: []const []const decoded.Token = &.{},
/// `[base]`'s tokens: the defaults a renderer may set once, for every
/// diagram.
base_tokens: []const decoded.Token = &.{},
gpa: std.mem.Allocator,

/// A descriptor of `:Style`, by its place in `descriptors`.
pub const Descriptor = enum(u16) { _ };

/// A descriptor and the value it resolves to, with the layer that bound it.
pub const Entry = struct { descriptor: Descriptor, value: Value, layer: Layer = .base };

/// Where an entry's value comes from. Above `base`, the author asked for
/// it: what a renderer reports when it can't draw it.
pub const Layer = enum { computed, base, kind, theme, program, mark };

/// How serious an issue is, as drawn (fab-core's: it is read from the
/// diagnostics).
pub const Mark = fab.Compilation.Mark;

/// Entries `start..end` of `entries`.
pub const Span = struct { start: u32 = 0, end: u32 = 0 };

/// One step of the cascade, as a rule adds it (statements.md §25): a class
/// inside `[base]`, a kind's theme, a named theme, a diagram's classes and
/// tokens, or (null) the top level's classes, every diagram's.
pub const Step = union(enum) {
    class: Env.Class,
    kind: []const u8,
    theme: []const u8,
    zone: ?Ir.ZoneIndex,
};

/// What one step adds to its parent's style, for one set of classes: the
/// entries that differ, by value or by layer. A class step's classes are
/// its parent's and its own; a layer step's, the whole set its elements
/// have.
pub const Rule = struct {
    adds: Step,
    classes: Env.Classes,
    parent: ?RuleIndex = null,
    entries: Span,
};

pub const RuleIndex = enum(u32) { _ };

pub const Element = struct {
    rule: RuleIndex,
    own: Span = .{},
    /// Its worst issue, drawn or not (`:marks []`).
    mark: ?Mark = null,
};

pub const Elements = struct {
    nodes: []const Element = &.{},
    edges: []const Element = &.{},
    cells: []const Element = &.{},
    zones: []const Element = &.{},
};

/// An element of the IR, of any table.
pub const Subject = Ir.Subject;

pub fn deinit(s: *Sheet) void {
    s.arena.deinit();
    s.gpa.free(s.descriptors);
    s.gpa.free(s.rules);
    s.gpa.free(s.entries);
    s.gpa.free(s.elements.nodes);
    s.gpa.free(s.elements.edges);
    s.gpa.free(s.elements.cells);
    s.gpa.free(s.elements.zones);
    s.gpa.free(s.tokens);
    s.* = undefined;
}

/// The descriptor named `name`, `:` included; null when `:Style` has none.
/// A renderer looks up the names it draws once.
pub fn descriptor(s: *const Sheet, name: []const u8) ?Descriptor {
    for (s.descriptors, 0..) |d, i| if (std.mem.eql(u8, d, name)) return @fromBackingInt(@as(u16, @intCast(i)));
    return null;
}

/// The value `zone` binds the token `name` to, if any: `[unsupported]`'s
/// colour, for a caption.
pub fn token(s: *const Sheet, z: Ir.ZoneIndex, name: []const u8) ?Value {
    for (s.tokens[@backingInt(z)]) |t| if (std.mem.eql(u8, t.label, name)) return t.value;
    return null;
}

/// `[base]`'s value for the token `name`.
pub fn baseToken(s: *const Sheet, name: []const u8) ?Value {
    for (s.base_tokens) |t| if (std.mem.eql(u8, t.label, name)) return t.value;
    return null;
}

pub fn element(s: *const Sheet, subject: Subject) Element {
    return switch (subject) {
        .node => |n| s.elements.nodes[@backingInt(n)],
        .edge => |x| s.elements.edges[@backingInt(x)],
        .cell => |x| s.elements.cells[@backingInt(x)],
        .zone => |z| s.elements.zones[@backingInt(z)],
    };
}

pub fn rule(s: *const Sheet, r: RuleIndex) Rule {
    return s.rules[@backingInt(r)];
}

/// The style of `subject`: its own entries over its rule's, over its rule's
/// parents'.
pub fn style(s: *const Sheet, subject: Subject) View {
    const e = s.element(subject);
    return .{ .sheet = s, .own = s.slice(e.own), .rule = e.rule };
}

pub fn slice(s: *const Sheet, span: Span) []const Entry {
    return s.entries[span.start..span.end];
}

// ---------------------------------------------------------------------------
// Dump: what the author asked for, as it resolved. Zone by zone, as
// `Ir.dump`: its own style, the tokens it rebinds, then its nodes, edges
// and cells. Each element lists, by descriptor, the entries a theme, the
// program or a mark gave it, with that layer; `[base]` and what is computed
// are left out, unless `base` asks for `[base]`; an element with nothing
// to show is not written. Values as fAB writes them, a flag as its
// descriptor, `!` when off. The format of the conformance corpus's
// `.sheet`.
//
//   zone G: fill [#1f6feb] program
//     token ink [#ff0000]        G rebinds [ink], unlike [base]
//     node n0: shape [circle] theme, label "x" program
//     edge f: arrow [/dashed/>] program, hide! program
//     cell α: label $\alpha$ program

pub const DumpOptions = struct {
    /// `[base]`'s entries too, and every token a diagram has.
    base: bool = false,
};

pub fn dump(s: *const Sheet, w: *std.Io.Writer, options: DumpOptions) std.Io.Writer.Error!void {
    const ir = s.ir;
    for (0..ir.zones.len) |z| {
        const zone: Ir.ZoneIndex = @fromBackingInt(@as(u32, @intCast(z)));
        try w.print("zone {s}", .{ir.string(ir.zones.items(.name)[z])});
        try s.dumpStyle(.{ .zone = zone }, options, w);
        try w.writeByte('\n');
        for (s.tokens[z]) |t| {
            if (!options.base) if (s.baseToken(t.label)) |b| if (std.meta.eql(b, t.value)) continue;
            try w.print("  token {s} ", .{t.label});
            try decoded.write(t.value, w);
            try w.writeByte('\n');
        }
        for (ir.nodes.items(.zone), 0..) |owner, n| {
            if (owner != zone) continue;
            const subject: Subject = .{ .node = @fromBackingInt(@as(u32, @intCast(n))) };
            if (!s.shown(subject, options)) continue;
            try w.print("  node n{d}", .{n});
            try s.dumpStyle(subject, options, w);
            try w.writeByte('\n');
        }
        for (ir.edges.items(.zone), ir.edges.items(.name), 0..) |owner, name, e| {
            if (owner != zone) continue;
            const subject: Subject = .{ .edge = @fromBackingInt(@as(u32, @intCast(e))) };
            if (!s.shown(subject, options)) continue;
            try w.print("  edge {s}", .{ir.string(name)});
            try s.dumpStyle(subject, options, w);
            try w.writeByte('\n');
        }
        for (ir.cells.items(.zone), ir.cells.items(.name), 0..) |owner, name, c| {
            if (owner != zone) continue;
            const subject: Subject = .{ .cell = @fromBackingInt(@as(u32, @intCast(c))) };
            if (!s.shown(subject, options)) continue;
            try w.print("  cell {s}", .{ir.string(name)});
            try s.dumpStyle(subject, options, w);
            try w.writeByte('\n');
        }
    }
}

/// Whether the dump has anything of `subject`'s style to show.
fn shown(s: *const Sheet, subject: Subject, options: DumpOptions) bool {
    const v = s.style(subject);
    for (0..s.descriptors.len) |d| {
        if (v.entry(@fromBackingInt(@as(u16, @intCast(d))))) |e| if (dumped(e, options)) return true;
    }
    return false;
}

/// What the author asked for (a theme, the program, a mark), and `[base]`'s
/// when asked; never what is computed.
fn dumped(e: Entry, options: DumpOptions) bool {
    return switch (e.layer) {
        .kind, .theme, .program, .mark => true,
        .base => options.base,
        .computed => false,
    };
}

/// `: d value layer, …`, in `:Style`'s order; nothing when none.
fn dumpStyle(s: *const Sheet, subject: Subject, options: DumpOptions, w: *std.Io.Writer) std.Io.Writer.Error!void {
    const v = s.style(subject);
    var first = true;
    for (s.descriptors, 0..) |name, d| {
        const e = v.entry(@fromBackingInt(@as(u16, @intCast(d)))) orelse continue;
        if (!dumped(e, options)) continue;
        try w.writeAll(if (first) ": " else ", ");
        first = false;
        // Names without their sigil, as the JSON writes them (§22.13); a
        // flag as fAB writes it, `!` when off.
        try w.writeAll(name[1..]);
        switch (e.value) {
            .flag => |on| if (!on) try w.writeByte('!'),
            else => {
                try w.writeByte(' ');
                try decoded.write(e.value, w);
            },
        }
        try w.print(" {s}", .{@tagName(e.layer)});
    }
}

/// One element's style, read a descriptor at a time. The typed readers
/// give null where the value is nil or of another sort; `label` tells nil
/// from a label the caller has no meaning for.
pub const View = struct {
    sheet: *const Sheet,
    own: []const Entry,
    rule: ?RuleIndex,

    pub fn get(v: View, d: Descriptor) ?Value {
        return if (v.entry(d)) |e| e.value else null;
    }

    /// The entry for `d`, with the layer that bound it.
    pub fn entry(v: View, d: Descriptor) ?Entry {
        if (find(v.own, d)) |e| return e;
        var it = v.rules();
        while (it.next()) |entries| if (find(entries, d)) |e| return e;
        return null;
    }

    /// The entries of the element's rule, then of each parent up.
    pub fn rules(v: View) Rules {
        return .{ .sheet = v.sheet, .at = v.rule };
    }

    pub const Rules = struct {
        sheet: *const Sheet,
        at: ?RuleIndex,

        pub fn next(it: *Rules) ?[]const Entry {
            const r = it.sheet.rule(it.at orelse return null);
            it.at = r.parent;
            return it.sheet.slice(r.entries);
        }
    };

    pub fn color(v: View, d: Descriptor) ?value.Rgba {
        return if (v.get(d)) |x| switch (x) {
            .color => |c| c,
            else => null,
        } else null;
    }

    pub fn number(v: View, d: Descriptor) ?Decimal {
        return if (v.get(d)) |x| switch (x) {
            .number => |n| n,
            else => null,
        } else null;
    }

    pub fn text(v: View, d: Descriptor) ?[]const u8 {
        return if (v.get(d)) |x| switch (x) {
            .text => |t| t,
            else => null,
        } else null;
    }

    pub fn flag(v: View, d: Descriptor) bool {
        return if (v.get(d)) |x| switch (x) {
            .flag => |f| f,
            else => false,
        } else false;
    }

    /// A label, as the caller's enum `E`: `[double-circle]` is
    /// `.double_circle`, a glyph its own spelling, `@"|>"`.
    pub fn label(v: View, comptime E: type, d: Descriptor) Label(E) {
        const name = if (v.get(d)) |x| switch (x) {
            .label => |l| l.name,
            else => return .nil,
        } else return .nil;
        inline for (comptime std.meta.fieldNames(E)) |field| {
            if (kebab(field, name)) return .{ .value = @field(E, field) };
        }
        return .{ .unknown = name };
    }
};

pub fn Label(comptime E: type) type {
    return union(enum) {
        /// Nothing there, or not a label.
        nil,
        value: E,
        /// A label the caller gives no meaning to, for it to report.
        unknown: []const u8,
    };
}

/// Whether Zig's `field` spells the label `name`, `_` for `-`.
fn kebab(field: []const u8, name: []const u8) bool {
    if (field.len != name.len) return false;
    for (field, name) |f, n| if (f != n and !(f == '_' and n == '-')) return false;
    return true;
}

fn find(entries: []const Entry, d: Descriptor) ?Entry {
    var lo: usize = 0;
    var hi: usize = entries.len;
    while (lo < hi) {
        const mid = (lo + hi) / 2;
        const at = @backingInt(entries[mid].descriptor);
        if (at == @backingInt(d)) return entries[mid];
        if (at < @backingInt(d)) lo = mid + 1 else hi = mid;
    }
    return null;
}
