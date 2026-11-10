//! Decoding (plan step 9d2): CST values into `decoded.Value`, once, after
//! they are checked. Silent: whatever is wrong was reported by the checks,
//! and decodes as nil.

const std = @import("std");
const Analyser = @import("Analyser.zig");
const Cst = @import("../parse/Cst.zig");
const Env = @import("Env.zig");
const value = @import("value.zig");
const vocabulary = @import("vocabulary.zig");
const decoded = @import("decoded.zig");

const Node = Cst.Node;
const TypeIndex = Env.TypeIndex;
const Value = decoded.Value;

/// What a descriptor binds, written as `attr`: a flag on or off, or its
/// value read as its type expects.
pub fn attr(a: *Analyser, node: Node.Index, f: Env.Function) error{OutOfMemory}!Value {
    const cst = a.cst;
    const body = cst.data(node).node;
    if (f.bundle or f.type == .flag) return .{ .flag = !cst.inverted(node) };
    if (body == .root) return .nil;
    return of(a, body, f.type);
}

/// A value node, read as `expected` expects.
pub fn of(a: *Analyser, node: Node.Index, expected: TypeIndex) error{OutOfMemory}!Value {
    const cst = a.cst;
    switch (cst.tag(node)) {
        .leaf => {
            const main = cst.mainToken(node);
            const text = cst.tokenText(main);
            return switch (cst.tokenTag(main)) {
                .str => .{ .text = try unescape(a, text[1 .. text.len - 1], null) },
                .math => .{ .math = try unescape(a, text[1 .. text.len - 1], '$') },
                .val => bracket(a, text, expected),
                else => .nil,
            };
        },
        .block => return .{ .record = try record(a, node, .initOne(.zone)) },
        // A proposition, `( … )`: the proof's, read with its shell (step 11).
        else => return .nil,
    }
}

/// `[…]`: its element, or its elements where there are several or a list
/// is expected.
fn bracket(a: *Analyser, text: []const u8, expected: TypeIndex) error{OutOfMemory}!Value {
    var elements: std.ArrayList(value.Element) = .empty;
    defer elements.deinit(a.gpa);
    var reader = value.read(text);
    while (reader.next() catch return .nil) |e| try elements.append(a.gpa, e);

    const list = isList(&a.env, expected, 8);
    if (elements.items.len == 1 and !list) return element(a, elements.items[0]);
    // `[]` where a list goes: no items.
    if (elements.items.len == 1 and list and elements.items[0].kind == .empty) return .{ .elements = &.{} };
    const out = try a.env.arena.allocator().alloc(Value, elements.items.len);
    for (elements.items, out) |e, *v| v.* = element(a, e);
    return .{ .elements = out };
}

/// One element: a literal, a label by name, or a named value's value,
/// decoded when it was defined, with its own type.
fn element(a: *Analyser, e: value.Element) Value {
    return switch (e.kind) {
        .empty => .nil,
        .color => |c| .{ .color = c },
        .number => |n| .{ .number = n },
        .range => |r| .{ .range = r },
        .symbol => .{ .label = .{ .name = e.text, .inverted = e.inverted } },
        .name => if (a.env.values.get(e.text)) |v|
            (if (v.body == null) .{ .label = .{ .name = e.text, .inverted = e.inverted } } else v.decoded orelse .nil)
        else
            .{ .label = .{ .name = e.text, .inverted = e.inverted } },
        .type => .nil,
    };
}

/// `{ … }`: a record, its functions with no subject binding `owner` (null
/// in a bundle: where it is used).
pub fn record(a: *Analyser, node: Node.Index, owner: ?Env.Classes) error{OutOfMemory}!decoded.RecordIndex {
    var r: Building = .{};
    defer r.bindings.deinit(a.gpa);
    defer r.tokens.deinit(a.gpa);
    try items(a, node, owner, &r);
    const arena = a.env.arena.allocator();
    const index: decoded.RecordIndex = @fromBackingInt(@as(u32, @intCast(a.env.records.items.len)));
    try a.env.records.append(a.gpa, .{
        .bindings = try arena.dupe(decoded.Binding, r.bindings.items),
        .tokens = try arena.dupe(decoded.Token, r.tokens.items),
    });
    return index;
}

