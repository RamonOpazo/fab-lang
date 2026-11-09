//! The product of the style pass: a resolved Style for every node, edge and
//! zone of an IR, the way a style sheet maps elements to styles.
//!
//! Made by Styler.zig. A Sheet borrows the IR and the environment, which
//! must outlive it, and owns its tables and the labels that aren't in the
//! IR's strings.
//!
//! Two forms live here while the style pass moves (plan step 9d): the typed
//! tables `nodes`, `edges` and `zones`, which renderers read until 9d5, and
//! the Sheet of values (statements.md §22.12). The prelude is its only
//! schema: a style is a list of entries, a descriptor of `:Style` and its
//! value, resolved. Styles are shared the way the author shares them: a
//! *rule* per diagram and set of classes present holds what those make, and
//! each element names its rule and holds only its own entries. `style`
//! merges the two.

const std = @import("std");
const Ir = @import("../analyse/Ir.zig");
const Env = @import("../analyse/Env.zig");
const Decimal = @import("../analyse/Decimal.zig");
const value = @import("../analyse/value.zig");
const decoded = @import("../analyse/decoded.zig");
const Style = @import("Style.zig");
const Value = decoded.Value;

const Sheet = @This();

ir: *const Ir,
nodes: []const Style,
edges: []const Style,
zones: []const Style,
/// Labels that aren't in the IR's strings: the canonical ends, `f+` and `+f`.
labels: []const u8,

/// `:Style`'s descriptors, in the order they are declared, the prelude's
/// first: what a `Descriptor` indexes. Names borrow the environment's
/// sources.
descriptors: []const []const u8 = &.{},
rules: []const Rule = &.{},
/// Every rule's and element's entries, each list sorted by descriptor.
entries: []const Entry = &.{},
/// Each element's rule and own entries, indexed as the IR's tables.
elements: Elements = .{},
gpa: std.mem.Allocator,

/// A descriptor of `:Style`, by its place in `descriptors`.
pub const Descriptor = enum(u16) { _ };

/// A descriptor and the value it resolves to.
pub const Entry = struct { descriptor: Descriptor, value: Value };

/// Entries `start..end` of `entries`.
pub const Span = struct { start: u32 = 0, end: u32 = 0 };

/// The style a diagram's elements of one set of classes share: `G`'s
/// `&node, &choice`.
pub const Rule = struct { zone: Ir.ZoneIndex, classes: Env.Classes, entries: Span };

pub const RuleIndex = enum(u32) { _ };

pub const Element = struct { rule: RuleIndex, own: Span = .{} };

pub const Elements = struct {
    nodes: []const Element = &.{},
    edges: []const Element = &.{},
    cells: []const Element = &.{},
    zones: []const Element = &.{},
};

/// An element of the IR, of any table.
pub const Subject = union(enum) {
    node: Ir.NodeIndex,
    edge: Ir.EdgeIndex,
    cell: Ir.CellIndex,
    zone: Ir.ZoneIndex,
};

pub fn deinit(s: *Sheet) void {
    s.gpa.free(s.nodes);
    s.gpa.free(s.edges);
    s.gpa.free(s.zones);
    s.gpa.free(s.labels);
    s.gpa.free(s.descriptors);
    s.gpa.free(s.rules);
    s.gpa.free(s.entries);
    s.gpa.free(s.elements.nodes);
    s.gpa.free(s.elements.edges);
    s.gpa.free(s.elements.cells);
    s.gpa.free(s.elements.zones);
    s.* = undefined;
}

/// The descriptor named `name`, `:` included; null when `:Style` has none.
/// A renderer looks up the names it draws once.
pub fn descriptor(s: *const Sheet, name: []const u8) ?Descriptor {
    for (s.descriptors, 0..) |d, i| if (std.mem.eql(u8, d, name)) return @fromBackingInt(@as(u16, @intCast(i)));
    return null;
}

pub fn rule(s: *const Sheet, r: RuleIndex) Rule {
    return s.rules[@backingInt(r)];
}

/// The style of `subject`: its own entries over its rule's.
pub fn style(s: *const Sheet, subject: Subject) View {
    const e = switch (subject) {
        .node => |n| s.elements.nodes[@backingInt(n)],
        .edge => |x| s.elements.edges[@backingInt(x)],
        .cell => |x| s.elements.cells[@backingInt(x)],
        .zone => |z| s.elements.zones[@backingInt(z)],
    };
    return .{ .own = s.slice(e.own), .rule = s.slice(s.rule(e.rule).entries) };
}

pub fn slice(s: *const Sheet, span: Span) []const Entry {
    return s.entries[span.start..span.end];
}

/// One element's style, read a descriptor at a time. The typed readers
/// give null where the value is nil or of another sort; `label` tells nil
/// from a label the caller has no meaning for.
pub const View = struct {
    own: []const Entry,
    rule: []const Entry,

    pub fn get(v: View, d: Descriptor) ?Value {
        return find(v.own, d) orelse find(v.rule, d);
    }

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

fn find(entries: []const Entry, d: Descriptor) ?Value {
    var lo: usize = 0;
    var hi: usize = entries.len;
    while (lo < hi) {
        const mid = (lo + hi) / 2;
        const at = @backingInt(entries[mid].descriptor);
        if (at == @backingInt(d)) return entries[mid].value;
        if (at < @backingInt(d)) lo = mid + 1 else hi = mid;
    }
    return null;
}

pub fn node(s: *const Sheet, n: Ir.NodeIndex) Style {
    return s.nodes[@backingInt(n)];
}

pub fn edge(s: *const Sheet, e: Ir.EdgeIndex) Style {
    return s.edges[@backingInt(e)];
}

pub fn zone(s: *const Sheet, z: Ir.ZoneIndex) Style {
    return s.zones[@backingInt(z)];
}

/// How a zone appears: flat, a cluster, one node or a table.
pub fn drawnAs(s: *const Sheet, z: Ir.ZoneIndex) Style.As {
    return s.zones[@backingInt(z)].as;
}

/// Whether a zone draws a border or background around its contents. A
/// cluster has neither unless the program gives it a stroke or a fill.
pub fn isFramed(s: *const Sheet, z: Ir.ZoneIndex) bool {
    const drawn = s.zones[@backingInt(z)];
    return drawn.stroke != null or drawn.fill != null;
}
