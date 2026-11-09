//! Records, `{ … }`, checked against the environment (statements.md §21.6,
//! §22). Two of them are read here; the layers (`G :style { … }`) wait for
//! plan steps 9 and 11.
//!
//!   :Style [dark] := { [ink] := [#ddd], &zone :fill [#111] }    a theme
//!   :terminal := { :shape [circle], :fill [red] }                a bundle
//!
//! A theme holds tokens, named with `:=`, class contexts, and descriptors
//! with no context, which bind the diagram it is applied to. A bundle holds
//! descriptors only. Neither has a type (statements.md §22.9): each keeps
//! its structure, the record types its descriptors belong to, and is checked
//! by it where it is used. A record under a contract is checked as written.
//!
//! The shapes `definitions.entries` reports (bare terms, levels,
//! declarations) are passed over here.

const std = @import("std");
const Cst = @import("../parse/Cst.zig");
const Analyser = @import("Analyser.zig");
const Env = @import("Env.zig");
const definitions = @import("definitions.zig");
const vocabulary = @import("vocabulary.zig");
const valueReader = @import("value.zig").read;

const Node = Cst.Node;
const TokenIndex = Cst.TokenIndex;
const TypeIndex = Env.TypeIndex;

/// `[dark] := { … }`, checked against the record type `record` when a
/// contract gives one (`:Style [dark] := …`). Functions with no subject bind
/// the owner, a diagram. Returns its structure.
pub fn theme(a: *Analyser, body: Node.Index, record: ?TypeIndex) error{OutOfMemory}![]Env.Content {
    var contents: Contents = .{};
    defer contents.list.deinit(a.gpa);
    try themeItems(a, body, .initOne(.zone), record, &contents);
    return a.env.arena.allocator().dupe(Env.Content, contents.list.items);
}

/// The items of a theme, or of a subject's block in it, whose functions
/// bind `owner`.
fn themeItems(a: *Analyser, node: Node.Index, owner: Env.Classes, record: ?TypeIndex, contents: ?*Contents) error{OutOfMemory}!void {
    const cst = a.cst;
    var one: [1]Node.Index = undefined;
    for (vocabulary.itemsOf(cst, node, &one)) |item| switch (cst.tag(item)) {
        .statement => if (cst.tokenTag(cst.mainToken(item)) == .defn) try token(a, item),
        .entry => {
            const parts = cst.children(item);
            const subject = cst.subject(item) orelse {
                for (parts) |part| try themeKey(a, part, owner, record, contents);
                continue;
            };
            if (!definitions.areClasses(cst, subject)) {
                try a.fail(.element_in_theme, cst.firstToken(subject));
                continue;
            }
            var classes: Env.Classes = .empty;
            if (!try vocabulary.readClasses(a, subject, &classes)) continue;
            for (parts[1..]) |part| try themeKey(a, part, classes, record, contents);
        },
        else => {},
    };
}

fn themeKey(a: *Analyser, part: Node.Index, owner: Env.Classes, record: ?TypeIndex, contents: ?*Contents) error{OutOfMemory}!void {
    switch (a.cst.tag(part)) {
        .attr => try function(a, part, .{ .record = record, .at = .{ .subject = owner }, .contents = contents }),
        .block => try themeItems(a, part, owner, record, contents),
        else => {},
    }
}

/// `:terminal := { … }`: a new function, a flag applying where all its
/// contents apply.
pub fn bundle(a: *Analyser, name: Node.Index, body: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    const name_token = cst.mainToken(name);
    if (cst.inverted(name)) {
        try a.fail(.bad_naming_head, name_token);
        return;
    }
    var b: Bundle = .{};
    defer b.contents.list.deinit(a.gpa);
    if (isLiteral(cst, body)) {
        try a.fail(.wrong_type, cst.firstToken(body));
    } else try bundleItems(a, body, &b);

    const gop = try a.env.functions.getOrPut(a.gpa, cst.tokenText(name_token));
    if (gop.found_existing) {
        try a.errors.append(a.gpa, .{ .tag = .name_defined_twice, .token = name_token, .related = if (gop.value_ptr.prelude) null else gop.value_ptr.token });
        return;
    }
    const contents = a.env.arena.allocator().dupe(Env.Content, b.contents.list.items) catch |err| {
        _ = a.env.functions.remove(cst.tokenText(name_token));
        return err;
    };
    gop.value_ptr.* = .{ .classes = b.classes, .type = .flag, .token = name_token, .bundle = true, .contents = contents };
}

