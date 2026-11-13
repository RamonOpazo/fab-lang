//! The cascade (statements.md §22.4, §22.11, §22.12; plan step 9d4): the
//! Sheet of values, folded from the layers, lowest first:
//!
//!   computed  <  [base]  <  the kind's theme  <  the diagram's themes, left to right  <  the program  <  marks
//!
//! A kind's theme (statements.md §24.3) is the first theme of the diagram
//! that states the kind, so it passes down with the diagram's layers.
//!
//! A diagram held by others (statements.md §23.2) has its containers' layers
//! between `[base]` and its own, outermost first: their themes, tokens and
//! classes, never their element bindings.
//!
//! A *rule*, one per diagram and set of classes present, folds `[base]`,
//! the diagram's themes and the program's class bindings, the most specific
//! winning within a layer and of one rank the later. Within the program, a
//! class at the top level (every diagram's) ranks below a class inside the
//! diagram, each by the classes' own ranks: `&node` < the kinds <
//! `&canonical` < `&hole`. Once every element is made, rules are shared as a
//! tree of steps (statements.md §25): `[base]` class by class, then each
//! layer the diagram adds, each step a rule holding what it changes; a
//! sequence of steps is made once, whichever diagrams take it. An *element* holds its own bindings, then what is
//! computed where the result is still nil (labels by name, a cell's arrow by
//! level), then its marks. Tokens are resolved per diagram, one step, in
//! rules and elements alike.

