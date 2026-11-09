//! The cascade (statements.md §22.4, §22.11, §22.12; plan step 9d4): the
//! Sheet of values, folded from the layers, lowest first:
//!
//!   computed  <  [base]  <  the diagram's themes, left to right  <  the program  <  marks
//!
//! A *rule*, one per diagram and set of classes present, folds `[base]`,
//! the diagram's themes and the program's class bindings, the most specific
//! winning within a layer and of one rank the later. Within the program, a
//! class at the top level (every diagram's) ranks below a class inside the
//! diagram, each by the classes' own ranks: `&node` < the kinds <
//! `&canonical` < `&hole`. An *element* holds its own bindings, then what is
//! computed where the result is still nil (labels by name, a cell's arrow by
//! level), then its marks. Tokens are resolved per diagram, one step, in
//! rules and elements alike.

const std = @import("std");
const Ir = @import("../analyse/Ir.zig");
const Env = @import("../analyse/Env.zig");
const decoded = @import("../analyse/decoded.zig");
const layers = @import("../analyse/layers.zig");
const Sheet = @import("Sheet.zig");

const Descriptor = Sheet.Descriptor;
const Entry = Sheet.Entry;
const Value = decoded.Value;
const Mark = Sheet.Mark;
const Layer = Sheet.Layer;

/// What the cascade reads besides the IR: the environment (`[base]`, the
/// themes, the bundles) and the program's layers.
pub const Inputs = struct {
    env: *const Env,
    bindings: []const layers.Binding = &.{},
    tokens: []const layers.Token = &.{},
};

/// Each element's worst issue, and each diagram's mark.
pub const Marks = struct {
    nodes: []const ?Mark,
    edges: []const ?Mark,
    cells: []const ?Mark,
    zones: []const ZoneMark,
};

/// How a diagram is drawn for its issues: a border in the colour of the most
/// severe, and the caption "unsupported" while any is unsupported.
pub const ZoneMark = struct {
    border: ?Mark = null,
    unsupported: bool = false,
};

