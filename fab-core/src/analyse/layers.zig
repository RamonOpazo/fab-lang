//! Layers read (statements.md §22.10, plan step 9c): descriptions resolved to
//! the elements they describe, and kept as bindings for the style pass.
//!
//!   G :style { :caption "G", #Done :terminal, (f, g) :label "x" }
//!   G.f+ :ink [red]                          joins G's style
//!   &node :fill [white]                      every diagram's nodes
//!
//! A context is a subject: a diagram, a part of one (`f`, `f+`, `+f`, `#X`,
//! `@`), a class (`&edge`, `G.&edge`), or a group of them, over which the
//! descriptor distributes. Inside a block it is relative to the owner, and
//! only a diagram has parts. A layer is open: every description of it joins
//! one. Only `:style` is read; `:prove` and `:place` are unsupported, at
//! their descriptor, until plan step 11.
//!
//! Nodes are union-find elements until the graph is built (`finish`), since
//! a later diagram can still merge them.

const std = @import("std");
const Cst = @import("../parse/Cst.zig");
const Analyser = @import("Analyser.zig");
const Env = @import("Env.zig");
const Ir = @import("Ir.zig");
const records = @import("records.zig");
const vocabulary = @import("vocabulary.zig");
const elaborate = @import("elaborate.zig");
const decode = @import("decode.zig");
const decoded = @import("decoded.zig");

const Node = Cst.Node;
const TokenIndex = Cst.TokenIndex;

pub const Layer = enum { style };

/// What a description is about.
pub const Subject = union(enum) {
    zone: Ir.ZoneIndex,
    edge: Ir.EdgeIndex,
    cell: Ir.CellIndex,
    node: Ir.NodeIndex,
    class: Class,

    /// `&edge`, every diagram's; `G.&edge`, G's.
    pub const Class = struct { classes: Env.Classes, zone: ?Ir.ZoneIndex };
};

/// `G.f :label "x"`: a subject, the attribute that describes it (its name,
/// key and value, read in the style pass), and its layer.
pub const Binding = struct {
    subject: Subject,
    attr: Node.Index,
    layer: Layer,
    /// The attribute's name, `:` included, and its key without brackets:
    /// what the style pass reads, with no CST.
    descriptor: []const u8,
    key: ?[]const u8 = null,
    value: decoded.Value,
};

/// `G :style { [ink] := [#000000] }`: a token a diagram's own layer binds,
/// after its themes (statements.md §22.11).
pub const Token = struct { zone: Ir.ZoneIndex, token: decoded.Token };

/// A token naming a subject, for the language server.
/// A subject before the graph is built: a node is still an element, with
/// the end that reached it, if one did.
pub const Pending = union(enum) {
    subject: Subject,
    /// Reached in `zone`'s context, at `token`; through `end`, if one.
    node: struct { elem: u32, end: ?Ir.End, token: TokenIndex, zone: Ir.ZoneIndex },
};

pub const PendingBinding = struct { subject: Pending, attr: Node.Index, layer: Layer, descriptor: []const u8, key: ?[]const u8, value: decoded.Value };
pub const PendingReference = struct { token: TokenIndex, subject: Pending };

/// Where a block's contexts are read: in a diagram, which has parts, or in
/// an element or a class, which has none.
const Owner = struct { subject: Pending, zone: ?Analyser.Zone };

/// `G :style { … }`, `G.f :label "x"`, `&node :fill [red]`: a description
/// at the top level, its shape checked already.
pub fn description(a: *Analyser, entry: Node.Index) error{OutOfMemory}!void {
    try entryIn(a, entry, null, null);
}

