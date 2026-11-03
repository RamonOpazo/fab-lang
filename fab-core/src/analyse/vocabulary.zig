//! The statements that make vocabulary, not structure (statements.md §21),
//! read into the environment:
//!
//!   :Shape :: [circle], [box]         a label type and its labels
//!   (&edge, &cell) :side :: :Side     a function's signature
//!   :Side := :Union.(:Facing, :On)    an alias
//!   :Color [warn] := [red]            a named value, its type a contract
//!
//! Names are defined once, before use, in source order. Names inside
//! records (bundles, themes, layers) are read with plan steps 8d and 9.

const std = @import("std");
const Cst = @import("../parse/Cst.zig");
const Analyser = @import("Analyser.zig");
const Env = @import("Env.zig");
const value = @import("value.zig");

const Node = Cst.Node;
const TokenIndex = Cst.TokenIndex;
const TypeIndex = Env.TypeIndex;

// ---------------------------------------------------------------------------
// Declarations

/// `:Shape :: [circle], [box]`: a new label type, or labels added to a type
/// that takes them (`:Color :: [ink]`).
pub fn labels(a: *Analyser, head: Node.Index, body: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    const env = &a.env;
    const type_token = cst.mainToken(head);
    const type_name = cst.tokenText(type_token);

    const t: TypeIndex = if (env.type_table.get(type_name)) |named| switch (named) {
        .type => |declared| if (env.takesLabels(declared.index)) declared.index else {
            try a.fail(.labels_on_structure, type_token);
            return;
        },
        .constructor => {
            try a.fail(.labels_on_structure, type_token);
            return;
        },
    } else blk: {
        const t = try env.newLabels(a.gpa);
        try env.type_table.put(a.gpa, type_name, .{ .type = .{ .index = t, .token = type_token } });
        env.name(t, type_name);
        break :blk t;
    };

    var one: [1]Node.Index = undefined;
    for (itemsOf(cst, body, &one)) |item| {
        const token = switch (labelToken(cst, item)) {
            .label => |token| token,
            // Its shape was reported when the brackets were read.
            .malformed => continue,
            .not_a_label => {
                try a.fail(.not_a_label, cst.firstToken(item));
                continue;
            },
        };
        const text = cst.tokenText(token);
        try define(a, text[1 .. text.len - 1], .{ .type = t, .token = token, .body = null });
    }
}

/// A label is one name or one symbol, alone in its bracket, with no `!`.
fn labelToken(cst: *const Cst, node: Node.Index) union(enum) { label: TokenIndex, malformed, not_a_label } {
    if (cst.tag(node) != .leaf) return .not_a_label;
    const token = cst.mainToken(node);
    if (cst.tokenTag(token) != .val) return .not_a_label;
    var reader = value.read(cst.tokenText(token));
    const element = (reader.next() catch return .malformed) orelse return .not_a_label;
    if ((reader.next() catch return .malformed) != null) return .not_a_label;
    if (element.inverted) return .not_a_label;
    return switch (element.kind) {
        .name, .symbol => .{ .label = token },
        else => .not_a_label,
    };
}

/// `(&node, &zone) :fill :: :Color`.
pub fn signature(a: *Analyser, head: Node.Index, body: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    const parts = cst.children(head);
    var classes: Env.Classes = .empty;
    const known = try readClasses(a, parts[0], &classes);
    const function_token = cst.mainToken(parts[1]);
    const t = try typeExpression(a, body) orelse .unknown;
    if (!known) return;

    const gop = try a.env.functions.getOrPut(a.gpa, cst.tokenText(function_token));
    if (gop.found_existing) {
        try a.errors.append(a.gpa, .{ .tag = .name_defined_twice, .token = function_token, .related = gop.value_ptr.token });
        return;
    }
    gop.value_ptr.* = .{ .classes = classes, .type = t, .token = function_token };
}

/// The classes of `&node` or `(&node, &zone)`. Whether all are known.
fn readClasses(a: *Analyser, node: Node.Index, classes: *Env.Classes) error{OutOfMemory}!bool {
    const cst = a.cst;
    if (cst.tag(node) == .leaf) {
        const token = cst.mainToken(node);
        if (Env.class(cst.tokenText(token))) |c| {
            classes.insert(c);
            return true;
        }
        try a.fail(.unknown_class, token);
        return false;
    }
    var known = true;
    for (cst.children(node)) |child| known = try readClasses(a, child, classes) and known;
    return known;
}

// ---------------------------------------------------------------------------
// Definitions

/// `:Side := :Union.(:Facing, :On)`: a second name for a type.
pub fn alias(a: *Analyser, head: Node.Index, body: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    const token = cst.mainToken(head);
    const t = try typeExpression(a, body) orelse .unknown;
    const gop = try a.env.type_table.getOrPut(a.gpa, cst.tokenText(token));
    if (gop.found_existing) {
        const first: ?TokenIndex = switch (gop.value_ptr.*) {
            .type => |declared| declared.token,
            .constructor => null,
        };
        try a.errors.append(a.gpa, .{ .tag = .name_defined_twice, .token = token, .related = first });
        return;
    }
    gop.value_ptr.* = .{ .type = .{ .index = t, .token = token } };
    a.env.name(t, cst.tokenText(token));
}

