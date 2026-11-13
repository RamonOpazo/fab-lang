//! fab-layer-place: the place layer's runtime (statements.md §26, §29;
//! layout.md). From fab-core's analysis to the Place: each diagram's seed,
//! metric and flow, each edge's span and collapse, read against the lattice.
//! No I/O. Its consumers call it.

const std = @import("std");
const fab = @import("fab_core");

pub const Place = @import("Place.zig");
pub const grid = @import("grid.zig");
pub const resolve = @import("resolve.zig");
/// The layer's own diagnostics, in fab-core's shape.
pub const messages = @import("messages.zig");

/// The Place of `c`'s program, or null when its IR is withheld. The caller
/// owns it; it borrows `c`, which must outlive it.
pub fn of(gpa: std.mem.Allocator, c: *fab.Compilation) error{OutOfMemory}!?Place {
    const graph = try c.ir() orelse return null;
    const result = try c.analysis();
    return try resolve.resolve(gpa, graph, .{
        .env = &result.env,
        .bindings = result.bindings,
        .kinds = result.kinds,
        .cst = try c.cst(),
    });
}

test {
    std.testing.refAllDecls(@This());
    _ = @import("grid.test.zig");
    _ = @import("ranks.zig");
    _ = @import("conformance.test.zig");
}