/// An entry, with its owners (null at the top level) and the layer it is in
/// (null until a layer descriptor or a descriptor of a record type says).
fn entryIn(a: *Analyser, entry: Node.Index, owners: ?[]const Owner, layer: ?Layer) error{OutOfMemory}!void {
    const cst = a.cst;
    var subjects: std.ArrayList(Owner) = .empty;
    defer subjects.deinit(a.gpa);
    const context = cst.subject(entry);
    if (context) |c| {
        if (owners) |os| {
            try within(a, c, os, &subjects);
        } else try top(a, c, &subjects);
    } else if (owners) |os| {
        try subjects.appendSlice(a.gpa, os);
    } else return; // *context missing*, said with its shape
    // An absent context is left out of the children.
    for (cst.children(entry)[@intFromBool(context != null)..]) |item| switch (cst.tag(item)) {
        .attr => try descriptor(a, item, subjects.items, layer),
        .block => try block(a, item, subjects.items, layer),
        else => {},
    };
}

/// The items of a block, read once for all its owners.
fn block(a: *Analyser, node: Node.Index, owners: []const Owner, layer: ?Layer) error{OutOfMemory}!void {
    const cst = a.cst;
    var one: [1]Node.Index = undefined;
    for (vocabulary.itemsOf(cst, node, &one)) |item| switch (cst.tag(item)) {
        .entry => try entryIn(a, item, owners, layer),
        // Braces and groups with no context only organise.
        .block => try block(a, item, owners, layer),
        .group => try block(a, cst.children(item)[0], owners, layer),
        .items => try block(a, item, owners, layer),
        // Tokens, `[ink] := [#fff]`: a diagram's own, after its themes.
        // Their shape was checked; other shapes were reported with it.
        .statement => if (layer == .style and cst.tokenTag(cst.mainToken(item)) == .defn) {
            if (try decode.token(a, item)) |t| for (owners) |o| switch (o.subject) {
                .subject => |s| switch (s) {
                    .zone => |z| try a.tokens.append(a.gpa, .{ .zone = z, .token = t }),
                    else => {},
                },
                .node => {},
            };
        },
        else => {},
    };
}

/// One descriptor, for all the subjects of its entry. A layer descriptor,
/// `:style`, opens its layer; any other is a binding of the style, checked
/// once against the classes of all its subjects.
fn descriptor(a: *Analyser, attr: Node.Index, subjects: []const Owner, layer: ?Layer) error{OutOfMemory}!void {
    const cst = a.cst;
    const name_token = cst.mainToken(attr);
    const name = cst.tokenText(name_token);
    const f = a.env.functions.get(name) orelse {
        // Declared with the proof and place shells (plan step 11): checked
        // for shape, not read.
        if (std.mem.eql(u8, name, ":prove") or std.mem.eql(u8, name, ":place")) {
            try a.fail(.unsupported_layer, name_token);
            return;
        }
        try a.fail(.unknown_attribute, name_token);
        return;
    };
    try a.referToken(name_token, .descriptor, .{ .token = f.token, .prelude = f.prelude });
    const style = if (a.env.type_table.get(":Style")) |named| named.index else null;
    const classes = classesOf(subjects);

    // `G :style { … }`: the layer, opened on the diagrams it describes.
    const value = cst.data(attr).node;
    if (layer == null and f.record == null and a.env.isRecord(f.type) and cst.tag(value) == .block) {
        if (!Env.within(classes).subsetOf(f.classes))
            try a.errors.append(a.gpa, .{ .tag = .does_not_apply, .token = name_token, .related = if (f.prelude) null else f.token });
        try block(a, value, subjects, .style);
        return;
    }

    try records.function(a, attr, .{ .record = style, .at = .{ .subject = classes } });
    const bound = try decode.attr(a, attr, f);
    const key: ?[]const u8 = if (cst.key(attr)) |k| blk: {
        const text = cst.tokenText(k);
        break :blk text[1 .. text.len - 1];
    } else null;
    for (subjects) |s| try a.bindings.append(a.gpa, .{ .subject = s.subject, .attr = attr, .layer = .style, .descriptor = name, .key = key, .value = bound });
}