const Building = struct {
    bindings: std.ArrayList(decoded.Binding) = .empty,
    tokens: std.ArrayList(decoded.Token) = .empty,
};

fn items(a: *Analyser, node: Node.Index, owner: ?Env.Classes, r: *Building) error{OutOfMemory}!void {
    const cst = a.cst;
    var one: [1]Node.Index = undefined;
    for (vocabulary.itemsOf(cst, node, &one)) |item| switch (cst.tag(item)) {
        .statement => if (cst.tokenTag(cst.mainToken(item)) == .defn) {
            if (try token(a, item)) |t| try r.tokens.append(a.gpa, t);
        },
        .entry => {
            const parts = cst.children(item);
            const classes = if (cst.subject(item)) |subject| (classesOf(cst, subject) orelse continue) else owner;
            for (parts[@intFromBool(cst.subject(item) != null)..]) |part| switch (cst.tag(part)) {
                .attr => try binding(a, part, classes, r),
                .block => try items(a, part, classes, r),
                else => {},
            };
        },
        .block => try items(a, item, owner, r),
        else => {},
    };
}

fn binding(a: *Analyser, node: Node.Index, classes: ?Env.Classes, r: *Building) error{OutOfMemory}!void {
    const cst = a.cst;
    const name = cst.tokenText(cst.mainToken(node));
    const f = a.env.descriptor(name, a.case_kind) orelse return;
    const key: ?[]const u8 = if (cst.key(node)) |k| keyText(cst.tokenText(k)) else null;
    try r.bindings.append(a.gpa, .{ .classes = classes, .descriptor = name, .key = key, .value = try attr(a, node, f) });
}

/// `[ink] := [#dddddd]`: a label bound to a value of its type.
pub fn token(a: *Analyser, naming: Node.Index) error{OutOfMemory}!?decoded.Token {
    const cst = a.cst;
    const key, const body = cst.data(naming).nodes;
    if (cst.tag(key) != .leaf or cst.tokenTag(cst.mainToken(key)) != .val) return null;
    const label = keyText(cst.tokenText(cst.mainToken(key)));
    const v = a.env.values.get(label) orelse return null;
    if (v.body != null) return null;
    return .{ .label = label, .value = try of(a, body, v.type) };
}

/// The classes a theme's subject names, `&node` or a group of them; null
/// when it names anything else (reported by the checks).
fn classesOf(cst: *const Cst, node: Node.Index) ?Env.Classes {
    if (cst.tag(node) == .leaf) {
        const c = Env.class(cst.tokenText(cst.mainToken(node))) orelse return null;
        return .initOne(c);
    }
    var classes: Env.Classes = .empty;
    for (cst.children(node)) |child| classes.setUnion(classesOf(cst, child) orelse return null);
    return classes;
}

/// `[a]` without its brackets.
fn keyText(bracketed: []const u8) []const u8 {
    return bracketed[1 .. bracketed.len - 1];
}

/// `"…"` undone: `\x` is `x`. With `only`, only `\only` is undone, as in
/// maths, whose other backslashes are LaTeX's.
fn unescape(a: *Analyser, text: []const u8, only: ?u8) error{OutOfMemory}![]const u8 {
    if (std.mem.indexOfScalar(u8, text, '\\') == null) return text;
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        if (text[i] == '\\' and i + 1 < text.len and (only == null or text[i + 1] == only.?)) i += 1;
        try out.append(a.env.arena.allocator(), text[i]);
    }
    return out.items;
}

/// Whether `t` expects a list: a list, or a type holding one.
fn isList(env: *const Env, t: TypeIndex, depth: u32) bool {
    if (depth == 0) return false;
    return switch (env.get(t)) {
        .list => true,
        .twin => |inner| isList(env, inner, depth - 1),
        .@"union" => |ts| for (ts) |m| {
            if (isList(env, m, depth - 1)) break true;
        } else false,
        .declared => |id| for (env.declared.items[id].members.items) |m| {
            if (isList(env, m, depth - 1)) break true;
        } else false,
        else => false,
    };
}

test {
    _ = @import("decode.test.zig");
}
