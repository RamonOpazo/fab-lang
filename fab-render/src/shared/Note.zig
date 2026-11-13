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
/// The descriptor or label concerned, for the tags that name one: `:bend`,
/// `star`. Borrows the Sheet.
name: []const u8 = "",

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
    /// A descriptor the author bound that this engine doesn't draw: one
    /// note per descriptor per diagram.
    descriptor_not_drawn,
    /// A label this engine has no meaning for (`:shape [star]`, an unbound
    /// token); drawn with a fallback.
    label_not_drawn,
    /// An arrow's tail or head other than `>`: graphviz draws the line only,
    /// for now.
    arrow_ends_not_drawn,
    /// Graphviz draws one flow for the whole graph, along an axis: a
    /// diagram whose flow is another, or between axes, is drawn in the
    /// graph's.
    flow_not_drawn,
};

/// One line, for the terminal or a tooltip.
pub fn write(n: Note, w: *std.Io.Writer) std.Io.Writer.Error!void {
    switch (n.tag) {
        .cell_not_drawn => try w.writeAll("cells are not drawn by the graphviz engine"),
        .wavy_line_drawn_solid => try w.writeAll("graphviz has no wavy lines; drawn solid"),
        .shape_approximated => try w.writeAll("graphviz has no exact match for this shape; the nearest is used"),
        .zone_drawn_as_cluster => try w.writeAll("this zone's `:as` is not supported yet; drawn as a cluster"),
        .descriptor_not_drawn => try w.print("graphviz does not draw `{s}` yet", .{n.name}),
        .label_not_drawn => try w.print("graphviz has no meaning for `[{s}]`; drawn with a fallback", .{n.name}),
        .arrow_ends_not_drawn => try w.writeAll("graphviz draws an arrow's line, and its head as `>`, for now"),
        .flow_not_drawn => try w.writeAll("graphviz draws one flow for the whole graph, along an axis; this diagram is drawn in the graph's"),
    }
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
