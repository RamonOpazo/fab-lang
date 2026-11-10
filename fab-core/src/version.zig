//! The build's version (release.md §1–2), as every package shows it:
//! `0.1.0` for a stable build, `0.1.0-dev.97+e3ee815[.dirty][.incomplete]`
//! for a dev one. `build.zig` computes all but `.incomplete`, which only the
//! code knows: whether some diagnostic tag is still unsupported.

const build_options = @import("build_options");
const Error = @import("analyse/Error.zig");

pub const string: []const u8 = build_options.version ++ if (Error.incomplete) ".incomplete" else "";

/// A tagged commit, built clean.
pub const stable: bool = build_options.stable;

test {
    _ = @import("version.test.zig");
}
