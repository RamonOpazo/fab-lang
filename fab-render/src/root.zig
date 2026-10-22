//! fab-render: pure functions from a Sheet (the styled IR) to bytes. No I/O.
//!
//! Each backend realizes the looks the Sheet has already resolved; none of
//! them decides a look. Starting processes (Graphviz, LaTeX) belongs to the
//! hosts, fab-cli and fab-wasm, never to this package.
//!
//!   2dot/      Sheet → DOT; Graphviz lays it out
//!   Note.zig   what a backend couldn't express exactly
//!
//! Later: 2tikz/ (plain TikZ, with coordinates), layout/ (shared by native
//! and 2tikz, given a label-measuring function), native/ (layout → SVG).

const std = @import("std");

pub const Note = @import("shared/Note.zig");
pub const to_dot = @import("2dot/root.zig");

test {
    std.testing.refAllDecls(@This());
}