/// The classes of what a descriptor is written at: an element's own, or a
/// class. A node's are its kind, known once the graph is built, so nodes
/// are judged then (`check`).
fn classesOf(subjects: []const Owner) Env.Classes {
    var classes: Env.Classes = .empty;
    for (subjects) |s| switch (s.subject) {
        .node => {},
        .subject => |subject| switch (subject) {
            .zone => classes.insert(.zone),
            .edge => classes.insert(.edge),
            .cell => classes.insert(.cell),
            .node => classes.insert(.node),
            .class => |c| classes.setUnion(c.classes),
        },
    };
    return classes;
}

// ---------------------------------------------------------------------------
// Contexts

/// A context at the top level: a diagram (`G`), a part of one (`G.f`), a
/// class (`&node`, `G.&node`), or a group of them.
fn top(a: *Analyser, node: Node.Index, out: *std.ArrayList(Owner)) error{OutOfMemory}!void {
    const cst = a.cst;
    const main = cst.mainToken(node);
    switch (cst.tag(node)) {
        .group => try each(a, node, null, out),
        .leaf => switch (cst.tokenTag(main)) {
            .zone_id => if (try diagram(a, main)) |zone| {
                try add(a, out, .{ .subject = .{ .subject = .{ .zone = zone.index } }, .zone = zone }, main);
            },
            .class_id => try class(a, main, null, out),
            else => try notASubject(a, node),
        },
        .juxtafix => {
            const left, const right = cst.data(node).nodes;
            if (cst.tag(left) != .leaf or cst.tokenTag(cst.mainToken(left)) != .zone_id) return notASubject(a, node);
            const zone = try diagram(a, cst.mainToken(left)) orelse return;
            try reference(a, cst.mainToken(left), .{ .subject = .{ .zone = zone.index } });
            try part(a, zone, right, out);
        },
        else => try notASubject(a, node),
    }
}

/// A context inside a block: a part of each owner, which must be a diagram.
fn within(a: *Analyser, node: Node.Index, owners: []const Owner, out: *std.ArrayList(Owner)) error{OutOfMemory}!void {
    for (owners) |owner| if (owner.zone == null) {
        try a.fail(.element_has_no_parts, a.cst.firstToken(node));
        return;
    };
    for (owners) |owner| try part(a, owner.zone.?, node, out);
}

