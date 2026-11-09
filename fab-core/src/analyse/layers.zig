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
//! one. Only `:style` is read; `:prove` and `:place` wait for plan step 11.
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
pub const Binding = struct { subject: Subject, attr: Node.Index, layer: Layer };

/// A token naming a subject, for the language server.
pub const Reference = struct { token: TokenIndex, subject: Subject };

/// A subject before the graph is built: a node is still an element, with
/// the end that reached it, if one did.
pub const Pending = union(enum) {
    subject: Subject,
    node: struct { elem: u32, end: ?Ir.End, token: TokenIndex },
};

pub const PendingBinding = struct { subject: Pending, attr: Node.Index, layer: Layer };
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
        // Tokens, `[ink] := [#fff]`, are read in the style pass; their
        // shape was checked. Other shapes were reported with it.
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
        // Declared with the proof and place shells (plan step 11); the
        // description is unsupported already.
        if (std.mem.eql(u8, name, ":prove") or std.mem.eql(u8, name, ":place")) return;
        try a.fail(.unknown_attribute, name_token);
        return;
    };
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
    for (subjects) |s| try a.bindings.append(a.gpa, .{ .subject = s.subject, .attr = attr, .layer = .style });
}

/// The classes of what a descriptor is written at: an element's own, or a
/// class. A node's kind is known once the graph is built (plan step 9c3).
fn classesOf(subjects: []const Owner) Env.Classes {
    var classes: Env.Classes = .empty;
    for (subjects) |s| switch (s.subject) {
        .node => classes.insert(.node),
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
                try add(a, out, .{ .subject = .{ .node = .{ .elem = elem, .end = null, .token = main } }, .zone = null }, main);
            },
            .class_id => try class(a, main, zone.index, out),
            .zone_id => if (std.mem.eql(u8, cst.tokenText(main), a.cst.tokenText(zone.token))) {
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
            const side: Ir.End.Side = if (cst.tag(node) == .prefix) .dom else .cod;
            const elem = if (side == .dom) g.left else g.right;
            const end: Ir.End = .{ .edge = @fromBackingInt(g.index), .side = side };
            try add(a, out, .{ .subject = .{ .node = .{ .elem = elem, .end = end, .token = edge_token } }, .zone = null }, edge_token);
        },
        // `G.f` inside G's block is `f`; `A.f` is A's to describe.
        .juxtafix => {
            const left, const right = cst.data(node).nodes;
            if (cst.tag(left) != .leaf or cst.tokenTag(cst.mainToken(left)) != .zone_id) return notASubject(a, node);
            const left_token = cst.mainToken(left);
            if (!std.mem.eql(u8, cst.tokenText(left_token), cst.tokenText(zone.token)))
                return a.fail(.another_diagrams_subject, left_token);
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
    return if (zone.broken) null else zone;
}

fn class(a: *Analyser, token: TokenIndex, zone: ?Ir.ZoneIndex, out: *std.ArrayList(Owner)) error{OutOfMemory}!void {
    const c = Env.class(a.cst.tokenText(token)) orelse return a.fail(.unknown_class, token);
    const subject: Subject = .{ .class = .{ .classes = .initOne(c), .zone = zone } };
    try add(a, out, .{ .subject = .{ .subject = subject }, .zone = null }, token);
}

fn add(a: *Analyser, out: *std.ArrayList(Owner), owner: Owner, token: TokenIndex) error{OutOfMemory}!void {
    try out.append(a.gpa, owner);
    try a.references.append(a.gpa, .{ .token = token, .subject = owner.subject });
}

fn reference(a: *Analyser, token: TokenIndex, subject: Pending) error{OutOfMemory}!void {
    try a.references.append(a.gpa, .{ .token = token, .subject = subject });
}

/// A chain, a path or a pinch addresses a structure, not one element.
fn notASubject(a: *Analyser, node: Node.Index) error{OutOfMemory}!void {
    try a.fail(.not_a_subject, a.cst.firstToken(node));
}

// ---------------------------------------------------------------------------
// After the graph

/// Nodes, once the graph is built: each element's class is an IR node.
pub fn finish(a: *Analyser, node_of: []const Ir.NodeIndex) error{OutOfMemory}!struct { []Binding, []Reference } {
    const bindings = try a.gpa.alloc(Binding, a.bindings.items.len);
    errdefer a.gpa.free(bindings);
    for (a.bindings.items, bindings) |p, *b| b.* = .{ .subject = resolve(a, p.subject, node_of), .attr = p.attr, .layer = p.layer };
    const references = try a.gpa.alloc(Reference, a.references.items.len);
    for (a.references.items, references) |p, *r| r.* = .{ .token = p.token, .subject = resolve(a, p.subject, node_of) };
    return .{ bindings, references };
}

fn resolve(a: *Analyser, p: Pending, node_of: []const Ir.NodeIndex) Subject {
    return switch (p) {
        .subject => |s| s,
        .node => |n| .{ .node = node_of[a.uf.find(n.elem)] },
    };
}
