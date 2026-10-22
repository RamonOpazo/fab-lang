//! Something a backend could not express exactly.
//!
//! Notes are not diagnostics. A diagnostic says the program is wrong; a note
//! says the chosen engine draws a valid program less than fully, such as DOT
//! leaving out cells that the native renderer would draw. Notes never change
//! a program's status or a command's exit code. Hosts print them with the
//! same reporter as diagnostics, so they look alike.

const std = @import("std");
const fab = @import("fab_core");

const Note = @This();

tag: Tag,
/// The element concerned, if any.
subject: ?fab.Ir.Subject = null,

pub const Tag = enum {
    /// DOT has no edges between edges.
    cell_not_drawn,
    /// DOT has no wavy lines; drawn solid.
    wavy_line_drawn_solid,
    /// No DOT shape matches exactly; the nearest one is used.
    shape_approximated,
    /// `:as node` and `:as table` arrive with zone contraction; drawn as a
    /// cluster meanwhile.
    zone_drawn_as_cluster,
};

/// One line, for the terminal or a tooltip.
pub fn message(n: Note) []const u8 {
    return switch (n.tag) {
        .cell_not_drawn => "cells are not drawn by the graphviz engine",
        .wavy_line_drawn_solid => "graphviz has no wavy lines; drawn solid",
        .shape_approximated => "graphviz has no exact match for this shape; the nearest is used",
        .zone_drawn_as_cluster => "this zone's `:as` is not supported yet; drawn as a cluster",
    };
}

/// The notes a backend produces while writing.
pub const List = struct {
    gpa: std.mem.Allocator,
    items: std.ArrayList(Note) = .empty,

    pub fn init(gpa: std.mem.Allocator) List {
        return .{ .gpa = gpa };
    }

    pub fn deinit(l: *List) void {
        l.items.deinit(l.gpa);
    }

    pub fn add(l: *List, note: Note) error{OutOfMemory}!void {
        try l.items.append(l.gpa, note);
    }
};
