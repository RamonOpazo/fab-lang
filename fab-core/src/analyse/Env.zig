//! The environment of names (statements.md §21): types, the values and
//! labels written in brackets, and functions with their signatures.
//!
//! Types are interned: every type is an index into one table, structural
//! types included, so `:List.(:Color)` written twice is one index, and type
//! equality is index equality. An alias is a second name for an index.
//!
//! The environment stores where a name was defined, not what it evaluates
//! to: a value is read again from its node when it is needed. Names are
//! slices of the source, which outlives it.
//!
//! A program's environment starts as the prelude's (`adopt`). Its entries
//! keep their tokens and nodes, which are the prelude's, so each is marked:
//! an error can't point into another source.

const std = @import("std");
const Cst = @import("../parse/Cst.zig");

const Env = @This();
const TokenIndex = Cst.TokenIndex;
const Node = Cst.Node;

/// Holds the slices of structural types.
arena: std.heap.ArenaAllocator,
types: std.ArrayList(Type) = .empty,
/// The first name of each type, for messages; null for a structural type
/// never named.
type_names: std.ArrayList(?[]const u8) = .empty,
interned: std.HashMapUnmanaged(Type, TypeIndex, TypeContext, std.hash_map.default_max_load_percentage) = .empty,
/// Type names, `:` included: `:Color`, `:Arrow`.
type_table: std.StringHashMapUnmanaged(Named) = .empty,
/// Bracket names, brackets excluded: `red`, `circle`, `>`.
values: std.StringHashMapUnmanaged(Value) = .empty,
/// Function names, `:` included: `:fill`.
functions: std.StringHashMapUnmanaged(Function) = .empty,
/// The next label type's identity.
label_types: u32 = 0,

pub const TypeIndex = enum(u32) {
    text,
    math,
    color,
    number,
    range,
    flag,
    record,
    /// An empty slot, `[/solid/>]`'s tail: it fits any slot.
    nothing,
    /// Whatever failed to type. It fits anywhere, so one error says it.
    unknown,
    _,
};

pub const Type = union(enum) {
    text,
    math,
    color,
    number,
    range,
    flag,
    record,
    nothing,
    unknown,
    /// A set of labels, `:Shape :: [circle], …`; each declaration of a new
    /// label type gets its own identity.
    labels: u32,
    tuple: []const TypeIndex,
    list: TypeIndex,
    @"union": []const TypeIndex,
};

/// The parametrised constructors, which are no type until applied.
pub const Constructor = enum { tuple, list, @"union" };

pub const Named = union(enum) {
    type: struct { index: TypeIndex, token: ?TokenIndex, prelude: bool = false },
    constructor: Constructor,
};

pub const Value = struct {
    type: TypeIndex,
    /// Where it was defined; null for a built-in.
    token: ?TokenIndex,
    /// The value it is bound to; null for a label, which has no definition.
    body: ?Node.Index,
    /// Defined in the prelude: `token` and `body` are the prelude's.
    prelude: bool = false,
};

pub const Function = struct {
    /// The classes it applies to.
    classes: Classes,
    type: TypeIndex,
    token: TokenIndex,
    prelude: bool = false,
};

/// The built-in classes (spec, Subjects and classes).
pub const Class = enum { node, plain, choice, parallel, start, end, hole, canonical, edge, cell, zone };
pub const Classes = std.EnumSet(Class);

pub fn init(gpa: std.mem.Allocator) error{OutOfMemory}!Env {
    var env: Env = .{ .arena = .init(gpa) };
    errdefer env.deinit(gpa);
    // The scalars first, in TypeIndex's order, so their indices are fixed.
    for ([_]Type{ .text, .math, .color, .number, .range, .flag, .record, .nothing, .unknown }) |t| _ = try env.intern(gpa, t);
    const builtins = [_]struct { []const u8, TypeIndex }{
        .{ ":Text", .text },   .{ ":Math", .math }, .{ ":Color", .color },   .{ ":Number", .number },
        .{ ":Range", .range }, .{ ":Flag", .flag }, .{ ":Record", .record },
    };
    for (builtins) |b| {
        try env.type_table.put(gpa, b[0], .{ .type = .{ .index = b[1], .token = null } });
        env.type_names.items[@backingInt(b[1])] = b[0];
    }
    try env.type_table.put(gpa, ":Tuple", .{ .constructor = .tuple });
    try env.type_table.put(gpa, ":List", .{ .constructor = .list });
    try env.type_table.put(gpa, ":Union", .{ .constructor = .@"union" });
    return env;
}

