//! The statements that make vocabulary, not structure (statements.md §21),
//! read into the environment:
//!
//!   :Shape :: [circle], [box]         a declared type and its labels
//!   :Side :: :Facing, :On             a declared type and its members
//!   :Angle :: :Number!                one member: the numbers and twins
//!   :Style :: { &node :x :: :Color }  a record type and its descriptors
//!   (&edge, &cell) :side :: :Side     a function's signature
//!   :Color [warn] := [red]            a named value, its type a contract
//!
//! Types are declared, never named (statements.md §22.8); a declaration
//! repeated adds to its type. A type holds values or descriptors, never both
//! (§22.9).
//!
//! Names are defined once, before use, in source order. Bundles are
//! functions too, defined by records (`records.zig`).

const std = @import("std");
const Cst = @import("../parse/Cst.zig");
const Analyser = @import("Analyser.zig");
const Env = @import("Env.zig");
const value = @import("value.zig");
const definitions = @import("definitions.zig");
const records = @import("records.zig");

const Node = Cst.Node;
const TokenIndex = Cst.TokenIndex;
const TypeIndex = Env.TypeIndex;

// ---------------------------------------------------------------------------
// Declarations

/// `:T :: …`: a new declared type, or what a declaration adds to one. Each
/// item is a label (`[circle]`), a member, a type whose values the type
/// holds (`:Number!`, `:Facing`, `[:Tip/:Stroke/:Tip]`), or a signature,
/// which makes it a record type (`&node :fill :: :Color`).
pub fn declareType(a: *Analyser, head: Node.Index, body: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    const env = &a.env;
    const type_token = cst.mainToken(head);
    const type_name = cst.tokenText(type_token);

    const t: TypeIndex = if (env.type_table.get(type_name)) |named| named.index else blk: {
        const t = try env.newDeclared(a.gpa);
        try env.type_table.put(a.gpa, type_name, .{ .index = t, .token = type_token });
        env.name(t, type_name);
        break :blk t;
    };

    var one: [1]Node.Index = undefined;
    for (itemsOf(cst, body, &one)) |item| {
        if (cst.tag(item) == .statement) {
            try descriptor(a, t, item);
            continue;
        }
        if (isTypeItem(cst, item)) {
            try member(a, t, type_token, item);
            continue;
        }
        if (!env.takesLabels(t)) {
            try a.fail(.labels_on_structure, type_token);
            return;
        }
        const token = switch (labelToken(cst, item)) {
            .label => |token| token,
            // Its shape was reported when the brackets were read.
            .malformed => continue,
            .not_a_label => {
                try a.fail(.not_a_label, cst.firstToken(item));
                continue;
            },
        };
        switch (a.env.get(t)) {
            .declared => |id| a.env.declared.items[id].holds = .values,
            else => {},
        }
        const text = cst.tokenText(token);
        try define(a, text[1 .. text.len - 1], .{ .type = t, .token = token, .body = null });
    }
}

/// A type among a declaration's items, rather than a label: a type name, a
/// twin, a group, a bracket of type names.
fn isTypeItem(cst: *const Cst, item: Node.Index) bool {
    return switch (cst.tag(item)) {
        .leaf => switch (cst.tokenTag(cst.mainToken(item))) {
            .type_id => true,
            .val => blk: {
                var reader = value.read(cst.tokenText(cst.mainToken(item)));
                while (true) {
                    const element = (reader.next() catch continue) orelse break;
                    if (element.kind == .type) break :blk true;
                }
                break :blk false;
            },
            else => false,
        },
        .postfix, .group, .juxtafix => true,
        else => false,
    };
}

/// `&node :fill :: :Color` in `:Style :: { … }`: a descriptor of the record
/// type `t`. Inside a type, `::` declares only signatures, and nothing is
/// named.
fn descriptor(a: *Analyser, t: TypeIndex, item: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    const head, const body = cst.data(item).nodes;
    if (cst.tokenTag(cst.mainToken(item)) == .defn) {
        try a.fail(.naming_in_type, cst.mainToken(item));
        return;
    }
    if (cst.tag(head) != .entry or !definitions.isVocabulary(cst, head)) {
        try a.fail(.bad_declaration_head, cst.firstToken(head));
        return;
    }
    const holds = switch (a.env.get(t)) {
        .declared => |id| &a.env.declared.items[id].holds,
        else => null,
    };
    if (holds == null or holds.?.* == .values) {
        try a.fail(.descriptors_on_value_type, cst.firstToken(item));
        return;
    }
    holds.?.* = .descriptors;
    try signature(a, head, body, t);
}

