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
pub const Sheet = @import("style/Sheet.zig");
pub const Styler = @import("style/Styler.zig");
pub const Diagnostic = @import("compile/Diagnostic.zig");
pub const Compilation = @import("compile/Compilation.zig");
pub const Lines = @import("compile/Lines.zig");
pub const json = @import("emit/json.zig");
pub const print = @import("print/print.zig");

test {
    std.testing.refAllDecls(@This());
}