/// A structure: the record types some descriptors belong to, one content
/// per record type, the first, which is what a use reports.
const Contents = struct {
    list: std.ArrayList(Env.Content) = .empty,

    fn add(c: *Contents, gpa: std.mem.Allocator, content: Env.Content) error{OutOfMemory}!void {
        for (c.list.items) |existing| if (existing.record == content.record) return;
        try c.list.append(gpa, content);
    }

    /// `f` as written: its record type, or a bundle's structure.
    fn addFunction(c: *Contents, gpa: std.mem.Allocator, f: Env.Function, at: TokenIndex) error{OutOfMemory}!void {
        if (f.bundle) {
            for (f.contents) |content| try c.add(gpa, content);
        } else try c.add(gpa, .{ .record = f.record, .token = at });
    }
};

/// What a bundle's contents add up to: where they all apply, and their
/// structure.
const Bundle = struct {
    classes: Env.Classes = .full,
    contents: Contents = .{},
};

fn bundleItems(a: *Analyser, node: Node.Index, b: *Bundle) error{OutOfMemory}!void {
    const cst = a.cst;
    var one: [1]Node.Index = undefined;
    for (vocabulary.itemsOf(cst, node, &one)) |item| switch (cst.tag(item)) {
        // A token is no descriptor either.
        .statement => try a.fail(.subject_in_bundle, cst.firstToken(item)),
        .entry => {
            if (cst.subject(item)) |subject| {
                try a.fail(.subject_in_bundle, cst.firstToken(subject));
                continue;
            }
            for (cst.children(item)) |part| switch (cst.tag(part)) {
                .attr => try function(a, part, .{ .record = null, .at = .{ .bundle = b }, .contents = &b.contents }),
                .block => try bundleItems(a, part, b),
                else => {},
            };
        },
        else => {},
    };
}

/// Where a function is written: in a record of a record type (null where
/// none is expected yet: the record is checked where it is used), at a
/// subject of these classes or in a bundle, whose classes it narrows; and
/// the structure it adds to.
const Use = struct {
    record: ?TypeIndex,
    at: union(enum) { subject: Env.Classes, bundle: *Bundle },
    contents: ?*Contents = null,
};

/// `:fill [red]`, `:hide`, `:hide!`: known, applying where it is written,
/// and given what its signature asks for.
fn function(a: *Analyser, attr: Node.Index, use: Use) error{OutOfMemory}!void {
    const cst = a.cst;
    const name_token = cst.mainToken(attr);
    const f = a.env.functions.get(cst.tokenText(name_token)) orelse {
        try a.fail(.unknown_attribute, name_token);
        return;
    };
    const signature: ?TokenIndex = if (f.prelude) null else f.token;
    if (cst.key(attr)) |key| try checkKey(a, f, key, signature);

    const applies = switch (use.at) {
        .subject => |classes| Env.within(classes).subsetOf(f.classes),
        .bundle => |b| blk: {
            const meet = b.classes.intersectWith(f.classes);
            // Once empty, the bundle applies nowhere, and that was said.
            const ok = !meet.eql(.empty) or b.classes.eql(.empty);
            b.classes = meet;
            break :blk ok;
        },
    };
    // One error per use: the record type first, then the classes.
    if (use.contents) |c| try c.addFunction(a.gpa, f, name_token);
    const outside = if (use.record) |record| foreign(f, record) else null;
    if (outside) |related| {
        try a.errors.append(a.gpa, .{ .tag = .does_not_apply, .token = name_token, .related = related.token });
    } else if (!applies) try a.errors.append(a.gpa, .{ .tag = .does_not_apply, .token = name_token, .related = signature });

    const value = cst.data(attr).node;
    const inverted = cst.inverted(attr);
    if (f.type == .flag) {
        if (value != .root) {
            try a.fail(.value_given_to_flag, cst.firstToken(value));
        } else if (inverted and f.bundle) {
            // A bundle is no `:Flag!`: it has no twin.
            try a.fail(.not_invertible, name_token);
        }
        return;
    }
    if (inverted) try a.fail(.not_invertible, name_token);
    if (value == .root) {
        if (!inverted) try a.fail(.value_missing, name_token);
        return;
    }
    // A record after a descriptor has the descriptor's type.
    if (cst.tag(value) == .block and a.env.isRecord(f.type)) {
        try themeItems(a, value, f.classes, f.type, null);
        return;
    }
    const actual = try vocabulary.typeOf(a, value);
    try vocabulary.check(a, actual, f.type, .wrong_type, cst.firstToken(value), signature);
    if (a.env.fits(actual, f.type)) try structure(a, value, f.type, .wrong_type);
}

/// `:legend.[done]`: one name, on a table's descriptor. An entry with no key
/// leaves the slot off, so `.[]` is malformed (statements.md §22.8).
fn checkKey(a: *Analyser, f: Env.Function, key: TokenIndex, signature: ?TokenIndex) error{OutOfMemory}!void {
    if (!f.table) {
        try a.errors.append(a.gpa, .{ .tag = .key_not_taken, .token = key, .related = signature });
        return;
    }
    var reader = valueReader(a.cst.tokenText(key));
    const element = (reader.next() catch {
        try a.fail(reader.failure, key);
        return;
    }) orelse return;
    const one = (reader.next() catch null) == null;
    if (element.kind != .name or element.inverted or !one) try a.fail(.key_malformed, key);
}