/// A part of `zone`: an edge or a cell, an end, a named node, `@`, a class
/// in it, or a group of them. `zone.x` is `x`; another diagram's parts are
/// its own to describe.
fn part(a: *Analyser, zone: Analyser.Zone, node: Node.Index, out: *std.ArrayList(Owner)) error{OutOfMemory}!void {
    const cst = a.cst;
    const main = cst.mainToken(node);
    // What refers into a broken diagram is quiet.
    if (zone.broken) return;
    switch (cst.tag(node)) {
        .group => try each(a, node, zone, out),
        .leaf => switch (cst.tokenTag(main)) {
            .edge_id => {
                const name = zone.table.get(cst.tokenText(main)) orelse return a.fail(.undeclared_name_in_diagram, main);
                const subject: Subject = switch (name.is) {
                    .generator => |g| if (name.level == 1) .{ .edge = @fromBackingInt(g.index) } else .{ .cell = @fromBackingInt(g.index) },
                    .hole => return,
                    .node => unreachable, // nodes are named with `#`
                };
                try a.referTokenTo(main, if (name.level == 1) .edge else .cell, .{ .token = name.is.generator.token }, elaborate.names(name));
                try add(a, out, .{ .subject = .{ .subject = subject }, .zone = null }, main);
            },
            .node_id, .at => {
                const key = if (cst.tokenTag(main) == .at) "@" else cst.tokenText(main);
                const name = zone.table.get(key) orelse
                    return a.fail(if (cst.tokenTag(main) == .at) .diagram_without_own_node else .undeclared_name_in_diagram, main);
                const elem = switch (name.is) {
                    .node => |e| e,
                    .hole => return,
                    .generator => unreachable,
                };
                try a.referTokenTo(main, .node, .{ .token = name.token }, .{ .elem = elem });
                try add(a, out, .{ .subject = .{ .node = .{ .elem = elem, .end = null, .token = main, .zone = zone.index } }, .zone = null }, main);
            },
            .class_id => try class(a, main, zone.index, out),
            .zone_id => if (std.mem.eql(u8, cst.tokenText(main), a.cst.tokenText(zone.token))) {
                try a.referTokenTo(main, .zone, .{ .token = zone.token }, .{ .subject = .{ .zone = zone.index } });
                try add(a, out, .{ .subject = .{ .subject = .{ .zone = zone.index } }, .zone = zone }, main);
            } else try a.fail(.another_diagrams_subject, main),
            else => try notASubject(a, node),
        },
        // `+f`, `f+`: the node at an end of an edge.
        .prefix, .postfix => {
            const operand = cst.data(node).node;
            if (cst.tokenTag(main) != .plus or cst.tag(operand) != .leaf or cst.tokenTag(cst.mainToken(operand)) != .edge_id)
                return notASubject(a, node);
            const edge_token = cst.mainToken(operand);
            const name = zone.table.get(cst.tokenText(edge_token)) orelse return a.fail(.undeclared_name_in_diagram, edge_token);
            if (name.level != 1) return a.fail(.undeclared_name_in_diagram, edge_token);
            const g = switch (name.is) {
                .generator => |g| g,
                .hole => return,
                .node => unreachable,
            };
            try a.referTokenTo(edge_token, .edge, .{ .token = g.token }, .{ .subject = .{ .edge = @fromBackingInt(g.index) } });
            const side: Ir.End.Side = if (cst.tag(node) == .prefix) .dom else .cod;
            const elem = if (side == .dom) g.left else g.right;
            const end: Ir.End = .{ .edge = @fromBackingInt(g.index), .side = side };
            try add(a, out, .{ .subject = .{ .node = .{ .elem = elem, .end = end, .token = edge_token, .zone = zone.index } }, .zone = null }, edge_token);
        },
        // `G.f` inside G's block is `f`; `A.f` is A's to describe.
        .juxtafix => {
            const left, const right = cst.data(node).nodes;
            if (cst.tag(left) != .leaf or cst.tokenTag(cst.mainToken(left)) != .zone_id) return notASubject(a, node);
            const left_token = cst.mainToken(left);
            if (!std.mem.eql(u8, cst.tokenText(left_token), cst.tokenText(zone.token)))
                return a.fail(.another_diagrams_subject, left_token);
            try a.referTokenTo(left_token, .zone, .{ .token = zone.token }, .{ .subject = .{ .zone = zone.index } });
            try part(a, zone, right, out);
        },
        else => try notASubject(a, node),
    }
}

/// The items of a group of contexts, at the top level (`zone` null) or in a
/// diagram.
fn each(a: *Analyser, group: Node.Index, zone: ?Analyser.Zone, out: *std.ArrayList(Owner)) error{OutOfMemory}!void {
    var one: [1]Node.Index = undefined;
    for (vocabulary.itemsOf(a.cst, a.cst.children(group)[0], &one)) |item| {
        if (zone) |z| try part(a, z, item, out) else try top(a, item, out);
    }
}

/// A diagram declared before, by its name. A broken one is quiet.
fn diagram(a: *Analyser, token: TokenIndex) error{OutOfMemory}!?Analyser.Zone {
    const zone = a.zones.get(a.cst.tokenText(token)) orelse {
        try a.fail(.description_at_undeclared_context, token);
        return null;
    };
    try a.referTokenTo(token, .zone, .{ .token = zone.token }, .{ .subject = .{ .zone = zone.index } });
    return if (zone.broken) null else zone;
}

fn class(a: *Analyser, token: TokenIndex, zone: ?Ir.ZoneIndex, out: *std.ArrayList(Owner)) error{OutOfMemory}!void {
    const c = Env.class(a.cst.tokenText(token)) orelse return a.fail(.unknown_class, token);
    const subject: Subject = .{ .class = .{ .classes = .initOne(c), .zone = zone } };
    try add(a, out, .{ .subject = .{ .subject = subject }, .zone = null }, token);
}