pub fn deinit(env: *Env, gpa: std.mem.Allocator) void {
    env.types.deinit(gpa);
    env.type_names.deinit(gpa);
    env.interned.deinit(gpa);
    env.type_table.deinit(gpa);
    env.values.deinit(gpa);
    env.functions.deinit(gpa);
    env.arena.deinit();
    env.* = undefined;
}

/// Marks every entry as the prelude's, before a program is analysed in it.
pub fn adopt(env: *Env) void {
    var types = env.type_table.valueIterator();
    while (types.next()) |named| switch (named.*) {
        .type => |*t| t.prelude = true,
        .constructor => {},
    };
    var values = env.values.valueIterator();
    while (values.next()) |v| v.prelude = true;
    var functions = env.functions.valueIterator();
    while (functions.next()) |f| f.prelude = true;
}

pub fn get(env: *const Env, index: TypeIndex) Type {
    return env.types.items[@backingInt(index)];
}

/// The index of `t`, made if new. Slices in `t` are copied.
pub fn intern(env: *Env, gpa: std.mem.Allocator, t: Type) error{OutOfMemory}!TypeIndex {
    if (env.interned.get(t)) |index| return index;
    const owned: Type = switch (t) {
        .tuple => |ts| .{ .tuple = try env.arena.allocator().dupe(TypeIndex, ts) },
        .@"union" => |ts| .{ .@"union" = try env.arena.allocator().dupe(TypeIndex, ts) },
        else => t,
    };
    const index: TypeIndex = @fromBackingInt(@intCast(env.types.items.len));
    try env.types.append(gpa, owned);
    errdefer _ = env.types.pop();
    try env.type_names.append(gpa, null);
    errdefer _ = env.type_names.pop();
    try env.interned.put(gpa, owned, index);
    return index;
}

/// A new label type, with its own identity.
pub fn newLabels(env: *Env, gpa: std.mem.Allocator) error{OutOfMemory}!TypeIndex {
    defer env.label_types += 1;
    return env.intern(gpa, .{ .labels = env.label_types });
}

/// Gives a type a name for messages, unless it has one.
pub fn name(env: *Env, index: TypeIndex, text: []const u8) void {
    const slot = &env.type_names.items[@backingInt(index)];
    if (slot.* == null) slot.* = text;
}

/// Whether a value of type `actual` can stand where `expected` is.
pub fn fits(env: *const Env, actual: TypeIndex, expected: TypeIndex) bool {
    if (actual == expected or actual == .unknown or expected == .unknown or actual == .nothing) return true;
    return switch (env.get(expected)) {
        .@"union" => |members| for (members) |m| {
            if (env.fits(actual, m)) break true;
        } else false,
        .list => |element| switch (env.get(actual)) {
            // A tuple of elements that each fit, and so `[]`, a list of nothing.
            .tuple => |ts| for (ts) |t| {
                if (!env.fits(t, element)) break false;
            } else true,
            .list => |a| env.fits(a, element),
            // A single value is a list of one.
            else => env.fits(actual, element),
        },
        .tuple => |slots| switch (env.get(actual)) {
            .tuple => |ts| ts.len == slots.len and for (ts, slots) |t, s| {
                if (!env.fits(t, s)) break false;
            } else true,
            else => false,
        },
        else => false,
    };
}

/// Whether labels can be added to a type: a single value's, not a
/// structure's.
pub fn takesLabels(env: *const Env, index: TypeIndex) bool {
    return switch (env.get(index)) {
        .text, .math, .color, .number, .range, .labels => true,
        else => false,
    };
}

pub fn class(text: []const u8) ?Class {
    return std.meta.stringToEnum(Class, text[1..]);
}

const TypeContext = struct {
    pub fn hash(_: TypeContext, t: Type) u64 {
        var h: std.hash.Wyhash = .init(0);
        h.update(@tagName(t));
        switch (t) {
            .labels => |id| h.update(std.mem.asBytes(&id)),
            .list => |e| h.update(std.mem.asBytes(&e)),
            .tuple, .@"union" => |ts| h.update(std.mem.sliceAsBytes(ts)),
            else => {},
        }
        return h.final();
    }

    pub fn eql(_: TypeContext, a: Type, b: Type) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        return switch (a) {
            .labels => |id| id == b.labels,
            .list => |e| e == b.list,
            .tuple => |ts| std.mem.eql(TypeIndex, ts, b.tuple),
            .@"union" => |ts| std.mem.eql(TypeIndex, ts, b.@"union"),
            else => true,
        };
    }
};