/// Fills `sheet`'s Sheet of values. `reached[n]` says whether some edge
/// arrives at node n: a null node is then an end.
pub fn build(gpa: std.mem.Allocator, ir: *const Ir, in: Inputs, reached: []const bool, marks: Marks, sheet: *Sheet) error{OutOfMemory}!void {
    var b: Builder = .{ .gpa = gpa, .arena = sheet.arena.allocator(), .ir = ir, .in = in };
    defer b.deinit();
    errdefer b.free();
    try b.collectDescriptors();
    b.base = record(in.env, in.env.values.get("base"));
    try b.sortBindings();

    b.zone_tokens = try gpa.alloc([]const decoded.Token, ir.zones.len);
    @memset(b.zone_tokens, &.{});
    b.zone_themes = try gpa.alloc([]const decoded.Record, ir.zones.len);
    @memset(b.zone_themes, &.{});
    for (0..ir.zones.len) |z| try b.prepareZone(@fromBackingInt(@as(u32, @intCast(z))));

    const zones = ir.nodes.items(.zone);
    const own = ir.zones.items(.own);
    b.nodes = try gpa.alloc(Sheet.Element, ir.nodes.len);
    for (b.nodes, ir.nodes.items(.kind), ir.nodes.items(.name), ir.nodes.items(.canonical), zones, reached, marks.nodes, 0..) |*e, kind, name, canonical, zone, arrived, mark, i| {
        var classes: Env.Classes = .initMany(&.{ .node, switch (kind) {
            .plain => .plain,
            .choice => .choice,
            .parallel => .parallel,
            .hole => .hole,
            .null_node => if (arrived) .end else .start,
        } });
        // Labelled by its canonical end (spec, Subjects and classes): unnamed,
        // not `@`, and its label, resolved without `&canonical`, left to be
        // computed. A mark's `:label ""` keeps it out; `&choice :label []`
        // brings it in.
        const self: Ir.NodeIndex = @fromBackingInt(@as(u32, @intCast(i)));
        if (name == null and canonical != null and own[@backingInt(zone)] != self and
            try b.labelComputed(.{ .node = self }, try b.ruleFor(zone, classes))) classes.insert(.canonical);
        const computed: Value = if (name) |n|
            .{ .text = withoutSigil(ir.string(n)) }
        else if (own[@backingInt(zone)] == self)
            // `@` stands for the diagram itself (statements.md §20).
            .{ .text = ir.string(ir.zones.items(.name)[@backingInt(zone)]) }
        else if (canonical) |end|
            .{ .text = try b.canonicalLabel(end) }
        else
            .{ .text = "" };
        e.* = try b.element(.{ .node = self }, zone, classes, computed, mark, false);
    }
    b.edges = try gpa.alloc(Sheet.Element, ir.edges.len);
    for (b.edges, ir.edges.items(.zone), ir.edges.items(.name), marks.edges, 0..) |*e, zone, name, mark, i| {
        e.* = try b.element(.{ .edge = @fromBackingInt(@as(u32, @intCast(i))) }, zone, .initOne(.edge), .{ .text = ir.string(name) }, mark, false);
    }
    b.cells = try gpa.alloc(Sheet.Element, ir.cells.len);
    for (b.cells, ir.cells.items(.zone), ir.cells.items(.name), ir.cells.items(.level), marks.cells, 0..) |*e, zone, name, level, mark, i| {
        b.level = level;
        e.* = try b.element(.{ .cell = @fromBackingInt(@as(u32, @intCast(i))) }, zone, .initOne(.cell), .{ .text = ir.string(name) }, mark, false);
    }
    b.zones = try gpa.alloc(Sheet.Element, ir.zones.len);
    for (b.zones, ir.zones.items(.name), marks.zones, 0..) |*e, name, mark, z| {
        b.zone_mark = mark;
        const zone: Ir.ZoneIndex = @fromBackingInt(@as(u32, @intCast(z)));
        e.* = try b.element(.{ .zone = zone }, zone, .initOne(.zone), .{ .text = ir.string(name) }, mark.border, true);
    }

    try b.prune();
    const descriptors = try b.names.toOwnedSlice(gpa);
    errdefer gpa.free(descriptors);
    const made = try b.rules.toOwnedSlice(gpa);
    errdefer gpa.free(made);
    sheet.entries = try b.entries.toOwnedSlice(gpa);
    sheet.descriptors = descriptors;
    sheet.rules = made;
    sheet.tokens = b.zone_tokens;
    if (b.base) |base| sheet.base_tokens = base.tokens;
    sheet.elements = .{ .nodes = b.nodes, .edges = b.edges, .cells = b.cells, .zones = b.zones };
}

/// The record a named value is, if it is one.
fn record(env: *const Env, v: ?Env.Value) ?decoded.Record {
    const d = (v orelse return null).decoded orelse return null;
    return switch (d) {
        .record => |r| env.records.items[@backingInt(r)],
        else => null,
    };
}

/// One step of the cascade's precedence: a layer, then a rank in it.
const Precedence = u32;

/// A descriptor's value so far, and the precedence it was bound at.
const Slot = ?struct { at: Precedence, value: Value, layer: Layer };

