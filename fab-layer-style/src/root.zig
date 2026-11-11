//! fab-layer-style: the style layer's runtime (statements.md §26). From
//! fab-core's analysis to the Sheet, every element's style resolved by the
//! cascade. No I/O. A renderer calls it before drawing.

const std = @import("std");
const fab = @import("fab_core");

pub const Sheet = @import("Sheet.zig");
pub const Styler = @import("Styler.zig");

/// How a diagram is drawn for its diagnostics (spec, Errors): a border in the
/// colour of the most severe one, and a label while any is unsupported
/// (statements.md §15.3).
pub const ZoneMark = Styler.ZoneMark;

/// The Sheet of `c`'s program, or null when its IR is withheld. The caller
/// owns it; it borrows `c`, which must outlive it.
pub fn of(gpa: std.mem.Allocator, c: *fab.Compilation) error{OutOfMemory}!?Sheet {
    const graph = try c.ir() orelse return null;
    const result = try c.analysis();
    return try Styler.style(gpa, graph, .{
        .env = &result.env,
        .bindings = result.bindings,
        .tokens = result.tokens,
        .kinds = result.kinds,
    }, try c.marks());
}

/// The mark of a zone, as the style layer draws it, whether or not the IR
/// is withheld.
pub fn zoneMark(c: *fab.Compilation, zone: fab.Ir.ZoneIndex) error{OutOfMemory}!ZoneMark {
    return Styler.zoneMark(&(try c.analysis()).ir, try c.marks(), zone);
}

test {
    std.testing.refAllDecls(@This());
    _ = @import("conformance.test.zig");
}
