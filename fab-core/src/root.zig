//! fab-core: source in, IR out. No I/O.

const std = @import("std");

pub const Token = @import("lex/Token.zig");
pub const Lexer = @import("lex/Lexer.zig");
pub const Cst = @import("parse/Cst.zig");
pub const Parser = @import("parse/Parser.zig");
pub const Ir = @import("analyse/Ir.zig");
pub const Analyser = @import("analyse/Analyser.zig");
pub const Style = @import("format/Style.zig");
pub const Sheet = @import("format/Sheet.zig");
pub const Formatter = @import("format/Formatter.zig");
pub const Diagnostic = @import("compile/Diagnostic.zig");
pub const Compilation = @import("compile/Compilation.zig");
pub const json = @import("emit/json.zig");

test {
    std.testing.refAllDecls(@This());
}