fn add(a: *Analyser, out: *std.ArrayList(Owner), owner: Owner, token: TokenIndex) error{OutOfMemory}!void {
    try out.append(a.gpa, owner);
    try a.contexts.append(a.gpa, .{ .token = token, .subject = owner.subject });
}

fn reference(a: *Analyser, token: TokenIndex, subject: Pending) error{OutOfMemory}!void {
    try a.contexts.append(a.gpa, .{ .token = token, .subject = subject });
}

/// A chain, a path or a pinch addresses a structure, not one element.
fn notASubject(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    try a.fail(.not_a_subject, a.cst.firstToken(node));
}

// ---------------------------------------------------------------------------
// After the graph

/// What can be judged only once the graph is built, before errors become
/// issues, so each marks its element:
///
///   canonical references (plan step 9c2): a node reached through an end is
///   reached through its canonical one, a named node only by its name, and
///   a node another diagram made is that diagram's to describe;
///   per element (9c3): a node's descriptors apply to its kind, and each
///   (element, descriptor, key) is bound once in a layer.
pub fn check(a: *Analyser, node_of: []const Ir.NodeIndex) error{OutOfMemory}!void {
    const zones = a.builder.nodes.items(.zone);
    const ends = a.builder.nodes.items(.canonical);
    for (a.contexts.items) |r| switch (r.subject) {
        .node => |n| {
            const node = node_of[a.uf.find(n.elem)];
            if (zones[@backingInt(node)] != n.zone) {
                try a.failOn(.another_diagrams_subject, n.token, .{ .elem = n.elem });
                continue;
            }
            const end = n.end orelse continue;
            const tag: Analyser.Error.Tag = if (ends[@backingInt(node)]) |c| blk: {
                if (c.edge == end.edge and c.side == end.side) continue;
                break :blk .non_canonical_reference;
            } else .named_node_referenced_by_end;
            try a.failOn(tag, n.token, .{ .elem = n.elem });
        },
        .subject => {},
    };
    try kinds(a, node_of);
    try twice(a, node_of);
}

/// A node binding applies to the node's kind: `&choice :knob` not at a
/// plain node. One error per attribute.
fn kinds(a: *Analyser, node_of: []const Ir.NodeIndex) error{OutOfMemory}!void {
    const arrives = try a.arena.allocator().alloc(bool, a.builder.nodes.len);
    @memset(arrives, false);
    for (a.builder.edges.items(.target)) |t| arrives[@backingInt(t)] = true;
    var reported: ?Node.Index = null;
    for (a.bindings.items) |b| {
        const n = switch (b.subject) {
            .node => |n| n,
            .subject => continue,
        };
        if (reported == b.attr) continue;
        const f = a.env.functions.get(a.cst.tokenText(a.cst.mainToken(b.attr))) orelse continue;
        const node = @backingInt(node_of[a.uf.find(n.elem)]);
        const kind: Env.Class = switch (a.builder.nodes.items(.kind)[node]) {
            .plain => .plain,
            .choice => .choice,
            .parallel => .parallel,
            .hole => .hole,
            // A start is a null node no edge arrives at; an end, one some
            // edge arrives at.
            .null_node => if (arrives[node]) .end else .start,
        };
        if (f.classes.contains(kind)) continue;
        reported = b.attr;
        try a.errors.append(a.gpa, .{
            .tag = .does_not_apply,
            .token = a.cst.mainToken(b.attr),
            .related = if (f.prelude) null else f.token,
            .subject = .{ .elem = n.elem },
        });
    }
}