/// Adds the values of `item`'s type to the declared type `t`.
fn member(a: *Analyser, t: TypeIndex, type_token: TokenIndex, item: Node.Index) error{OutOfMemory}!void {
    const m = try typeExpression(a, item) orelse return;
    const id = switch (a.env.get(t)) {
        .declared => |id| id,
        // The built-ins are the language's: they take labels, no members.
        else => {
            try a.fail(.bad_declaration_head, type_token);
            return;
        },
    };
    // A record type holds descriptors only.
    switch (a.env.declared.items[id].holds) {
        .descriptors => {
            try a.fail(.labels_on_structure, type_token);
            return;
        },
        else => a.env.declared.items[id].holds = .values,
    }
    if (a.env.includes(m, t)) {
        try a.fail(.type_includes_itself, a.cst.firstToken(item));
        return;
    }
    const members = &a.env.declared.items[id].members;
    for (members.items) |existing| if (existing == m) return;
    try members.append(a.gpa, m);
}

/// A label is one name or one symbol, alone in its bracket, with no `!`.
pub fn labelToken(cst: *const Cst, node: Node.Index) union(enum) { label: TokenIndex, malformed, not_a_label } {
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

/// `(&node, &zone) :fill :: :Color`, at the top level (`record` null) or in
/// a record type's declaration. With an empty key slot, `:axiom.[]`, a table.
pub fn signature(a: *Analyser, head: Node.Index, body: Node.Index, record: ?TypeIndex) error{OutOfMemory}!void {
    const cst = a.cst;
    const parts = cst.children(head);
    var classes: Env.Classes = .empty;
    const known = try readClasses(a, parts[0], &classes);
    const function_token = cst.mainToken(parts[1]);
    // A declaration names no key: the slot is empty.
    const key = cst.key(parts[1]);
    if (key) |k| if (!std.mem.eql(u8, cst.tokenText(k), "[]")) try a.fail(.key_in_declaration, k);
    const t = try typeExpression(a, body) orelse .unknown;
    if (!known) return;

    const gop = try a.env.functions.getOrPut(a.gpa, cst.tokenText(function_token));
    if (gop.found_existing) {
        try a.errors.append(a.gpa, .{ .tag = .name_defined_twice, .token = function_token, .related = if (gop.value_ptr.prelude) null else gop.value_ptr.token });
        return;
    }
    gop.value_ptr.* = .{ .classes = Env.within(classes), .type = t, .token = function_token, .record = record, .table = key != null };
}

/// The classes of `&node` or `(&node, &zone)`. Whether all are known.
pub fn readClasses(a: *Analyser, node: Node.Index, classes: *Env.Classes) error{OutOfMemory}!bool {
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

pub const NamedValue = struct { contract: ?TypeIndex, name: ?[]const u8 };

/// `[warn] := [red]`, `:Color [warn] := [red]`, `:Style [dark] := { … }`.
/// The name takes the type written before it, a contract the value must
/// fit, or else the value's own type. Returns the contract, and the name
/// defined, if any. A record's structure is checked against a record type's
/// contract descriptor by descriptor (`records.theme`), not here.
pub fn namedValue(a: *Analyser, head: Node.Index, body: Node.Index) error{OutOfMemory}!NamedValue {
    const cst = a.cst;
    const name_node, const contract_node: ?Node.Index = if (cst.tag(head) == .o_chain)
        .{ cst.children(head)[1], cst.children(head)[0] }
    else
        .{ head, null };
    const name_token = cst.mainToken(name_node);

    const contract: ?TypeIndex = if (contract_node) |node| try typeExpression(a, node) else null;
    const actual = try typeOf(a, body);
    if (contract) |expected| {
        const at = cst.firstToken(body);
        try check(a, actual, expected, .contract_broken, at, cst.firstToken(contract_node.?));
        // `:Style [both] := [x/y]`: named records, by their structure.
        if (cst.tag(body) == .leaf and a.env.fits(actual, expected)) try records.structure(a, body, expected, .contract_broken);
    }
    const none: NamedValue = .{ .contract = contract, .name = null };

    // The name: one name, alone in its bracket.
    var reader = value.read(cst.tokenText(name_token));
    const element = (reader.next() catch return none) orelse {
        try a.fail(.bad_naming_head, name_token);
        return none;
    };
    if (element.kind != .name or element.inverted or (reader.next() catch return none) != null) {
        try a.fail(.bad_naming_head, name_token);
        return none;
    }
    // A name for named records keeps their structure.
    const contents: []Env.Content = if (cst.tag(body) == .leaf) try records.named(a, body) else &.{};
    // A contract names no record type: a record keeps its structure only.
    const t = if (cst.tag(body) == .block) actual else contract orelse actual;
    try define(a, element.text, .{ .type = t, .token = name_token, .body = body, .contents = contents });
    return .{ .contract = contract, .name = element.text };
}

/// Defines a bracket name, once.
pub fn define(a: *Analyser, text: []const u8, entry: Env.Value) error{OutOfMemory}!void {
    const gop = try a.env.values.getOrPut(a.gpa, text);
    if (gop.found_existing) {
        const first = gop.value_ptr.*;
        // A label of another type: one label, one type.
        const tag: Analyser.Error.Tag = if (first.body == null and entry.body == null and first.type != entry.type)
            .label_in_two_types
        else
            .name_defined_twice;
        try a.errors.append(a.gpa, .{ .tag = tag, .token = entry.token.?, .related = if (first.prelude) null else first.token });
        return;
    }
    gop.value_ptr.* = entry;
}

// ---------------------------------------------------------------------------
// Types

/// A type, as it is written (statements.md §22.8): a name, `:Color`; a
/// twin, `:Number!`; a union, `:A, :B` or `(:A, :B)`; a bracket of type
/// names, `[:Tip/:Stroke/:Tip]` a tuple, `[:Style]` a list. Null after
/// reporting why it is no type.
pub fn typeExpression(a: *Analyser, node: Node.Index) error{OutOfMemory}!?TypeIndex {
    const cst = a.cst;
    const token = cst.mainToken(node);
    switch (cst.tag(node)) {
        .leaf => switch (cst.tokenTag(token)) {
            .type_id => {
                const named = a.env.type_table.get(cst.tokenText(token)) orelse return notAType(a, node);
                return named.index;
            },
            .val => return bracketType(a, token),
            else => return notAType(a, node),
        },
        .postfix => {
            if (cst.tokenTag(token) != .bang) return notAType(a, node);
            const inner = try typeExpression(a, cst.data(node).node) orelse return null;
            return try a.env.twin(a.gpa, inner) orelse {
                try a.fail(.not_invertible, token);
                return null;
            };
        },
        .group => return unionOf(a, cst.children(node)[0]),
        .items => return unionOf(a, node),
        // `:List.(:Style)`, `:Color.(:Text)`: no type takes parameters.
        .juxtafix => {
            const left = cst.data(node).nodes[0];
            if (cst.tag(left) == .leaf and cst.tokenTag(cst.mainToken(left)) == .type_id) {
                try a.fail(.type_with_parameters, cst.mainToken(left));
                return null;
            }
            return notAType(a, node);
        },
        else => return notAType(a, node),
    }
}

/// The union of the types among `node`'s items; one item is its own type.
fn unionOf(a: *Analyser, node: Node.Index) error{OutOfMemory}!?TypeIndex {
    var members: std.ArrayList(TypeIndex) = .empty;
    defer members.deinit(a.gpa);
    var failed = false;
    var one: [1]Node.Index = undefined;
    for (itemsOf(a.cst, node, &one)) |item| {
        const t = try typeExpression(a, item) orelse {
            failed = true;
            continue;
        };
        // Unions flatten: a choice among choices is one choice.
        switch (a.env.get(t)) {
            .@"union" => |ts| for (ts) |m| try appendNew(a, &members, m),
            else => try appendNew(a, &members, t),
        }
    }
    if (failed) return null;
    if (members.items.len == 1) return members.items[0];
    return try a.env.intern(a.gpa, .{ .@"union" = members.items });
}

fn appendNew(a: *Analyser, list: *std.ArrayList(TypeIndex), t: TypeIndex) error{OutOfMemory}!void {
    for (list.items) |existing| if (existing == t) return;
    try list.append(a.gpa, t);
}

/// `[:Tip/:Stroke/:Tip]`, a tuple; `[:Style]`, a list. A bracket of values
/// is no type; one mixing both was reported with the brackets.
fn bracketType(a: *Analyser, token: TokenIndex) error{OutOfMemory}!?TypeIndex {
    var slots: std.ArrayList(TypeIndex) = .empty;
    defer slots.deinit(a.gpa);
    var values = false;
    var failed = false;
    var reader = value.read(a.cst.tokenText(token));
    while (true) {
        const element = (reader.next() catch {
            failed = true;
            continue;
        }) orelse break;
        if (element.kind != .type) {
            values = true;
            continue;
        }
        const named = a.env.type_table.get(element.text) orelse {
            try a.fail(.not_a_type, token);
            failed = true;
            continue;
        };
        const t = if (element.inverted) try a.env.twin(a.gpa, named.index) orelse {
            try a.fail(.not_invertible, token);
            failed = true;
            continue;
        } else named.index;
        try slots.append(a.gpa, t);
    }
    if (values) {
        if (slots.items.len == 0 and !failed) try a.fail(.not_a_type, token);
        return null;
    }
    if (failed) return null;
    if (slots.items.len == 1) return try a.env.intern(a.gpa, .{ .list = slots.items[0] });
    return try a.env.intern(a.gpa, .{ .tuple = slots.items });
}

/// Reports `tag` at `token` unless a value of type `actual` fits
/// `expected`; *not invertible* when only its `!`s are in the way.
pub fn check(a: *Analyser, actual: TypeIndex, expected: TypeIndex, tag: Analyser.Error.Tag, token: TokenIndex, related: ?TokenIndex) error{OutOfMemory}!void {
    if (a.env.fits(actual, expected)) return;
    const plain = try a.env.untwinned(a.gpa, actual);
    const reported: Analyser.Error.Tag = if (plain != actual and a.env.fits(plain, expected)) .not_invertible else tag;
    try a.errors.append(a.gpa, .{ .tag = reported, .token = token, .related = related });
}

fn notAType(a: *Analyser, node: Node.Index) error{OutOfMemory}!?TypeIndex {
    try a.fail(.not_a_type, a.cst.firstToken(node));
    return null;
}

/// A value's type, read from its shape: `"…"` text, `$…$` math, `{ … }` a
/// record (checked by its structure where used), a bracket its elements' (one, or a tuple
/// of several; `[]` nil). A name not yet defined is reported, and is
/// unknown.
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
    var types = false;
    while (true) {
        // Shapes were reported when the brackets were read.
        const element = (reader.next() catch {
            try elements.append(a.gpa, .unknown);
            continue;
        }) orelse break;
        const t: TypeIndex = switch (element.kind) {
            .empty => .nil,
            .color => .color,
            .number => .number,
            .range => .range,
            .type => {
                types = true;
                continue;
            },
            .name, .symbol => if (a.env.values.get(element.text)) |v| v.type else blk: {
                try a.fail(.undefined_name, token);
                break :blk .unknown;
            },
        };
        // `[30!]`, `[?!]`: the twin, where the type has one.
        try elements.append(a.gpa, if (!element.inverted) t else try a.env.twin(a.gpa, t) orelse blk: {
            try a.fail(.not_invertible, token);
            break :blk .unknown;
        });
    }
    // `[:Style]` where a value goes; mixed with values, it was reported
    // with the brackets.
    if (types) {
        if (elements.items.len == 0) try a.fail(.type_as_value, token);
        return .unknown;
    }
    return switch (elements.items.len) {
        0 => unreachable, // one element more than slashes
        1 => elements.items[0],
        else => try a.env.intern(a.gpa, .{ .tuple = elements.items }),
    };
}

/// A body's items: the children of `items`, a block's, or the one item,
/// put in `one`.
pub fn itemsOf(cst: *const Cst, node: Node.Index, one: *[1]Node.Index) []const Node.Index {
    switch (cst.tag(node)) {
        .items => return cst.children(node),
        .block => return itemsOf(cst, cst.children(node)[0], one),
        else => {
            one[0] = node;
            return one;
        },
    }
}
