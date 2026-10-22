//! A union-find over the elements of a graph: edge ends and named atoms.
//!
//! A class of glued elements is a node. The root of a class is always its
//! oldest element, so the root is also the end that created the node (its
//! canonical reference) and tells which zone owns it.
//!
//! Each class carries annotations that form flat lattices: a kind, a name,
//! a sealed flag. Merging two classes joins their annotations. When two values
//! can't be joined, `unite` returns the conflict instead of merging, and
//! leaves both classes unchanged. Deciding what a conflict means, and
//! reporting it, is the caller's job: this file knows nothing of diagnostics.
//!
//! A hole (a placeholder for a part of the program that failed) joins with
//! anything without conflict, so nothing glued to a hole reports again.
//!
//! Every write is recorded in an undo log, so the structure can be rolled back
//! to any earlier snapshot. There is no path compression: roots are the oldest
//! elements, which keeps trees shallow, and it leaves `unite` and `edit` as
//! the only writes to undo.

const std = @import("std");
const Ir = @import("Ir.zig");
/// A token index, as in Cst. Kept local so this folder needs nothing outside it.
const TokenIndex = u32;

const UnionFind = @This();

arena: std.mem.Allocator,
parent: std.ArrayList(u32) = .empty,
classes: std.ArrayList(Class) = .empty,
/// Which edge end each element is; null for atoms (`#A`, `@`, holes,
/// level-2 nodes).
end_of: std.ArrayList(?Ir.End) = .empty,
zone_of: std.ArrayList(u32) = .empty,
log: std.ArrayList(Undo) = .empty,

/// A class's annotations. Valid at roots only.
pub const Class = struct {
    kind: ?Ir.Node.Kind = null,
    kind_token: TokenIndex = 0,
    name: ?[]const u8 = null,
    name_token: TokenIndex = 0,
    own: bool = false,
    sealed: bool = false,
    /// A placeholder for a part of the program that failed.
    hole: bool = false,
    size: u32 = 1,
    /// Level 2: the outer edge this class stands for.
    outer: ?u32 = null,

    pub fn named(c: Class) bool {
        return c.name != null or c.own;
    }
};

/// Two annotations that can't be joined.
pub const Conflict = struct {
    tag: Tag,
    /// The token that set the conflicting value, when there is one.
    related: ?TokenIndex = null,

    pub const Tag = enum {
        /// One class is a null node, which belongs to exactly one edge end.
        sealed_end,
        /// Both classes have the same kind: it would be declared twice.
        same_kind,
        /// The classes have different kinds.
        different_kinds,
        /// Both classes are named (`#A` or `@`).
        two_names,
        /// Level 2: the classes stand for different outer edges.
        two_outer_edges,
    };
};

/// A position to roll back to.
pub const Mark = struct {
    len: u32,
    log: u32,
};

const Undo = union(enum) {
    parent: struct { elem: u32, old: u32 },
    class: struct { root: u32, old: Class },
};

pub fn init(arena: std.mem.Allocator) UnionFind {
    return .{ .arena = arena };
}

pub fn add(uf: *UnionFind, zone: u32, end: ?Ir.End, initial: Class) error{OutOfMemory}!u32 {
    const elem: u32 = @intCast(uf.parent.items.len);
    try uf.parent.append(uf.arena, elem);
    try uf.classes.append(uf.arena, initial);
    try uf.end_of.append(uf.arena, end);
    try uf.zone_of.append(uf.arena, zone);
    return elem;
}

pub fn len(uf: *const UnionFind) usize {
    return uf.parent.items.len;
}

pub fn find(uf: *const UnionFind, x: u32) u32 {
    var i = x;
    while (uf.parent.items[i] != i) i = uf.parent.items[i];
    return i;
}

/// The annotations of the class containing `x`, for reading.
pub fn class(uf: *const UnionFind, x: u32) Class {
    return uf.classes.items[uf.find(x)];
}

/// The annotations of the class containing `x`, for writing. The current
/// values are logged first, so the change can be rolled back.
pub fn edit(uf: *UnionFind, x: u32) error{OutOfMemory}!*Class {
    const root = uf.find(x);
    try uf.log.append(uf.arena, .{ .class = .{ .root = root, .old = uf.classes.items[root] } });
    return &uf.classes.items[root];
}

/// Merges the classes of `x` and `y`, joining their annotations. The older
/// root stays root. On a conflict nothing changes and the conflict is
/// returned. A hole joins with anything.
pub fn unite(uf: *UnionFind, x: u32, y: u32) error{OutOfMemory}!?Conflict {
    var rx = uf.find(x);
    var ry = uf.find(y);
    if (rx == ry) return null;
    if (ry < rx) std.mem.swap(u32, &rx, &ry);
    const cx = uf.classes.items[rx];
    const cy = uf.classes.items[ry];

    if (!cx.hole and !cy.hole) {
        if (cx.sealed or cy.sealed) return .{ .tag = .sealed_end };
        if (cx.kind != null and cy.kind != null) {
            const tag: Conflict.Tag = if (cx.kind.? == cy.kind.?) .same_kind else .different_kinds;
            return .{ .tag = tag, .related = cy.kind_token };
        }
        if (cx.named() and cy.named()) return .{ .tag = .two_names, .related = cx.name_token };
        if (cx.outer != null and cy.outer != null and cx.outer.? != cy.outer.?) return .{ .tag = .two_outer_edges };
    }
    try uf.merge(rx, ry);
    return null;
}

/// Merges the classes of `x` and `y` whatever their annotations, keeping the
/// older class's value wherever both have one. Used to repair a conflict.
pub fn force(uf: *UnionFind, x: u32, y: u32) error{OutOfMemory}!void {
    var rx = uf.find(x);
    var ry = uf.find(y);
    if (rx == ry) return;
    if (ry < rx) std.mem.swap(u32, &rx, &ry);
    try uf.merge(rx, ry);
}

/// Joins root `ry` into the older root `rx`.
fn merge(uf: *UnionFind, rx: u32, ry: u32) error{OutOfMemory}!void {
    const cx = try uf.edit(rx);
    const cy = uf.classes.items[ry];
    if (cx.kind == null) {
        cx.kind = cy.kind;
        cx.kind_token = cy.kind_token;
    }
    if (!cx.named()) {
        cx.name = cy.name;
        cx.own = cy.own;
        cx.name_token = cy.name_token;
    }
    cx.outer = cx.outer orelse cy.outer;
    cx.sealed = cx.sealed or cy.sealed;
    cx.hole = cx.hole or cy.hole;
    cx.size += cy.size;

    try uf.log.append(uf.arena, .{ .parent = .{ .elem = ry, .old = uf.parent.items[ry] } });
    uf.parent.items[ry] = rx;
}

pub fn snapshot(uf: *const UnionFind) Mark {
    return .{ .len = @intCast(uf.parent.items.len), .log = @intCast(uf.log.items.len) };
}

/// Undoes every write since `mark`, newest first, and removes the elements
/// added since.
pub fn rollback(uf: *UnionFind, mark: Mark) void {
    var i = uf.log.items.len;
    while (i > mark.log) {
        i -= 1;
        switch (uf.log.items[i]) {
            .parent => |p| uf.parent.items[p.elem] = p.old,
            .class => |c| uf.classes.items[c.root] = c.old,
        }
    }
    uf.log.shrinkRetainingCapacity(mark.log);
    uf.parent.shrinkRetainingCapacity(mark.len);
    uf.classes.shrinkRetainingCapacity(mark.len);
    uf.end_of.shrinkRetainingCapacity(mark.len);
    uf.zone_of.shrinkRetainingCapacity(mark.len);
}
