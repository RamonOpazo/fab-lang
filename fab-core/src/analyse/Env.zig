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
const decoded = @import("decoded.zig");

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
/// Function names, `:` included: `:fill`. A descriptor a case declares
/// (statements.md §24.3) is here by its first kind; the same name in other
/// kinds' cases follows it in `cased`, through `next`.
functions: std.StringHashMapUnmanaged(Function) = .empty,
cased: std.ArrayList(Function) = .empty,
/// The declared types, by identity: what each holds besides its labels.
declared: std.ArrayList(Declared) = .empty,
/// Named records and bundles' bodies, decoded (plan step 9d2): what
/// `decoded.Value.record` and `Function.body` index.
records: std.ArrayList(decoded.Record) = .empty,

pub const TypeIndex = enum(u32) {
    text,
    math,
    color,
    number,
    range,
    flag,
    /// A record, `{ … }`. It has no type of its own: it fits every record
    /// type, and its structure is checked where one is expected.
    record,
    /// Nil, nothing written: `[]`, `[/solid/>]`'s tail. It fits only where
    /// a type admits it, and every list, as its "no elements".
    nil,
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
    nil,
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
    /// Values or descriptors, never both (statements.md §22.9); open until
    /// the first item says.
    holds: enum { open, values, descriptors } = .open,
};

pub const Named = struct { index: TypeIndex, token: ?TokenIndex, prelude: bool = false };

pub const Value = struct {
    type: TypeIndex,
    /// Where it was defined; null for a built-in.
    token: ?TokenIndex,
    /// The value it is bound to; null for a label, which has no definition.
    body: ?Node.Index,
    /// A record's structure, which has no type (statements.md §22.9): its
    /// descriptors, one per record type, the first of each. For a bracket of
    /// named records, theirs.
    contents: []Content = &.{},
    /// Defined in the prelude: `token` and `body` are the prelude's.
    prelude: bool = false,
    /// The value it names, decoded once it is checked; null for a label.
    decoded: ?decoded.Value = null,
};

pub const Function = struct {
    /// The classes it applies to, with the classes inside them (`within`).
    classes: Classes,
    type: TypeIndex,
    token: TokenIndex,
    /// The record type it is declared in, `:Style :: { … }`; null for a
    /// descriptor declared at the top level, `&zone :style :: :Style`, and
    /// for a bundle, which has none (statements.md §22.9).
    record: ?TypeIndex = null,
    /// A table, `&zone :axiom.[] :: …`: it takes a key, then its value.
    table: bool = false,
    /// A bundle, `:terminal := { … }`: a flag that is never inverted.
    bundle: bool = false,
    /// A bundle's descriptors, one per record type, the first of each:
    /// what it is checked by where it is used.
    contents: []Content = &.{},
    prelude: bool = false,
    /// A bundle's body, decoded: what it binds where it is used.
    body: ?decoded.RecordIndex = null,
    /// The kind whose case declares it, `[flow]` as `flow`; null for every
    /// kind (statements.md §24.3).
    kind: ?[]const u8 = null,
    /// The same name declared in another kind's case, in `cased`.
    next: ?u32 = null,
};

/// A descriptor in a bundle or a record, standing for the record type it
/// belongs to (null: none, a top-level descriptor).
pub const Content = struct {
    record: ?TypeIndex,
    token: TokenIndex,
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
    for ([_]Type{ .text, .math, .color, .number, .range, .flag, .record, .nil, .unknown }) |t| _ = try env.intern(gpa, t);
    const builtins = [_]struct { []const u8, TypeIndex }{
        .{ ":Text", .text },   .{ ":Math", .math }, .{ ":Color", .color }, .{ ":Number", .number },
        .{ ":Range", .range }, .{ ":Flag", .flag }, .{ ":Nil", .nil },
    };
    for (builtins) |b| {
        try env.type_table.put(gpa, b[0], .{ .index = b[1], .token = null });
        env.type_names.items[@backingInt(b[1])] = b[0];
    }
    env.type_names.items[@backingInt(TypeIndex.record)] = "{}";
    return env;
}

