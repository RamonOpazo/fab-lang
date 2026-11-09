//! The Sheet of values (statements.md §22.12, plan step 9d3): `:Style`'s
//! descriptors, a rule per diagram and set of classes present, and each
//! element's rule. A rule holds `[base]` folded by specificity; themes, a
//! diagram's own layer, tokens, computed defaults and marks come with the
//! cascade (9d4).

const std = @import("std");
const Ir = @import("../analyse/Ir.zig");
const Env = @import("../analyse/Env.zig");
const decoded = @import("../analyse/decoded.zig");
const Sheet = @import("Sheet.zig");

const Descriptor = Sheet.Descriptor;
const Entry = Sheet.Entry;

/// Fills `sheet`'s descriptors, rules, entries and elements. `reached[n]`
/// says whether some edge arrives at node n: a null node is then an end.
pub fn build(gpa: std.mem.Allocator, ir: *const Ir, env: *const Env, reached: []const bool, sheet: *Sheet) error{OutOfMemory}!void {
    var b: Builder = .{ .gpa = gpa, .env = env };
    defer b.deinit();
    errdefer b.free();
    try b.collectDescriptors();
    if (env.values.get("base")) |v| if (v.decoded) |d| switch (d) {
        .record => |r| b.base = env.records.items[@backingInt(r)],
        else => {},
    };

    const zones = ir.nodes.items(.zone);
    const own = ir.zones.items(.own);
    const nodes = try gpa.alloc(Sheet.Element, ir.nodes.len);
    b.nodes = nodes;
    for (nodes, ir.nodes.items(.kind), ir.nodes.items(.name), ir.nodes.items(.canonical), zones, reached, 0..) |*e, kind, name, canonical, zone, arrived, i| {
        var classes: Env.Classes = .initMany(&.{ .node, switch (kind) {
            .plain => .plain,
            .choice => .choice,
            .parallel => .parallel,
            .hole => .hole,
            .null_node => if (arrived) .end else .start,
        } });
        // Unnamed, and not `@`: known by its canonical end.
        const self: Ir.NodeIndex = @fromBackingInt(@as(u32, @intCast(i)));
        if (name == null and canonical != null and own[@backingInt(zone)] != self) classes.insert(.canonical);
        e.* = .{ .rule = try b.ruleFor(zone, classes) };
    }
    b.edges = try gpa.alloc(Sheet.Element, ir.edges.len);
    for (b.edges, ir.edges.items(.zone)) |*e, zone| e.* = .{ .rule = try b.ruleFor(zone, .initOne(.edge)) };
    b.cells = try gpa.alloc(Sheet.Element, ir.cells.len);
    for (b.cells, ir.cells.items(.zone)) |*e, zone| e.* = .{ .rule = try b.ruleFor(zone, .initOne(.cell)) };
    b.zones = try gpa.alloc(Sheet.Element, ir.zones.len);
    for (b.zones, 0..) |*e, z| e.* = .{ .rule = try b.ruleFor(@fromBackingInt(@as(u32, @intCast(z))), .initOne(.zone)) };

    const descriptors = try b.names.toOwnedSlice(gpa);
    errdefer gpa.free(descriptors);
    const made = try b.rules.toOwnedSlice(gpa);
    errdefer gpa.free(made);
    sheet.entries = try b.entries.toOwnedSlice(gpa);
    sheet.descriptors = descriptors;
    sheet.rules = made;
    sheet.elements = .{ .nodes = b.nodes, .edges = b.edges, .cells = b.cells, .zones = b.zones };
}

