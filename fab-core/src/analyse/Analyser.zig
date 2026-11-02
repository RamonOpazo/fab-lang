//! Turns a concrete syntax tree into the IR, and reports what is wrong with it.
//!
//! A skeleton. The analyser is rewritten for the 1 November spec in plan step 5
//! (CLAUDE.md), one rule at a time; until then it keeps its interface and
//! produces an empty IR with no errors.
//!
//! The analyser always produces an IR, valid program or not, together with the
//! errors it found. Deciding whether an IR with errors is acceptable belongs to
//! the compiler, not to this file.

const std = @import("std");
const Cst = @import("../parse/Cst.zig");
const Ir = @import("Ir.zig");

const TokenIndex = Cst.TokenIndex;

pub const Error = struct {
    tag: Tag,
    /// Where the error is reported.
    token: TokenIndex,
    /// Where the conflicting thing was first declared, when that helps.
    related: ?TokenIndex = null,
    /// What to mark in the graph, if anything.
    subject: ?Subject = null,

    /// Each rule of step 5 adds its tags. Non-exhaustive while there are
    /// none, so `Error` stays a type with values.
    pub const Tag = enum(u8) { _ };
};

/// An element of the graph under construction, before it becomes part of the
/// IR: a union-find element (whose class is a node), an edge, a cell or a zone.
pub const Subject = union(enum) {
    elem: u32,
    edge: u32,
    cell: u32,
    zone: u32,
};

/// Always an IR, and the errors found while building it. Errors with a
/// subject appear in the IR's issues table.
pub const Result = struct {
    ir: Ir,
    errors: []const Error,

    pub fn deinit(result: *Result, gpa: std.mem.Allocator) void {
        result.ir.deinit(gpa);
        gpa.free(result.errors);
        result.* = undefined;
    }
};

/// Analyses a program. A program with syntax errors is analysed too.
pub fn analyse(gpa: std.mem.Allocator, cst: *const Cst) error{OutOfMemory}!Result {
    _ = cst;
    var b: Ir.Builder = .init(gpa);
    errdefer b.deinit();
    const ir = try b.finish();
    return .{ .ir = ir, .errors = try gpa.alloc(Error, 0) };
}

test {
    _ = @import("union_find.test.zig");
}