/// The structure of a bracket of named records, `[dark/compact]`: their
/// contents, gathered. Empty for any other value.
pub fn named(a: *Analyser, value: Node.Index) error{OutOfMemory}![]Env.Content {
    var contents: Contents = .{};
    defer contents.list.deinit(a.gpa);
    try gather(a, value, &contents);
    if (contents.list.items.len == 0) return &.{};
    return a.env.arena.allocator().dupe(Env.Content, contents.list.items);
}

fn gather(a: *Analyser, value: Node.Index, contents: *Contents) error{OutOfMemory}!void {
    const cst = a.cst;
    if (cst.tag(value) != .leaf or cst.tokenTag(cst.mainToken(value)) != .val) return;
    var reader = valueReader(cst.tokenText(cst.mainToken(value)));
    while (true) {
        const element = (reader.next() catch continue) orelse break;
        if (element.kind != .name) continue;
        const v = a.env.values.get(element.text) orelse continue;
        for (v.contents) |c| try contents.add(a.gpa, c);
    }
}

/// Where a record type is expected, the named records in `value` are checked
/// by their structure (statements.md §22.9): each descriptor belongs to one
/// of the record types `expected` holds. Reports `tag` at the value, related
/// at the first descriptor that doesn't.
pub fn structure(a: *Analyser, value: Node.Index, expected: TypeIndex, tag: Analyser.Error.Tag) error{OutOfMemory}!void {
    var contents: Contents = .{};
    defer contents.list.deinit(a.gpa);
    try gather(a, value, &contents);
    if (contents.list.items.len == 0) return;

    var allowed: std.ArrayList(TypeIndex) = .empty;
    defer allowed.deinit(a.gpa);
    try recordTypes(a, expected, &allowed);
    // No record type expected: the value's type was the error, if any.
    if (allowed.items.len == 0) return;
    for (contents.list.items) |c| {
        const fits = if (c.record) |r| std.mem.indexOfScalar(TypeIndex, allowed.items, r) != null else false;
        if (fits) continue;
        try a.errors.append(a.gpa, .{ .tag = tag, .token = a.cst.firstToken(value), .related = if (c.prelude) null else c.token });
        return;
    }
}

/// The record types among `t`'s values: `[:Style]` holds `:Style`.
fn recordTypes(a: *Analyser, t: TypeIndex, out: *std.ArrayList(TypeIndex)) error{OutOfMemory}!void {
    switch (a.env.get(t)) {
        .declared => |id| {
            if (a.env.isRecord(t)) {
                if (std.mem.indexOfScalar(TypeIndex, out.items, t) == null) try out.append(a.gpa, t);
                return;
            }
            for (a.env.declared.items[id].members.items) |m| try recordTypes(a, m, out);
        },
        .list, .twin => |inner| try recordTypes(a, inner, out),
        .tuple, .@"union" => |ts| for (ts) |m| try recordTypes(a, m, out),
        else => {},
    }
}

/// Whether `f` belongs outside the record type `record`: the related token
/// to report (null in the prelude), or null when it belongs. A bundle
/// belongs where all its contents do.
fn foreign(f: Env.Function, record: TypeIndex) ?struct { token: ?TokenIndex } {
    if (!f.bundle) {
        if (f.record == record) return null;
        return .{ .token = if (f.prelude) null else f.token };
    }
    for (f.contents) |c| if (c.record != record) return .{ .token = if (c.prelude) null else c.token };
    return null;
}

/// `[ink] := [#dddddd]`: a label bound to a value of its type.
fn token(a: *Analyser, naming: Node.Index) error{OutOfMemory}!void {
    const cst = a.cst;
    const key, const value = cst.data(naming).nodes;
    const key_token = switch (vocabulary.labelToken(cst, key)) {
        .label => |t| t,
        .malformed => return,
        .not_a_label => {
            try a.fail(.not_a_label, cst.firstToken(key));
            return;
        },
    };
    const text = cst.tokenText(key_token);
    const label = a.env.values.get(text[1 .. text.len - 1]) orelse {
        try a.fail(.undefined_name, key_token);
        return;
    };
    // A named value is no label: it has a value already.
    if (label.body != null) {
        try a.fail(.not_a_label, key_token);
        return;
    }
    try vocabulary.check(a, try vocabulary.typeOf(a, value), label.type, .key_of_wrong_type, cst.firstToken(value), if (label.prelude) null else label.token);
}

fn isLiteral(cst: *const Cst, node: Node.Index) bool {
    return cst.tag(node) == .leaf and switch (cst.tokenTag(cst.mainToken(node))) {
        .str, .math, .val => true,
        else => false,
    };
}
