//! The product of the format pass: a resolved Style for every node, edge and
//! zone of an IR, the way a style sheet maps elements to styles.
//!
//! Made by Formatter.zig. A Sheet borrows the IR, which must outlive it, and
//! owns its tables and the labels that aren't in the IR's strings.

const std = @import("std");
const Ir = @import("../analyse/Ir.zig");
const Style = @import("Style.zig");

const Sheet = @This();

ir: *const Ir,
nodes: []const Style,
edges: []const Style,
zones: []const Style,
/// Labels that aren't in the IR's strings: the canonical ends, `f+` and `+f`.
labels: []const u8,
gpa: std.mem.Allocator,

pub fn deinit(s: *Sheet) void {
    s.gpa.free(s.nodes);
    s.gpa.free(s.edges);
    s.gpa.free(s.zones);
    s.gpa.free(s.labels);
    s.* = undefined;
}

pub fn node(s: *const Sheet, n: Ir.NodeIndex) Style {
    return s.nodes[@backingInt(n)];
}

pub fn edge(s: *const Sheet, e: Ir.EdgeIndex) Style {
    return s.edges[@backingInt(e)];
}

pub fn zone(s: *const Sheet, z: Ir.ZoneIndex) Style {
    return s.zones[@backingInt(z)];
}

/// How a zone appears: flat, a cluster, one node or a table.
pub fn drawnAs(s: *const Sheet, z: Ir.ZoneIndex) Style.As {
    return s.zones[@backingInt(z)].as;
}

/// Whether a zone draws a border or background around its contents. A
/// cluster has neither unless the program gives it a stroke or a fill.
pub fn isFramed(s: *const Sheet, z: Ir.ZoneIndex) bool {
    const style = s.zones[@backingInt(z)];
    return style.stroke != null or style.fill != null;
}