/// Each (element, descriptor, key) is bound once in a layer, and two
/// contexts naming one element are one binding. A table entry with no key
/// has a fresh one, so it never collides.
fn twice(a: *Analyser, node_of: []const Ir.NodeIndex) error{OutOfMemory}!void {
    const cst = a.cst;
    var seen: std.HashMapUnmanaged(Key, Node.Index, KeyContext, std.hash_map.default_max_load_percentage) = .empty;
    defer seen.deinit(a.gpa);
    for (a.bindings.items) |b| {
        const name = cst.tokenText(cst.mainToken(b.attr));
        const key_token = cst.key(b.attr);
        if (key_token == null) if (a.env.functions.get(name)) |f| if (f.table) continue;
        const key: Key = .{
            .layer = b.layer,
            .subject = resolve(a, b.subject, node_of),
            .name = name,
            .key = if (key_token) |t| cst.tokenText(t) else null,
        };
        const gop = try seen.getOrPut(a.gpa, key);
        if (!gop.found_existing) {
            gop.value_ptr.* = b.attr;
            continue;
        }
        try a.errors.append(a.gpa, .{
            .tag = .binding_made_twice,
            .token = cst.mainToken(b.attr),
            .related = cst.mainToken(gop.value_ptr.*),
            .subject = errorSubject(b.subject),
        });
    }
}

const Key = struct { layer: Layer, subject: Subject, name: []const u8, key: ?[]const u8 };

const KeyContext = struct {
    pub fn hash(_: KeyContext, k: Key) u64 {
        var h: std.hash.Wyhash = .init(0);
        h.update(std.mem.asBytes(&k.layer));
        h.update(@tagName(k.subject));
        switch (k.subject) {
            .zone => |z| h.update(std.mem.asBytes(&z)),
            .edge => |e| h.update(std.mem.asBytes(&e)),
            .cell => |c| h.update(std.mem.asBytes(&c)),
            .node => |n| h.update(std.mem.asBytes(&n)),
            .class => |c| {
                h.update(std.mem.asBytes(&c.classes.bits.mask));
                h.update(std.mem.asBytes(&c.zone));
            },
        }
        h.update(k.name);
        if (k.key) |key| h.update(key);
        return h.final();
    }

    pub fn eql(_: KeyContext, x: Key, y: Key) bool {
        if (x.layer != y.layer or !std.mem.eql(u8, x.name, y.name)) return false;
        if ((x.key == null) != (y.key == null)) return false;
        if (x.key) |k| if (!std.mem.eql(u8, k, y.key.?)) return false;
        if (std.meta.activeTag(x.subject) != std.meta.activeTag(y.subject)) return false;
        return switch (x.subject) {
            .zone => |z| z == y.subject.zone,
            .edge => |e| e == y.subject.edge,
            .cell => |c| c == y.subject.cell,
            .node => |n| n == y.subject.node,
            .class => |c| c.classes.eql(y.subject.class.classes) and c.zone == y.subject.class.zone,
        };
    }
};

/// What an error about a binding marks: its element, or the diagram of a
/// class in one. A class everywhere marks its statement's diagram.
fn errorSubject(p: Pending) ?Analyser.Subject {
    return switch (p) {
        .node => |n| .{ .elem = n.elem },
        .subject => |s| switch (s) {
            .zone => |z| .{ .zone = @backingInt(z) },
            .edge => |e| .{ .edge = @backingInt(e) },
            .cell => |c| .{ .cell = @backingInt(c) },
            .node => null,
            .class => |c| if (c.zone) |z| .{ .zone = @backingInt(z) } else null,
        },
    };
}

/// Nodes, once the graph is built: each element's class is an IR node.
pub fn finish(a: *Analyser) error{OutOfMemory}![]Binding {
    const bindings = try a.gpa.alloc(Binding, a.bindings.items.len);
    for (a.bindings.items, bindings) |p, *b| b.* = .{ .subject = resolve(a, p.subject, a.node_of), .attr = p.attr, .layer = p.layer, .descriptor = p.descriptor, .key = p.key, .value = p.value };
    return bindings;
}

fn resolve(a: *Analyser, p: Pending, node_of: []const Ir.NodeIndex) Subject {
    return switch (p) {
        .subject => |s| s,
        .node => |n| .{ .node = node_of[a.uf.find(n.elem)] },
    };
}
