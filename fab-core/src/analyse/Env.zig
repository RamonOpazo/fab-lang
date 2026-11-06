//! The environment of names (statements.md §21): types, the values and
//! labels written in brackets, and functions with their signatures.
//!
//! Types are interned: every type is an index into one table, structural
//! types included, so `[:Color]` written twice is one index, and type
//! equality is index equality. A declared type (`:Angle :: :Number!`,
//! `:Shape :: [circle]`) has an identity of its own (statements.md §22.8):
//! literals fit it through its members, a value typed by it fits only it and
//! the types that include it.
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
/// The declared types, by identity: what each holds besides its labels.
declared: std.ArrayList(Declared) = .empty,

pub const TypeIndex = enum(u32) {
    text,
    math,
    color,
    number,
    range,
    flag,
    record,
    /// An empty slot, `[/solid/>]`'s tail: it fits any slot (until 9b1).
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
    /// `:T :: …`, with an identity of its own: its labels, and the members
    /// in `declared`.
    declared: u32,
    /// `[:A/:B]`.
    tuple: []const TypeIndex,
    /// `[:A]`.
    list: TypeIndex,
    /// `:A, :B` in a declaration, `(:A, :B)` inside an expression.
    @"union": []const TypeIndex,
    /// `T!`: T's values and their twins. Never of a twin or a union, which
    /// `twin` normalises.
    twin: TypeIndex,
};

/// What a declared type holds besides its labels, added to by each
/// declaration of it.
pub const Declared = struct {
    members: std.ArrayList(TypeIndex) = .empty,
};

pub const Named = struct { index: TypeIndex, token: ?TokenIndex, prelude: bool = false };

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
    /// The classes it applies to, with the classes inside them (`within`).
    classes: Classes,
    type: TypeIndex,
    token: TokenIndex,
    /// A bundle, `:terminal := { … }`: a flag that is never inverted.
    bundle: bool = false,
    prelude: bool = false,
};

/// The built-in classes (spec, Subjects and classes).
pub const Class = enum { node, plain, choice, parallel, start, end, hole, canonical, edge, cell, zone };
pub const Classes = std.EnumSet(Class);

/// The classes inside `&node`.
const node_kinds: Classes = .initMany(&.{ .plain, .choice, .parallel, .start, .end, .hole, .canonical });

/// `classes` with the classes inside them: `&node` brings the node kinds.
pub fn within(classes: Classes) Classes {
    return if (classes.contains(.node)) classes.unionWith(node_kinds) else classes;
}

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
        try env.type_table.put(gpa, b[0], .{ .index = b[1], .token = null });
        env.type_names.items[@backingInt(b[1])] = b[0];
    }
    return env;
}

pub fn deinit(env: *Env, gpa: std.mem.Allocator) void {
    env.types.deinit(gpa);
    for (env.declared.items) |*d| d.members.deinit(gpa);
    env.declared.deinit(gpa);
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
    while (types.next()) |named| named.prelude = true;
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

/// A new declared type, with its own identity.
pub fn newDeclared(env: *Env, gpa: std.mem.Allocator) error{OutOfMemory}!TypeIndex {
    const id: u32 = @intCast(env.declared.items.len);
    try env.declared.append(gpa, .{});
    errdefer _ = env.declared.pop();
    return env.intern(gpa, .{ .declared = id });
}

/// `T!`. A twin of a twin is the twin; on a union `!` distributes; a flag
/// has twins by nature. Null for a type with no twins to give: a tuple, a
/// list, a record.
pub fn twin(env: *Env, gpa: std.mem.Allocator, t: TypeIndex) error{OutOfMemory}!?TypeIndex {
    switch (env.get(t)) {
        .twin, .flag, .unknown => return t,
        .tuple, .list, .record, .nothing => return null,
        .@"union" => |members| {
            var twins: std.ArrayList(TypeIndex) = .empty;
            defer twins.deinit(gpa);
            for (members) |m| try twins.append(gpa, try env.twin(gpa, m) orelse return null);
            return try env.intern(gpa, .{ .@"union" = twins.items });
        },
        else => return try env.intern(gpa, .{ .twin = t }),
    }
}

/// `t` with every twin taken back: what a value would be without its `!`s.
pub fn untwinned(env: *Env, gpa: std.mem.Allocator, t: TypeIndex) error{OutOfMemory}!TypeIndex {
    switch (env.get(t)) {
        .twin => |inner| return inner,
        .tuple => |slots| {
            var plain: std.ArrayList(TypeIndex) = .empty;
            defer plain.deinit(gpa);
            for (slots) |slot| try plain.append(gpa, try env.untwinned(gpa, slot));
            return env.intern(gpa, .{ .tuple = plain.items });
        },
        else => return t,
    }
}

/// Whether `inner` is `outer`, or among the members `outer` holds, at any
/// depth: what would make a declaration of `outer` with `inner` cyclic.
pub fn includes(env: *const Env, outer: TypeIndex, inner: TypeIndex) bool {
    if (outer == inner) return true;
    return switch (env.get(outer)) {
        .declared => |id| for (env.declared.items[id].members.items) |m| {
            if (env.includes(m, inner)) break true;
        } else false,
        .@"union", .tuple => |ts| for (ts) |m| {
            if (env.includes(m, inner)) break true;
        } else false,
        .list, .twin => |m| env.includes(m, inner),
        else => false,
    };
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
        // A declared type holds its members' values; a value typed by
        // another declared type is never unwrapped, so units stay apart.
        .declared => |id| for (env.declared.items[id].members.items) |m| {
            if (env.fits(actual, m)) break true;
        } else false,
        // An unmarked value is the first of its pair.
        .twin => |t| env.fits(actual, t) or switch (env.get(actual)) {
            .twin => |a| env.fits(a, t),
            else => false,
        },
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
        .text, .math, .color, .number, .range, .declared => true,
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
            .declared => |id| h.update(std.mem.asBytes(&id)),
            .list, .twin => |e| h.update(std.mem.asBytes(&e)),
            .tuple, .@"union" => |ts| h.update(std.mem.sliceAsBytes(ts)),
            else => {},
        }
        return h.final();
    }

    pub fn eql(_: TypeContext, a: Type, b: Type) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        return switch (a) {
            .declared => |id| id == b.declared,
            .list => |e| e == b.list,
            .twin => |e| e == b.twin,
            .tuple => |ts| std.mem.eql(TypeIndex, ts, b.tuple),
            .@"union" => |ts| std.mem.eql(TypeIndex, ts, b.@"union"),
            else => true,
        };
    }
};