pub fn deinit(env: *Env, gpa: std.mem.Allocator) void {
    env.types.deinit(gpa);
    for (env.declared.items) |*d| d.members.deinit(gpa);
    env.declared.deinit(gpa);
    env.records.deinit(gpa);
    env.type_names.deinit(gpa);
    env.interned.deinit(gpa);
    env.type_table.deinit(gpa);
    env.values.deinit(gpa);
    env.functions.deinit(gpa);
    env.cased.deinit(gpa);
    env.arena.deinit();
    env.* = undefined;
}

/// Marks every entry as the prelude's, before a program is analysed in it.
pub fn adopt(env: *Env) void {
    var types = env.type_table.valueIterator();
    while (types.next()) |named| named.prelude = true;
    var values = env.values.valueIterator();
    while (values.next()) |v| {
        v.prelude = true;
        for (v.contents) |*c| c.prelude = true;
    }
    var functions = env.functions.valueIterator();
    while (functions.next()) |f| {
        f.prelude = true;
        for (f.contents) |*c| c.prelude = true;
    }
    for (env.cased.items) |*f| f.prelude = true;
}

/// The descriptor `descriptor_name` in a diagram of `kind` (null: no kind, or none
/// known): declared for every kind, or in that kind's case.
pub fn descriptor(env: *const Env, descriptor_name: []const u8, kind: ?[]const u8) ?Function {
    var f = env.functions.get(descriptor_name) orelse return null;
    while (true) {
        if (f.kind == null) return f;
        if (kind) |k| if (std.mem.eql(u8, f.kind.?, k)) return f;
        f = env.cased.items[f.next orelse return null];
    }
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
/// list, a record, nil.
pub fn twin(env: *Env, gpa: std.mem.Allocator, t: TypeIndex) error{OutOfMemory}!?TypeIndex {
    switch (env.get(t)) {
        .twin, .flag, .unknown => return t,
        .tuple, .list, .record, .nil => return null,
        .declared => if (env.isRecord(t)) return null else return try env.intern(gpa, .{ .twin = t }),
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

/// Whether `t` is a record type: one declared by its descriptors.
pub fn isRecord(env: *const Env, t: TypeIndex) bool {
    return switch (env.get(t)) {
        .declared => |id| env.declared.items[id].holds == .descriptors,
        else => false,
    };
}

/// Gives a type a name for messages, unless it has one.
pub fn name(env: *Env, index: TypeIndex, text: []const u8) void {
    const slot = &env.type_names.items[@backingInt(index)];
    if (slot.* == null) slot.* = text;
}

/// Writes a type as fAB spells it, in its canonical form: its name, `:T!`,
/// `[:A/:B]`, `[:A]`, and a union always grouped, `(:A, :B)`, which reads
/// the same inside an expression and after `::`. A type nothing names, as
/// an unknown one, is `?`.
pub fn writeType(env: *const Env, index: TypeIndex, w: *std.Io.Writer) std.Io.Writer.Error!void {
    if (env.type_names.items[@backingInt(index)]) |n| return w.writeAll(n);
    switch (env.get(index)) {
        .twin => |t| {
            try env.writeType(t, w);
            try w.writeByte('!');
        },
        .list => |t| {
            try w.writeByte('[');
            try env.writeType(t, w);
            try w.writeByte(']');
        },
        .tuple => |ts| {
            try w.writeByte('[');
            for (ts, 0..) |t, i| {
                if (i > 0) try w.writeByte('/');
                try env.writeType(t, w);
            }
            try w.writeByte(']');
        },
        .@"union" => |ts| {
            try w.writeByte('(');
            for (ts, 0..) |t, i| {
                if (i > 0) try w.writeAll(", ");
                try env.writeType(t, w);
            }
            try w.writeByte(')');
        },
        else => try w.writeByte('?'),
    }
}

/// Whether a value of type `actual` can stand where `expected` is.
pub fn fits(env: *const Env, actual: TypeIndex, expected: TypeIndex) bool {
    if (actual == expected or actual == .unknown or expected == .unknown) return true;
    // A record fits by its structure, checked where it is used.
    if (actual == .record and env.isRecord(expected)) return true;
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
        .list => |element| actual == .nil or switch (env.get(actual)) {
            // Nil, before the switch, is no elements; a tuple, elements that
            // each fit.
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
/// structure's, nor a record type's.
pub fn takesLabels(env: *const Env, index: TypeIndex) bool {
    return switch (env.get(index)) {
        .text, .math, .color, .number, .range => true,
        .declared => |id| env.declared.items[id].holds != .descriptors,
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