const std = @import("std");
const fab = @import("fab_core");
const Ir = fab.Ir;
const Env = fab.Env;
const decoded = fab.decoded;
const layers = fab.layers;
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
    /// Each diagram's kind in effect, and the diagram stating it.
    kinds: []const layers.Kind = &.{},
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
    try b.nameRecords();
    b.base = record(in.env, in.env.values.get("base"));
    try b.sortBindings();

    b.zone_tokens = try gpa.alloc([]const decoded.Token, ir.zones.len);
    @memset(b.zone_tokens, &.{});
    b.zone_themes = try gpa.alloc([]const Themed, ir.zones.len);
    @memset(b.zone_themes, &.{});
    // Themes first, every diagram's: a member's tokens read its containers',
    // which are declared after it.
    for (0..ir.zones.len) |z| try b.prepareThemes(@fromBackingInt(@as(u32, @intCast(z))));
    for (0..ir.zones.len) |z| try b.prepareTokens(@fromBackingInt(@as(u32, @intCast(z))));

    const zones = ir.nodes.items(.zone);
    b.nodes = try gpa.alloc(Sheet.Element, ir.nodes.len);
    for (b.nodes, ir.nodes.items(.kind), ir.nodes.items(.name), ir.nodes.items(.diagram), ir.nodes.items(.canonical), zones, reached, marks.nodes, 0..) |*e, kind, name, diagram, canonical, zone, arrived, mark, i| {
        var classes: Env.Classes = .initMany(&.{ .node, switch (kind) {
            .plain => .plain,
            .choice => .choice,
            .parallel => .parallel,
            .hole => .hole,
            .null_node => if (arrived) .end else .start,
        } });
        // Labelled by its canonical end (spec, Subjects and classes): unnamed
        // (a diagram's node is named by its diagram), and its label, resolved
        // without `&canonical`, left to be computed. A mark's `:label ""` keeps it out; `&choice :label []`
        // brings it in.
        const self: Ir.NodeIndex = @fromBackingInt(@as(u32, @intCast(i)));
        if (name == null and canonical != null and
            try b.labelComputed(.{ .node = self }, try b.ruleFor(zone, classes))) classes.insert(.canonical);
        const computed: Value = if (name) |n|
            .{ .text = withoutSigil(ir.string(n)) }
        else if (diagram) |d|
            // A diagram's node stands for the diagram (statements.md §23.2).
            .{ .text = ir.string(ir.zones.items(.name)[@backingInt(d)]) }
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

    try b.share();
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

/// A theme of a diagram, the layer its entries are in (a kind's theme and
/// what it includes are `kind`, the rest `theme`), and its step's name.
const Themed = struct { record: decoded.Record, index: decoded.RecordIndex, layer: Layer, step: Sheet.Step };

/// One step of a diagram's layers (statements.md §25): a theme, the top
/// level's classes, or a diagram's classes and tokens, at a precedence.
const LayerStep = struct {
    adds: Sheet.Step,
    at: Precedence,
    what: union(enum) { theme: Themed, top, classes: Ir.ZoneIndex },
};

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
    /// Each rule's diagram, until `share`.
    rule_zones: std.ArrayList(Ir.ZoneIndex) = .empty,
    entries: std.ArrayList(Entry) = .empty,
    /// The named records, for their steps: `[dark]` is `dark`.
    record_names: std.AutoHashMapUnmanaged(u32, Named) = .empty,
    step_buffer: std.ArrayList(LayerStep) = .empty,
    made: std.AutoHashMapUnmanaged(Key, Sheet.RuleIndex) = .empty,
    /// The program's bindings by what they describe, each list in source
    /// order: classes at the top level, classes in a diagram, elements.
    top: std.ArrayList(u32) = .empty,
    in_zone: std.AutoHashMapUnmanaged(u32, std.ArrayList(u32)) = .empty,
    own: std.AutoHashMapUnmanaged(SubjectKey, std.ArrayList(u32)) = .empty,
    zone_themes: [][]const Themed = &.{},
    zone_tokens: [][]const decoded.Token = &.{},
    chain_buffer: std.ArrayList(Ir.ZoneIndex) = .empty,
    nodes: []Sheet.Element = &.{},
    edges: []Sheet.Element = &.{},
    cells: []Sheet.Element = &.{},
    zones: []Sheet.Element = &.{},
    /// The cell being made, for its arrow; the zone, for its caption.
    level: u32 = 0,
    zone_mark: ZoneMark = .{},

    const Key = struct { zone: u32, classes: u16 };
    const Named = struct { name: []const u8, token: u32 };
    const SubjectKey = struct { table: u8, index: u32 };

    fn deinit(b: *Builder) void {
        b.by_name.deinit(b.gpa);
        b.made.deinit(b.gpa);
        b.names.deinit(b.gpa);
        b.rules.deinit(b.gpa);
        b.rule_zones.deinit(b.gpa);
        b.entries.deinit(b.gpa);
        b.record_names.deinit(b.gpa);
        b.step_buffer.deinit(b.gpa);
        b.top.deinit(b.gpa);
        var zit = b.in_zone.valueIterator();
        while (zit.next()) |l| l.deinit(b.gpa);
        b.in_zone.deinit(b.gpa);
        var oit = b.own.valueIterator();
        while (oit.next()) |l| l.deinit(b.gpa);
        b.own.deinit(b.gpa);
        b.gpa.free(b.zone_themes);
        b.chain_buffer.deinit(b.gpa);
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

    /// Each named record's name, the first defined when several name it.
    fn nameRecords(b: *Builder) error{OutOfMemory}!void {
        var it = b.in.env.values.iterator();
        while (it.next()) |kv| {
            const d = kv.value_ptr.decoded orelse continue;
            if (d != .record) continue;
            const token: u32 = kv.value_ptr.token orelse 0;
            const gop = try b.record_names.getOrPut(b.gpa, @backingInt(d.record));
            if (!gop.found_existing or token < gop.value_ptr.token) gop.value_ptr.* = .{ .name = kv.key_ptr.*, .token = token };
        }
    }

    /// The program's bindings, by what they describe. A table's entries
    /// (`:lemma.[a]`) and another layer's bindings (`:place`) are no style's.
    fn sortBindings(b: *Builder) error{OutOfMemory}!void {
        for (b.in.bindings, 0..) |binding, i| {
            if (binding.key != null or binding.layer != .style) continue;
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

    /// The diagrams whose layers a diagram's rules fold, lowest first: its
    /// containers, outermost first, then itself (statements.md §23.2). The
    /// list is the Builder's, valid until the next call.
    fn chain(b: *Builder, zone: Ir.ZoneIndex) error{OutOfMemory}![]const Ir.ZoneIndex {
        b.chain_buffer.clearRetainingCapacity();
        var at: ?Ir.ZoneIndex = zone;
        while (at) |z| : (at = b.ir.zones.items(.container)[@backingInt(z)]) try b.chain_buffer.append(b.gpa, z);
        std.mem.reverse(Ir.ZoneIndex, b.chain_buffer.items);
        return b.chain_buffer.items;
    }

    /// A diagram's themes, includes first: the kind's theme where the
    /// diagram states its kind, then its `:theme`.
    fn prepareThemes(b: *Builder, zone: Ir.ZoneIndex) error{OutOfMemory}!void {
        var themes: std.ArrayList(Themed) = .empty;
        defer themes.deinit(b.gpa);
        var records: std.ArrayList(decoded.RecordIndex) = .empty;
        defer records.deinit(b.gpa);
        const kind = b.kindTheme(zone);
        if (kind) |k| try b.expand(.{ .record = k.record }, &records, 8);
        for (records.items) |r| try themes.append(b.gpa, b.themed(r, .kind, kind));
        records.clearRetainingCapacity();
        if (try b.themeValue(zone)) |v| try b.expand(v, &records, 8);
        for (records.items) |r| try themes.append(b.gpa, b.themed(r, .theme, null));
        b.zone_themes[@backingInt(zone)] = try b.arena.dupe(Themed, themes.items);
    }

    /// A theme and its step: the kind's own by the kind, a named one by its
    /// name.
    fn themed(b: *Builder, r: decoded.RecordIndex, layer: Layer, kind: ?KindTheme) Themed {
        const step: Sheet.Step = if (kind != null and kind.?.record == r)
            .{ .kind = kind.?.label }
        else
            .{ .theme = if (b.record_names.get(@backingInt(r))) |n| n.name else "" };
        return .{ .record = b.in.env.records.items[@backingInt(r)], .index = r, .layer = layer, .step = step };
    }

    const KindTheme = struct { record: decoded.RecordIndex, label: []const u8 };

    /// The theme of the kind `zone` states itself, if it has one.
    fn kindTheme(b: *Builder, zone: Ir.ZoneIndex) ?KindTheme {
        for (b.in.kinds) |k| if (k.zone == zone and k.from == zone) {
            const theme = b.in.env.kind_themes.get(k.label) orelse return null;
            return .{ .record = theme.record, .label = k.label };
        };
        return null;
    }

    /// A diagram's tokens: `[base]`'s, then along its chain each diagram's
    /// themes' and its own.
    fn prepareTokens(b: *Builder, zone: Ir.ZoneIndex) error{OutOfMemory}!void {
        var tokens: std.ArrayList(decoded.Token) = .empty;
        defer tokens.deinit(b.gpa);
        if (b.base) |base| for (base.tokens) |t| try bindToken(b.gpa, &tokens, t);
        for (try b.chain(zone)) |d| {
            for (b.zone_themes[@backingInt(d)]) |theme| for (theme.record.tokens) |t| try bindToken(b.gpa, &tokens, t);
            for (b.in.tokens) |t| if (t.zone == d) try bindToken(b.gpa, &tokens, t.token);
        }
        b.zone_tokens[@backingInt(zone)] = try b.arena.dupe(decoded.Token, tokens.items);
    }

    /// The diagram's `:theme`, read as any descriptor is, below its themes:
    /// `[base]`, a class in each of its containers (outermost first), a class
    /// at the top level, a class in the diagram, the diagram itself.
    fn themeValue(b: *Builder, zone: Ir.ZoneIndex) error{OutOfMemory}!?Value {
        var found: ?Value = null;
        if (b.base) |base| for (base.bindings) |binding| {
            if (binding.classes) |c| if (c.contains(.zone) and std.mem.eql(u8, binding.descriptor, ":theme")) {
                found = binding.value;
            };
        };
        const holders = try b.chain(zone);
        for (holders[0 .. holders.len - 1]) |d| if (b.in_zone.get(@backingInt(d))) |l| {
            if (b.zoneTheme(l.items)) |v| found = v;
        };
        const lists = [_][]const u32{
            b.top.items,
            if (b.in_zone.get(@backingInt(zone))) |l| l.items else &.{},
        };
        for (lists) |list| if (b.zoneTheme(list)) |v| {
            found = v;
        };
        if (b.own.get(subjectKey(.{ .zone = zone }))) |l| for (l.items) |i| {
            const binding = b.in.bindings[i];
            if (std.mem.eql(u8, binding.descriptor, ":theme")) found = binding.value;
        };
        return found;
    }

    /// The last `&zone :theme` among class bindings.
    fn zoneTheme(b: *Builder, list: []const u32) ?Value {
        var found: ?Value = null;
        for (list) |i| {
            const binding = b.in.bindings[i];
            if (binding.subject.class.classes.contains(.zone) and std.mem.eql(u8, binding.descriptor, ":theme")) found = binding.value;
        }
        return found;
    }

    /// `[dark/print]`: each record, after the themes its own `:theme`
    /// includes.
    fn expand(b: *Builder, v: Value, out: *std.ArrayList(decoded.RecordIndex), depth: u32) error{OutOfMemory}!void {
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
                try out.append(b.gpa, r);
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
        var tokens: std.ArrayList(decoded.Token) = .empty;
        defer tokens.deinit(b.gpa);
        // [base] is layer 0, then the diagram's steps.
        if (b.base) |base| try b.foldRecord(slots, base, classes, 0, .base);
        for (try b.layerSteps(zone)) |s| try b.apply(slots, &tokens, s, classes);

        const start: u32 = @intCast(b.entries.items.len);
        try b.emit(slots, b.zone_tokens[@backingInt(zone)], &b.entries);
        try b.rule_zones.append(b.gpa, zone);
        try b.rules.append(b.gpa, .{
            .adds = .{ .zone = zone },
            .classes = classes,
            .entries = .{ .start = start, .end = @intCast(b.entries.items.len) },
        });
        return index;
    }

    /// A diagram's steps above `[base]`, lowest first: each diagram of its
    /// chain, containers outermost first, its themes (each one layer more),
    /// then its classes in the program; the top level's classes, every
    /// diagram's own, just below the diagram's. The list is the Builder's,
    /// valid until the next call.
    fn layerSteps(b: *Builder, zone: Ir.ZoneIndex) error{OutOfMemory}![]const LayerStep {
        b.step_buffer.clearRetainingCapacity();
        var layer: Precedence = 1;
        for (try b.chain(zone)) |d| {
            for (b.zone_themes[@backingInt(d)]) |theme| {
                try b.step_buffer.append(b.gpa, .{ .adds = theme.step, .at = layer, .what = .{ .theme = theme } });
                layer += 1;
            }
            if (d == zone) try b.step_buffer.append(b.gpa, .{ .adds = .{ .zone = null }, .at = layer, .what = .top });
            try b.step_buffer.append(b.gpa, .{ .adds = .{ .zone = d }, .at = layer, .what = .{ .classes = d } });
            layer += 1;
        }
        return b.step_buffer.items;
    }

    /// Folds step `s` for `classes` into `slots`, and binds its tokens.
    fn apply(b: *Builder, slots: []Slot, tokens: *std.ArrayList(decoded.Token), s: LayerStep, classes: Env.Classes) error{OutOfMemory}!void {
        switch (s.what) {
            .theme => |t| {
                try b.foldRecord(slots, t.record, classes, s.at, t.layer);
                for (t.record.tokens) |token| try bindToken(b.gpa, tokens, token);
            },
            .top => for (b.top.items) |i| try b.foldProgram(slots, i, classes, s.at, 0),
            .classes => |d| {
                if (b.in_zone.get(@backingInt(d))) |list| for (list.items) |i| try b.foldProgram(slots, i, classes, s.at, 4);
                for (b.in.tokens) |t| if (t.zone == d) try bindToken(b.gpa, tokens, t.token);
            },
        }
    }

    /// Whether step `s` binds nothing for `classes` and no token: it is left
    /// out of the sequence, so diagrams differing only by it share.
    fn idle(b: *Builder, s: LayerStep, classes: Env.Classes) bool {
        switch (s.what) {
            .theme => |t| {
                if (t.record.tokens.len > 0) return false;
                for (t.record.bindings) |binding| {
                    if (binding.key != null) continue;
                    const c = binding.classes orelse continue;
                    if (c.intersectWith(classes).count() > 0) return false;
                }
                return true;
            },
            .top => return !b.meets(b.top.items, classes),
            .classes => |d| {
                for (b.in.tokens) |t| if (t.zone == d) return false;
                return !b.meets(if (b.in_zone.get(@backingInt(d))) |l| l.items else &.{}, classes);
            },
        }
    }

    /// Whether a class binding of `list` describes some of `classes`.
    fn meets(b: *Builder, list: []const u32, classes: Env.Classes) bool {
        for (list) |i| if (b.in.bindings[i].subject.class.classes.intersectWith(classes).count() > 0) return true;
        return false;
    }

    fn foldRecord(b: *Builder, slots: []Slot, r: decoded.Record, classes: Env.Classes, layer: Precedence, as: Layer) error{OutOfMemory}!void {
        for (r.bindings) |binding| {
            if (binding.key != null) continue;
            const meet = (binding.classes orelse continue).intersectWith(classes);
            if (meet.count() == 0) continue;
            try b.bind(slots, binding.descriptor, binding.value, layer * 16 + rank(meet), as, 8);
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

    /// The bound slots as entries of `out`, in descriptor order, `tokens`
    /// resolved. `:theme` is the cascade's, no element's style.
    fn emit(b: *Builder, slots: []const Slot, tokens: []const decoded.Token, out: *std.ArrayList(Entry)) error{OutOfMemory}!void {
        for (slots, 0..) |slot, i| if (slot) |s| {
            if (std.mem.eql(u8, b.names.items[i], ":theme")) continue;
            try out.append(b.gpa, .{
                .descriptor = @fromBackingInt(@as(u16, @intCast(i))),
                .value = try b.resolve(s.value, tokens),
                .layer = s.layer,
            });
        };
    }

    /// Shares the rules as a tree of steps (statements.md §25). Each rule
    /// an element names is folded again, step by step: `[base]` class by
    /// class, by rank, a rule each; then the diagram's layer steps for the
    /// whole set, a rule each that changes something, by value or by layer.
    /// A sequence of steps is made once (`Trie`), whichever diagram takes
    /// it; an idle step is no part of it. The element then names the last
    /// rule made. The rules no element names (the `&canonical` check makes
    /// some on the way) are dropped, and the entries only they held.
    fn share(b: *Builder) error{OutOfMemory}!void {
        const tables = [_][]Sheet.Element{ b.nodes, b.edges, b.cells, b.zones };
        const renumber = try b.gpa.alloc(?Sheet.RuleIndex, b.rules.items.len);
        defer b.gpa.free(renumber);
        @memset(renumber, null);
        const used = try b.gpa.alloc(bool, b.rules.items.len);
        defer b.gpa.free(used);
        @memset(used, false);
        for (tables) |table| for (table) |e| {
            used[@backingInt(e.rule)] = true;
        };
        var t: Tree = .{ .b = b, .slots = try b.gpa.alloc(Slot, b.names.items.len) };
        defer t.deinit();
        errdefer t.entries.deinit(b.gpa);
        errdefer t.rules.deinit(b.gpa);
        const base_tokens: []const decoded.Token = if (b.base) |base| base.tokens else &.{};

        for (b.rules.items, b.rule_zones.items, used, renumber) |r, zone, is_used, *new| if (is_used) {
            t.start();
            // [base], one class at a time: these rules are always made.
            var order: [16]Env.Class = undefined;
            var set: Env.Classes = .empty;
            for (byRank(r.classes, &order)) |class| {
                set.insert(class);
                @memset(t.slots, null);
                if (b.base) |base| try b.foldRecord(t.slots, base, set, 0, .base);
                try t.step(.{ .tag = .class, .a = @backingInt(class) }, .{ .class = class }, set, base_tokens, true);
            }
            // Then the diagram's layers, onto [base]'s fold of the set.
            t.tokens.clearRetainingCapacity();
            try t.tokens.appendSlice(b.gpa, base_tokens);
            for (try b.layerSteps(zone)) |s| {
                if (b.idle(s, r.classes)) continue;
                try b.apply(t.slots, &t.tokens, s, r.classes);
                try t.step(stepKey(s), s.adds, r.classes, t.tokens.items, false);
            }
            if (std.debug.runtime_safety) {
                const full = b.entries.items[r.entries.start..r.entries.end];
                std.debug.assert(full.len == t.prev.items.len);
                for (full) |e| std.debug.assert(inheritedFrom(t.prev.items, e));
            }
            new.* = t.at.?;
        };
        for (tables) |table| for (table) |*e| {
            e.rule = renumber[@backingInt(e.rule)].?;
            const start: u32 = @intCast(t.entries.items.len);
            try t.entries.appendSlice(b.gpa, b.entries.items[e.own.start..e.own.end]);
            e.own = .{ .start = start, .end = @intCast(t.entries.items.len) };
        };
        b.entries.deinit(b.gpa);
        b.entries = t.entries;
        b.rules.deinit(b.gpa);
        b.rules = t.rules;
    }

    /// A step, as the trie keys it: what it adds, not where.
    fn stepKey(s: LayerStep) StepKey {
        return switch (s.what) {
            .theme => |theme| .{ .tag = .theme, .a = @backingInt(theme.index), .b = @backingInt(theme.layer) },
            .top => .{ .tag = .top },
            .classes => |d| .{ .tag = .zone, .a = @backingInt(d) },
        };
    }

    /// A label one of `tokens` binds, replaced by its value, once: in a
    /// tuple too.
    fn resolve(b: *Builder, v: Value, tokens: []const decoded.Token) error{OutOfMemory}!Value {
        switch (v) {
            .label => |l| {
                if (l.inverted) return v;
                for (tokens) |t| if (std.mem.eql(u8, t.label, l.name)) return t.value;
                return v;
            },
            .elements => |es| {
                const out = try b.arena.alloc(Value, es.len);
                for (es, out) |e, *o| o.* = try b.resolve(e, tokens);
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
        try b.emit(slots, b.zone_tokens[@backingInt(zone)], &b.entries);
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

const StepKey = struct { tag: enum(u8) { class, theme, top, zone }, a: u32 = 0, b: u32 = 0 };

/// The rules `share` makes, and the sequences of steps it has walked: a
/// trie, each node the sequence of its parent and one step more, holding
/// the last rule made along it.
const Tree = struct {
    b: *Builder,
    slots: []Slot,
    entries: std.ArrayList(Entry) = .empty,
    rules: std.ArrayList(Sheet.Rule) = .empty,
    trie: std.AutoHashMapUnmanaged(TrieKey, TrieNode) = .empty,
    tokens: std.ArrayList(decoded.Token) = .empty,
    /// The style so far, resolved, and the step's.
    prev: std.ArrayList(Entry) = .empty,
    cur: std.ArrayList(Entry) = .empty,
    /// Where the walk is: its trie node, and the last rule made on it.
    node: u32 = root,
    at: ?Sheet.RuleIndex = null,

    const root = std.math.maxInt(u32);
    const TrieKey = struct { parent: u32, step: StepKey };
    const TrieNode = struct { id: u32, rule: ?Sheet.RuleIndex };

    fn deinit(t: *Tree) void {
        t.b.gpa.free(t.slots);
        t.trie.deinit(t.b.gpa);
        t.tokens.deinit(t.b.gpa);
        t.prev.deinit(t.b.gpa);
        t.cur.deinit(t.b.gpa);
    }

    fn start(t: *Tree) void {
        t.node = root;
        t.at = null;
        t.prev.clearRetainingCapacity();
    }

    /// One step more: the slots, as they now are, resolved by `tokens`. Made
    /// the first time the sequence is walked, as a rule holding what differs
    /// from the style before it, when something does or `always`.
    fn step(t: *Tree, key: StepKey, adds: Sheet.Step, classes: Env.Classes, tokens: []const decoded.Token, always: bool) error{OutOfMemory}!void {
        const gpa = t.b.gpa;
        t.cur.clearRetainingCapacity();
        try t.b.emit(t.slots, tokens, &t.cur);
        const gop = try t.trie.getOrPut(gpa, .{ .parent = t.node, .step = key });
        if (!gop.found_existing) {
            gop.value_ptr.* = .{ .id = t.trie.count() - 1, .rule = t.at };
            const start_at: u32 = @intCast(t.entries.items.len);
            for (t.cur.items) |e| if (!inheritedFrom(t.prev.items, e)) try t.entries.append(gpa, e);
            if (always or t.entries.items.len > start_at) {
                gop.value_ptr.rule = @fromBackingInt(@as(u32, @intCast(t.rules.items.len)));
                try t.rules.append(gpa, .{ .adds = adds, .classes = classes, .parent = t.at, .entries = .{ .start = start_at, .end = @intCast(t.entries.items.len) } });
            }
        }
        t.node = gop.value_ptr.id;
        t.at = gop.value_ptr.rule;
        std.mem.swap(std.ArrayList(Entry), &t.prev, &t.cur);
    }
};

/// `classes` in the order `[base]` adds them, by rank: `&node`, its kind,
/// `&canonical`, `&hole`.
fn byRank(classes: Env.Classes, out: []Env.Class) []const Env.Class {
    var n: usize = 0;
    for (0..4) |r| {
        var it = classes.iterator();
        while (it.next()) |c| if (rank(.initOne(c)) == r) {
            out[n] = c;
            n += 1;
        };
    }
    return out[0..n];
}

/// A token bound again replaces the binding before it.
fn bindToken(gpa: std.mem.Allocator, tokens: *std.ArrayList(decoded.Token), t: decoded.Token) error{OutOfMemory}!void {
    for (tokens.items) |*old| if (std.mem.eql(u8, old.label, t.label)) {
        old.value = t.value;
        return;
    };
    try tokens.append(gpa, t);
}

/// Whether `parent`, sorted by descriptor, holds `e` as it is: the same
/// value from the same layer.
fn inheritedFrom(parent: []const Entry, e: Entry) bool {
    for (parent) |p| if (p.descriptor == e.descriptor) return p.layer == e.layer and same(p.value, e.value);
    return false;
}

/// Whether two values are the same value.
fn same(a: Value, b: Value) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .nil => true,
        .flag => |x| x == b.flag,
        .text => |x| std.mem.eql(u8, x, b.text),
        .math => |x| std.mem.eql(u8, x, b.math),
        .color => |x| std.meta.eql(x, b.color),
        .number => |x| std.meta.eql(x, b.number),
        .range => |x| std.meta.eql(x, b.range),
        .label => |x| x.inverted == b.label.inverted and std.mem.eql(u8, x.name, b.label.name),
        .elements => |xs| xs.len == b.elements.len and for (xs, b.elements) |x, y| {
            if (!same(x, y)) break false;
        } else true,
        .record => |x| x == b.record,
    };
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
