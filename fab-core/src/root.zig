//! fab-core: source in, IR out. No I/O.

const std = @import("std");

pub const Token = @import("lex/Token.zig");
pub const Lexer = @import("lex/Lexer.zig");
pub const Cst = @import("parse/Cst.zig");
pub const Parser = @import("parse/Parser.zig");
pub const Ir = @import("analyse/Ir.zig");
pub const Analyser = @import("analyse/Analyser.zig");
/// What a bracket holds, element by element.
pub const value = @import("analyse/value.zig");
/// The environment: types, descriptors, named values and records.
pub const Env = @import("analyse/Env.zig");
/// Values as decoded once checked.
pub const decoded = @import("analyse/decoded.zig");
pub const Decimal = @import("analyse/Decimal.zig");
/// The layers as read: bindings, tokens, kinds.
pub const layers = @import("analyse/layers.zig");
pub const Diagnostic = @import("compile/Diagnostic.zig");
pub const Compilation = @import("compile/Compilation.zig");
pub const Lines = @import("compile/Lines.zig");
pub const json = @import("emit/json.zig");
pub const print = @import("print/print.zig");
/// For other packages' tests.
pub const testing = @import("compile/testing.zig");

/// The build's version (release.md §1–2): `0.1.0`, or
/// `0.1.0-dev.97+e3ee815[.dirty][.incomplete]`.
pub const version = @import("version.zig").string;
/// A tagged commit, built clean: it admits no unsupported construct.
pub const stable = @import("version.zig").stable;

test {
    std.testing.refAllDecls(@This());
}