const Builder = struct {
    gpa: std.mem.Allocator,
    /// The Sheet's: what outlives the pass.
    arena: std.mem.Allocator,
    ir: *const Ir,
    in: Inputs,
    base: ?decoded.Record = null,
    names: std.ArrayList([]const u8) = .empty,
    by_name: std.StringHashMapUnmanaged(Descriptor) = .empty,
    rules: std.ArrayList(Sheet.Rule) = .empty,
    entries: std.ArrayList(Entry) = .empty,
    made: std.AutoHashMapUnmanaged(Key, Sheet.RuleIndex) = .empty,
    /// The program's bindings by what they describe, each list in source
    /// order: classes at the top level, classes in a diagram, elements.
    top: std.ArrayList(u32) = .empty,
    in_zone: std.AutoHashMapUnmanaged(u32, std.ArrayList(u32)) = .empty,
    own: std.AutoHashMapUnmanaged(SubjectKey, std.ArrayList(u32)) = .empty,
    zone_themes: [][]const decoded.Record = &.{},
    zone_tokens: [][]const decoded.Token = &.{},
    nodes: []Sheet.Element = &.{},
    edges: []Sheet.Element = &.{},
    cells: []Sheet.Element = &.{},
    zones: []Sheet.Element = &.{},
    /// The cell being made, for its arrow; the zone, for its caption.
    level: u32 = 0,
    zone_mark: ZoneMark = .{},

    const Key = struct { zone: u32, classes: u16 };
    const SubjectKey = struct { table: u8, index: u32 };

    fn deinit(b: *Builder) void {
        b.by_name.deinit(b.gpa);
        b.made.deinit(b.gpa);
        b.names.deinit(b.gpa);
        b.rules.deinit(b.gpa);
        b.entries.deinit(b.gpa);
        b.top.deinit(b.gpa);
        var zit = b.in_zone.valueIterator();
        while (zit.next()) |l| l.deinit(b.gpa);
        b.in_zone.deinit(b.gpa);
        var oit = b.own.valueIterator();
        while (oit.next()) |l| l.deinit(b.gpa);
        b.own.deinit(b.gpa);
        b.gpa.free(b.zone_themes);
    }

    /// On failure, the tables `build` hands over last.
    fn free(b: *Builder) void {
        b.gpa.free(b.zone_tokens);
        b.gpa.free(b.nodes);
        b.gpa.free(b.edges);
        b.gpa.free(b.cells);
        b.gpa.free(b.zones);
    }

    /// `:Style`'s descriptors in declaration order: the prelude's, then the
    /// program's, each by its token.
    fn collectDescriptors(b: *Builder) error{OutOfMemory}!void {
        const style = (b.in.env.type_table.get(":Style") orelse return).index;
        const Found = struct { name: []const u8, prelude: bool, token: u32 };
        var found: std.ArrayList(Found) = .empty;
        defer found.deinit(b.gpa);
        var it = b.in.env.functions.iterator();
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

    /// The program's bindings, by what they describe. A table's entries
    /// (`:lemma.[a]`) are no style's.
    fn sortBindings(b: *Builder) error{OutOfMemory}!void {
        for (b.in.bindings, 0..) |binding, i| {
            if (binding.key != null) continue;
            const index: u32 = @intCast(i);
            const key: SubjectKey = switch (binding.subject) {
                .class => |c| {
                    if (c.zone) |z| {
                        const gop = try b.in_zone.getOrPut(b.gpa, @backingInt(z));
                        if (!gop.found_existing) gop.value_ptr.* = .empty;
                        try gop.value_ptr.append(b.gpa, index);
                    } else try b.top.append(b.gpa, index);
                    continue;
                },
                .node => |n| .{ .table = 0, .index = @backingInt(n) },
                .edge => |e| .{ .table = 1, .index = @backingInt(e) },
                .cell => |x| .{ .table = 2, .index = @backingInt(x) },
                .zone => |z| .{ .table = 3, .index = @backingInt(z) },
            };
            const gop = try b.own.getOrPut(b.gpa, key);
            if (!gop.found_existing) gop.value_ptr.* = .empty;
            try gop.value_ptr.append(b.gpa, index);
        }
    }

    fn subjectKey(subject: Sheet.Subject) SubjectKey {
        return switch (subject) {
            .node => |n| .{ .table = 0, .index = @backingInt(n) },
            .edge => |e| .{ .table = 1, .index = @backingInt(e) },
            .cell => |x| .{ .table = 2, .index = @backingInt(x) },
            .zone => |z| .{ .table = 3, .index = @backingInt(z) },
        };
    }

    /// A diagram's themes, includes first, and its tokens: `[base]`'s, its
    /// themes', its own.
    fn prepareZone(b: *Builder, zone: Ir.ZoneIndex) error{OutOfMemory}!void {
        var themes: std.ArrayList(decoded.Record) = .empty;
        defer themes.deinit(b.gpa);
        if (b.themeValue(zone)) |v| try b.expand(v, &themes, 8);
        b.zone_themes[@backingInt(zone)] = try b.arena.dupe(decoded.Record, themes.items);

        var tokens: std.ArrayList(decoded.Token) = .empty;
        defer tokens.deinit(b.gpa);
        if (b.base) |base| for (base.tokens) |t| try bindToken(b.gpa, &tokens, t);
        for (themes.items) |theme| for (theme.tokens) |t| try bindToken(b.gpa, &tokens, t);
        for (b.in.tokens) |t| if (t.zone == zone) try bindToken(b.gpa, &tokens, t.token);
        b.zone_tokens[@backingInt(zone)] = try b.arena.dupe(decoded.Token, tokens.items);
    }

    /// The diagram's `:theme`, read as any descriptor is, below its themes:
    /// `[base]`, a class at the top level, a class in the diagram, the
    /// diagram itself.
    fn themeValue(b: *Builder, zone: Ir.ZoneIndex) ?Value {
        var found: ?Value = null;
        if (b.base) |base| for (base.bindings) |binding| {
            if (binding.classes) |c| if (c.contains(.zone) and std.mem.eql(u8, binding.descriptor, ":theme")) {
                found = binding.value;
            };
        };
        const lists = [_][]const u32{
            b.top.items,
            if (b.in_zone.get(@backingInt(zone))) |l| l.items else &.{},
            if (b.own.get(subjectKey(.{ .zone = zone }))) |l| l.items else &.{},
        };
        for (lists, 0..) |list, k| for (list) |i| {
            const binding = b.in.bindings[i];
            if (k < 2 and !binding.subject.class.classes.contains(.zone)) continue;
            if (std.mem.eql(u8, binding.descriptor, ":theme")) found = binding.value;
        };
        return found;
    }

    /// `[dark/print]`: each record, after the themes its own `:theme`
    /// includes.
    fn expand(b: *Builder, v: Value, out: *std.ArrayList(decoded.Record), depth: u32) error{OutOfMemory}!void {
        if (depth == 0) return;
        const items: []const Value = switch (v) {
            .elements => |es| es,
            .record => &.{v},
            else => return,
        };
        for (items) |item| switch (item) {
            .record => |r| {
                const theme = b.in.env.records.items[@backingInt(r)];
                for (theme.bindings) |binding| if (std.mem.eql(u8, binding.descriptor, ":theme")) try b.expand(binding.value, out, depth - 1);
                try out.append(b.gpa, theme);
            },
            else => {},
        };
    }

    /// The rule of `zone`'s elements of `classes`, made the first time.
    fn ruleFor(b: *Builder, zone: Ir.ZoneIndex, classes: Env.Classes) error{OutOfMemory}!Sheet.RuleIndex {
        const key: Key = .{ .zone = @backingInt(zone), .classes = bits(classes) };
        const gop = try b.made.getOrPut(b.gpa, key);
        if (gop.found_existing) return gop.value_ptr.*;
        const index: Sheet.RuleIndex = @fromBackingInt(@as(u32, @intCast(b.rules.items.len)));
        gop.value_ptr.* = index;

        const slots = try b.gpa.alloc(Slot, b.names.items.len);
        defer b.gpa.free(slots);
        @memset(slots, null);
        // [base] is layer 0, each theme one more, the program the last.
        if (b.base) |base| try b.foldRecord(slots, base, classes, 0);
        const themes = b.zone_themes[@backingInt(zone)];
        for (themes, 1..) |theme, at| try b.foldRecord(slots, theme, classes, @intCast(at));
        const program: Precedence = @intCast(themes.len + 1);
        for (b.top.items) |i| try b.foldProgram(slots, i, classes, program, 0);
        if (b.in_zone.get(@backingInt(zone))) |list| for (list.items) |i| try b.foldProgram(slots, i, classes, program, 4);

        const start: u32 = @intCast(b.entries.items.len);
        try b.emit(slots, zone);
        try b.rules.append(b.gpa, .{
            .zone = zone,
            .classes = classes,
            .entries = .{ .start = start, .end = @intCast(b.entries.items.len) },
        });
        return index;
    }

    fn foldRecord(b: *Builder, slots: []Slot, r: decoded.Record, classes: Env.Classes, layer: Precedence) error{OutOfMemory}!void {
        for (r.bindings) |binding| {
            if (binding.key != null) continue;
            const meet = (binding.classes orelse continue).intersectWith(classes);
            if (meet.count() == 0) continue;
            try b.bind(slots, binding.descriptor, binding.value, layer * 16 + rank(meet), if (layer == 0) .base else .theme, 8);
        }
    }

    /// A program binding of a class, `shift` above the top level's when it
    /// is a diagram's.
    fn foldProgram(b: *Builder, slots: []Slot, i: u32, classes: Env.Classes, layer: Precedence, shift: u32) error{OutOfMemory}!void {
        const binding = b.in.bindings[i];
        const meet = binding.subject.class.classes.intersectWith(classes);
        if (meet.count() == 0) return;
        try b.bind(slots, binding.descriptor, binding.value, layer * 16 + shift + rank(meet), .program, 8);
    }

    /// Binds `descriptor` in `slots` at `at`, unless something more specific
    /// was bound. A bundle binds its body in its place.
    fn bind(b: *Builder, slots: []Slot, descriptor: []const u8, v: Value, at: Precedence, layer: Layer, depth: u32) error{OutOfMemory}!void {
        if (b.by_name.get(descriptor)) |d| {
            const slot = &slots[@backingInt(d)];
            if (slot.* == null or at >= slot.*.?.at) slot.* = .{ .at = at, .value = v, .layer = layer };
            return;
        }
        const f = b.in.env.functions.get(descriptor) orelse return;
        if (!f.bundle or depth == 0) return;
        if (v != .flag or !v.flag) return;
        const body = b.in.env.records.items[@backingInt(f.body orelse return)];
        for (body.bindings) |binding| try b.bind(slots, binding.descriptor, binding.value, at, layer, depth - 1);
    }

    /// The bound slots as entries, in descriptor order, tokens resolved.
    /// `:theme` is the cascade's, no element's style.
    fn emit(b: *Builder, slots: []const Slot, zone: Ir.ZoneIndex) error{OutOfMemory}!void {
        for (slots, 0..) |slot, i| if (slot) |s| {
            if (std.mem.eql(u8, b.names.items[i], ":theme")) continue;
            try b.entries.append(b.gpa, .{
                .descriptor = @fromBackingInt(@as(u16, @intCast(i))),
                .value = try b.resolve(s.value, zone),
                .layer = s.layer,
            });
        };
    }

    /// Drops the rules no element names (the `&canonical` check makes some
    /// on the way), and the entries only they held.
    fn prune(b: *Builder) error{OutOfMemory}!void {
        const tables = [_][]Sheet.Element{ b.nodes, b.edges, b.cells, b.zones };
        const renumber = try b.gpa.alloc(?Sheet.RuleIndex, b.rules.items.len);
        defer b.gpa.free(renumber);
        @memset(renumber, null);
        for (tables) |table| for (table) |e| {
            renumber[@backingInt(e.rule)] = e.rule;
        };
        var entries: std.ArrayList(Entry) = .empty;
        errdefer entries.deinit(b.gpa);
        var rules: std.ArrayList(Sheet.Rule) = .empty;
        errdefer rules.deinit(b.gpa);
        for (b.rules.items, renumber) |r, *new| if (new.* != null) {
            new.* = @fromBackingInt(@as(u32, @intCast(rules.items.len)));
            const start: u32 = @intCast(entries.items.len);
            try entries.appendSlice(b.gpa, b.entries.items[r.entries.start..r.entries.end]);
            try rules.append(b.gpa, .{ .zone = r.zone, .classes = r.classes, .entries = .{ .start = start, .end = @intCast(entries.items.len) } });
        };
        for (tables) |table| for (table) |*e| {
            e.rule = renumber[@backingInt(e.rule)].?;
            const start: u32 = @intCast(entries.items.len);
            try entries.appendSlice(b.gpa, b.entries.items[e.own.start..e.own.end]);
            e.own = .{ .start = start, .end = @intCast(entries.items.len) };
        };
        b.entries.deinit(b.gpa);
        b.entries = entries;
        b.rules.deinit(b.gpa);
        b.rules = rules;
    }

    /// A label a token of `zone` binds, replaced by its value, once: in a
    /// tuple too.
    fn resolve(b: *Builder, v: Value, zone: Ir.ZoneIndex) error{OutOfMemory}!Value {
        switch (v) {
            .label => |l| {
                if (l.inverted) return v;
                for (b.zone_tokens[@backingInt(zone)]) |t| if (std.mem.eql(u8, t.label, l.name)) return t.value;
                return v;
            },
            .elements => |es| {
                const out = try b.arena.alloc(Value, es.len);
                for (es, out) |e, *o| o.* = try b.resolve(e, zone);
                return .{ .elements = out };
            },
            else => return v,
        }
    }

    /// An element: its rule, its own bindings, what is computed where the
    /// result is nil, and its marks.
    fn element(b: *Builder, subject: Sheet.Subject, zone: Ir.ZoneIndex, classes: Env.Classes, label: Value, mark: ?Mark, is_zone: bool) error{OutOfMemory}!Sheet.Element {
        // The diagram's rule first, for `:marks`: making a rule appends
        // entries, so both are made before any slice of them is taken.
        const zone_rule: ZoneRule = .{ .rule = try b.ruleFor(zone, .initOne(.zone)), .zone = zone };
        const r = try b.ruleFor(zone, classes);
        const slots = try b.gpa.alloc(Slot, b.names.items.len);
        defer b.gpa.free(slots);
        @memset(slots, null);
        if (b.own.get(subjectKey(subject))) |list| for (list.items) |i| {
            const binding = b.in.bindings[i];
            try b.bind(slots, binding.descriptor, binding.value, 0, .program, 8);
        };

        const rule_entries = b.entries.items[b.rules.items[@backingInt(r)].entries.start..b.rules.items[@backingInt(r)].entries.end];
        const merged = struct {
            fn get(s: []const Slot, re: []const Entry, d: Descriptor) ?Value {
                if (s[@backingInt(d)]) |x| return x.value;
                for (re) |e| if (e.descriptor == d) return e.value;
                return null;
            }
        }.get;
        if (b.by_name.get(":label")) |d| if (isNil(merged(slots, rule_entries, d))) {
            slots[@backingInt(d)] = .{ .at = 0, .value = label, .layer = .computed };
        };
        if (subject == .cell) if (b.by_name.get(":arrow")) |d| if (isNil(merged(slots, rule_entries, d))) {
            const arrow = try b.arena.alloc(Value, 3);
            arrow[0] = .nil;
            arrow[1] = .{ .label = .{ .name = if (b.level <= 2) "double" else "triple" } };
            arrow[2] = .{ .label = .{ .name = ">" } };
            slots[@backingInt(d)] = .{ .at = 0, .value = .{ .elements = arrow }, .layer = .computed };
        };

        // Marks, unless the diagram draws none (`:marks []`).
        const drawn = if (b.by_name.get(":marks")) |d| !isNil(zone_rule.get(d, b)) else true;
        if (drawn) {
            if (is_zone) {
                if (b.zone_mark.border) |m| if (b.by_name.get(":stroke")) |d| {
                    slots[@backingInt(d)] = .{ .at = 0, .value = .{ .label = .{ .name = tokenOf(m) } }, .layer = .mark };
                };
                if (b.zone_mark.unsupported) if (b.by_name.get(":caption")) |d| {
                    slots[@backingInt(d)] = .{ .at = 0, .value = .{ .text = "unsupported" }, .layer = .mark };
                };
            } else if (mark) |m| {
                const colour: Value = .{ .label = .{ .name = tokenOf(m) } };
                if (b.by_name.get(":stroke")) |d| slots[@backingInt(d)] = .{ .at = 0, .value = colour, .layer = .mark };
                // A solid shape's fill is its line.
                if (b.by_name.get(":shape")) |d| if (merged(slots, rule_entries, d)) |shape| if (shape == .label and solid(shape.label.name)) {
                    if (b.by_name.get(":fill")) |f| slots[@backingInt(f)] = .{ .at = 0, .value = colour, .layer = .mark };
                };
            }
        }

        const start: u32 = @intCast(b.entries.items.len);
        try b.emit(slots, zone);
        return .{ .rule = r, .own = .{ .start = start, .end = @intCast(b.entries.items.len) }, .mark = mark };
    }

    /// Whether `subject`'s `:label`, its own over `r`'s, is nil: computed.
    fn labelComputed(b: *Builder, subject: Sheet.Subject, r: Sheet.RuleIndex) error{OutOfMemory}!bool {
        const d = b.by_name.get(":label") orelse return false;
        const slots = try b.gpa.alloc(Slot, b.names.items.len);
        defer b.gpa.free(slots);
        @memset(slots, null);
        if (b.own.get(subjectKey(subject))) |list| for (list.items) |i| {
            const binding = b.in.bindings[i];
            try b.bind(slots, binding.descriptor, binding.value, 0, .program, 8);
        };
        if (slots[@backingInt(d)]) |s| return s.value == .nil;
        const rule = b.rules.items[@backingInt(r)];
        for (b.entries.items[rule.entries.start..rule.entries.end]) |e| if (e.descriptor == d) return e.value == .nil;
        return true;
    }

    /// A diagram's `&zone` rule, read for `:marks`.
    const ZoneRule = struct {
        rule: Sheet.RuleIndex,
        zone: Ir.ZoneIndex,

        /// The diagram's own binding of `d`, else its rule's.
        fn get(z: ZoneRule, d: Descriptor, b: *Builder) ?Value {
            if (b.own.get(subjectKey(.{ .zone = z.zone }))) |list| {
                var found: ?Value = null;
                for (list.items) |i| if (std.mem.eql(u8, b.in.bindings[i].descriptor, b.names.items[@backingInt(d)])) {
                    found = b.in.bindings[i].value;
                };
                if (found) |v| return v;
            }
            const r = b.rules.items[@backingInt(z.rule)];
            for (b.entries.items[r.entries.start..r.entries.end]) |e| if (e.descriptor == d) return e.value;
            return null;
        }
    };

    /// `+f` for a domain, `f+` for a codomain.
    fn canonicalLabel(b: *Builder, end: Ir.End) error{OutOfMemory}![]const u8 {
        const name = b.ir.string(b.ir.edges.items(.name)[@backingInt(end.edge)]);
        return switch (end.side) {
            .dom => std.fmt.allocPrint(b.arena, "+{s}", .{name}),
            .cod => std.fmt.allocPrint(b.arena, "{s}+", .{name}),
        };
    }
};

/// A token bound again replaces the binding before it.
fn bindToken(gpa: std.mem.Allocator, tokens: *std.ArrayList(decoded.Token), t: decoded.Token) error{OutOfMemory}!void {
    for (tokens.items) |*old| if (std.mem.eql(u8, old.label, t.label)) {
        old.value = t.value;
        return;
    };
    try tokens.append(gpa, t);
}

fn isNil(v: ?Value) bool {
    return v == null or v.? == .nil;
}

/// The token a mark is drawn in.
fn tokenOf(m: Mark) []const u8 {
    return switch (m) {
        .unsupported => "unsupported",
        .warning => "warning",
        .@"error" => "error",
    };
}

/// Shapes whose fill is their line: a dot, a bar, an end.
fn solid(shape: []const u8) bool {
    for ([_][]const u8{ "point", "bar", "bullseye" }) |s| if (std.mem.eql(u8, s, shape)) return true;
    return false;
}

/// `#Valid` is labelled `Valid`.
fn withoutSigil(name: []const u8) []const u8 {
    return if (name.len > 0 and name[0] == '#') name[1..] else name;
}

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