const Builder = struct {
    gpa: std.mem.Allocator,
    env: *const Env,
    base: ?decoded.Record = null,
    names: std.ArrayList([]const u8) = .empty,
    by_name: std.StringHashMapUnmanaged(Descriptor) = .empty,
    rules: std.ArrayList(Sheet.Rule) = .empty,
    entries: std.ArrayList(Entry) = .empty,
    made: std.AutoHashMapUnmanaged(Key, Sheet.RuleIndex) = .empty,
    nodes: []Sheet.Element = &.{},
    edges: []Sheet.Element = &.{},
    cells: []Sheet.Element = &.{},
    zones: []Sheet.Element = &.{},

    const Key = struct { zone: u32, classes: u16 };

    fn deinit(b: *Builder) void {
        b.by_name.deinit(b.gpa);
        b.made.deinit(b.gpa);
        b.names.deinit(b.gpa);
        b.rules.deinit(b.gpa);
        b.entries.deinit(b.gpa);
    }

    /// On failure, the element tables too, which `build` hands over last.
    fn free(b: *Builder) void {
        b.gpa.free(b.nodes);
        b.gpa.free(b.edges);
        b.gpa.free(b.cells);
        b.gpa.free(b.zones);
    }

    /// `:Style`'s descriptors in declaration order: the prelude's, then the
    /// program's, each by its token.
    fn collectDescriptors(b: *Builder) error{OutOfMemory}!void {
        const style = (b.env.type_table.get(":Style") orelse return).index;
        const Found = struct { name: []const u8, prelude: bool, token: u32 };
        var found: std.ArrayList(Found) = .empty;
        defer found.deinit(b.gpa);
        var it = b.env.functions.iterator();
        while (it.next()) |kv| if (kv.value_ptr.record == style) try found.append(b.gpa, .{
            .name = kv.key_ptr.*,
            .prelude = kv.value_ptr.prelude,
            .token = kv.value_ptr.token,
        });
        std.mem.sort(Found, found.items, {}, struct {
            fn lessThan(_: void, l: Found, r: Found) bool {
                if (l.prelude != r.prelude) return l.prelude;
                return l.token < r.token;
            }
        }.lessThan);
        for (found.items, 0..) |f, i| {
            try b.names.append(b.gpa, f.name);
            try b.by_name.put(b.gpa, f.name, @fromBackingInt(@as(u16, @intCast(i))));
        }
    }

    /// The rule of `zone`'s elements of `classes`, made the first time.
    fn ruleFor(b: *Builder, zone: Ir.ZoneIndex, classes: Env.Classes) error{OutOfMemory}!Sheet.RuleIndex {
        const key: Key = .{ .zone = @backingInt(zone), .classes = bits(classes) };
        const gop = try b.made.getOrPut(b.gpa, key);
        if (gop.found_existing) return gop.value_ptr.*;
        const index: Sheet.RuleIndex = @fromBackingInt(@as(u32, @intCast(b.rules.items.len)));
        gop.value_ptr.* = index;
        const start: u32 = @intCast(b.entries.items.len);
        try b.fold(classes);
        try b.rules.append(b.gpa, .{
            .zone = zone,
            .classes = classes,
            .entries = .{ .start = start, .end = @intCast(b.entries.items.len) },
        });
        return index;
    }

    /// `[base]`'s bindings for `classes`, the most specific winning, and of
    /// one rank the later (statements.md §22.4): appended in descriptor
    /// order.
    fn fold(b: *Builder, classes: Env.Classes) error{OutOfMemory}!void {
        const base = b.base orelse return;
        const Best = struct { rank: u8, value: decoded.Value };
        const best = try b.gpa.alloc(?Best, b.names.items.len);
        defer b.gpa.free(best);
        @memset(best, null);
        for (base.bindings) |binding| {
            if (binding.key != null) continue;
            const meet = (binding.classes orelse continue).intersectWith(classes);
            if (meet.count() == 0) continue;
            const d = b.by_name.get(binding.descriptor) orelse continue;
            const r = rank(meet);
            const slot = &best[@backingInt(d)];
            if (slot.* == null or r >= slot.*.?.rank) slot.* = .{ .rank = r, .value = binding.value };
        }
        for (best, 0..) |slot, i| if (slot) |s| try b.entries.append(b.gpa, .{
            .descriptor = @fromBackingInt(@as(u16, @intCast(i))),
            .value = s.value,
        });
    }
};

/// The most specific of `classes`: `&node` < the kinds < `&canonical` <
/// `&hole`.
fn rank(classes: Env.Classes) u8 {
    var r: u8 = 0;
    var it = classes.iterator();
    while (it.next()) |c| r = @max(r, @as(u8, switch (c) {
        .node, .edge, .cell, .zone => 0,
        .plain, .choice, .parallel, .start, .end => 1,
        .canonical => 2,
        .hole => 3,
    }));
    return r;
}

fn bits(classes: Env.Classes) u16 {
    var out: u16 = 0;
    var it = classes.iterator();
    while (it.next()) |c| out |= @as(u16, 1) << @intCast(@backingInt(c));
    return out;
}
