//! fab-cli's pure part, imported by main.zig as the module `fab_cli`.
//!
//! Nothing here does I/O: it reads arguments and source text, and writes to
//! the writers it is given. Reading files, writing them and watching them is
//! main.zig's job. This is the same split as fab-core's: root.zig is what is
//! pure and tested, main.zig is the only part touching the outside world.
//!
//!   command/   what to do: parse the command line, run a command
//!   output/    how results look: diagnostics for the terminal

const std = @import("std");

pub const Args = @import("command/Args.zig");
pub const run = @import("command/run.zig");
pub const report = @import("output/report.zig");

test {
    std.testing.refAllDecls(@This());
}