/// `[warn] := [red]`, `:Color [warn] := [red]`, `:Record [dark] := { … }`.
/// The name takes the type written before it, a contract the value must
/// fit, or else the value's own type.
pub fn namedValue(a: *Analyser, head: Node.Index, body: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    const name_node, const contract_node: ?Node.Index = if (cst.tag(head) == .o_chain)
        .{ cst.children(head)[1], cst.children(head)[0] }
    else
        .{ head, null };
    const name_token = cst.mainToken(name_node);

    const contract: ?TypeIndex = if (contract_node) |node| try typeExpression(a, node) else null;
    const actual = try typeOf(a, body);
    if (contract) |expected| {
        if (!a.env.fits(actual, expected))
            try a.errors.append(a.gpa, .{ .tag = .contract_broken, .token = cst.firstToken(body), .related = cst.mainToken(contract_node.?) });
    }

    // The name: one name, alone in its bracket.
    var reader = value.read(cst.tokenText(name_token));
    const element = (reader.next() catch return) orelse {
        try a.fail(.bad_definition_head, name_token);
        return;
    };
    if (element.kind != .name or element.inverted or (reader.next() catch return) != null) {
        try a.fail(.bad_definition_head, name_token);
        return;
    }
    try define(a, element.text, .{ .type = contract orelse actual, .token = name_token, .body = body });
}

/// Defines a bracket name, once.
fn define(a: *Analyser, text: []const u8, entry: Env.Value) error{OutOfMemory}!void {
    const gop = try a.env.values.getOrPut(a.gpa, text);
    if (gop.found_existing) {
        const first = gop.value_ptr.*;
        // A label of another type: one label, one type.
        const tag: Analyser.Error.Tag = if (first.body == null and entry.body == null and first.type != entry.type)
            .label_in_two_types
        else
            .name_defined_twice;
        try a.errors.append(a.gpa, .{ .tag = tag, .token = entry.token.?, .related = first.token });
        return;
    }
    gop.value_ptr.* = entry;
}

// ---------------------------------------------------------------------------
// Types

/// `:Color`, `:List.(:Color)`, `:Tuple.(:Head, :Union.(:Line, :None))`.
/// Null after reporting why it is no type.
pub fn typeExpression(a: *Analyser, node: Node.Index) error{OutOfMemory}!?TypeIndex {
    const cst = a.cst;
    switch (cst.tag(node)) {
        .leaf => {
            const token = cst.mainToken(node);
            if (cst.tokenTag(token) != .type_id) return notAType(a, node);
            const named = a.env.type_table.get(cst.tokenText(token)) orelse return notAType(a, node);
            return switch (named) {
                .type => |declared| declared.index,
                .constructor => {
                    try a.fail(.wrong_type_parameters, token);
                    return null;
                },
            };
        },
        .juxtafix => {
            const left, const right = cst.data(node).nodes;
            const token = cst.mainToken(left);
            if (cst.tag(left) != .leaf or cst.tokenTag(token) != .type_id or cst.tag(right) != .group) return notAType(a, node);
            const named = a.env.type_table.get(cst.tokenText(token)) orelse return notAType(a, left);
            const constructor = switch (named) {
                .constructor => |c| c,
                .type => {
                    try a.fail(.wrong_type_parameters, token);
                    return null;
                },
            };

            var params: std.ArrayList(TypeIndex) = .empty;
            defer params.deinit(a.gpa);
            var failed = false;
            var one: [1]Node.Index = undefined;
            for (itemsOf(cst, cst.children(right)[0], &one)) |item| {
                if (try typeExpression(a, item)) |t| try params.append(a.gpa, t) else failed = true;
            }
            if (failed) return null;
            return switch (constructor) {
                .list => if (params.items.len != 1) {
                    try a.fail(.wrong_type_parameters, token);
                    return null;
                } else try a.env.intern(a.gpa, .{ .list = params.items[0] }),
                .tuple => try a.env.intern(a.gpa, .{ .tuple = params.items }),
                .@"union" => try a.env.intern(a.gpa, .{ .@"union" = params.items }),
            };
        },
        else => return notAType(a, node),
    }
}

fn notAType(a: *Analyser, node: Node.Index) error{OutOfMemory}!?TypeIndex {
    try a.fail(.not_a_type, a.cst.firstToken(node));
    return null;
}

/// A value's type, read from its shape: `"…"` text, `$…$` math, `{ … }` a
/// record, a bracket its elements' (one, or a tuple of several; `[]` a list
/// of nothing). A name not yet defined is reported, and is unknown.
pub fn typeOf(a: *Analyser, node: Node.Index) error{OutOfMemory}!TypeIndex {
    const cst = a.cst;
    if (cst.tag(node) == .block) return .record;
    if (cst.tag(node) != .leaf) return .unknown;
    const token = cst.mainToken(node);
    switch (cst.tokenTag(token)) {
        .str => return .text,
        .math => return .math,
        .val => {},
        else => return .unknown,
    }

    var elements: std.ArrayList(TypeIndex) = .empty;
    defer elements.deinit(a.gpa);
    var reader = value.read(cst.tokenText(token));
    while (true) {
        // Shapes were reported when the brackets were read.
        const element = (reader.next() catch {
            try elements.append(a.gpa, .unknown);
            continue;
        }) orelse break;
        try elements.append(a.gpa, switch (element.kind) {
            .empty => .nothing,
            .color => .color,
            .number => .number,
            .range => .range,
            .name, .symbol => if (a.env.values.get(element.text)) |v| v.type else blk: {
                try a.fail(.undefined_name, token);
                break :blk .unknown;
            },
        });
    }
    return switch (elements.items.len) {
        0 => try a.env.intern(a.gpa, .{ .list = .nothing }),
        1 => elements.items[0],
        else => try a.env.intern(a.gpa, .{ .tuple = elements.items }),
    };
}

/// A body's items: the children of `items`, a block's, or the one item,
/// put in `one`.
fn itemsOf(cst: *const Cst, node: Node.Index, one: *[1]Node.Index) []const Node.Index {
    switch (cst.tag(node)) {
        .items => return cst.children(node),
        .block => return itemsOf(cst, cst.children(node)[0], one),
        else => {
            one[0] = node;
            return one;
        },
    }
}
