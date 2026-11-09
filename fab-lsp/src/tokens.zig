//! Semantic tokens: what each token of a program is, for an editor to colour
//! (`textDocument/semanticTokens/full`). The lexer's tags already tell the
//! sorts apart: a diagram, an edge, a node, a descriptor, a type, a class.
//! What only analysis knows (a cell rather than an edge, a prelude name)
//! comes with navigation (plan step L2).
//!
//! Encoded as the protocol asks: five integers per token, relative to the
//! one before: line delta, start delta (UTF-16, from the previous start on
//! the same line), length (UTF-16), type, modifiers.

const std = @import("std");
const fab = @import("fab_core");
const Token = fab.Token;

/// The legend sent at initialisation; `Type` indexes it.
pub const types = [_][]const u8{ "namespace", "function", "variable", "property", "type", "enum", "string", "operator" };
pub const modifiers = [_][]const u8{"declaration"};

pub const Type = enum(u32) { namespace, function, variable, property, type, @"enum", string, operator };
pub const declaration: u32 = 1 << 0;

/// What a token is, or null for punctuation and line ends.
pub fn typeOf(tag: Token.Tag) ?Type {
    return switch (tag) {
        .zone_id => .namespace,
        .edge_id => .function,
        .node_id, .at => .variable,
        .attr_id => .property,
        .type_id => .type,
        .class_id => .@"enum",
        .str, .math, .val => .string,
        .slash, .plus, .star, .quid, .bang, .dot, .iden, .cong, .decl, .defn, .bar => .operator,
        .eof, .eol, .invalid, .comma, .l_par, .r_par, .l_cur, .r_cur => null,
    };
}

/// The encoded tokens of `source`, owned by the caller. A diagram's or a
/// type's name right before `::` is its declaration. A token spanning lines
/// is left out, since not every editor can show one.
pub fn encode(gpa: std.mem.Allocator, source: []const u8) error{OutOfMemory}![]u32 {
    var c = try fab.Compilation.init(gpa, source, .{ .warnings = .warn, .ir = .keep });
    defer c.deinit();
    const toks = try c.tokens();
    var lines = try fab.Lines.init(gpa, source);
    defer lines.deinit(gpa);

    const tags = toks.items(.tag);
    const starts = toks.items(.start);
    const ends = toks.items(.end);

    var data: std.ArrayList(u32) = .empty;
    errdefer data.deinit(gpa);
    var line: u32 = 0;
    var character: u32 = 0;
    for (tags, starts, ends, 0..) |tag, start, end, i| {
        const t = typeOf(tag) orelse continue;
        const from = lines.position(start);
        const to = lines.position(end);
        if (from.line != to.line) continue;
        const mods: u32 = if ((tag == .zone_id or tag == .type_id) and nextIs(tags, i, .decl)) declaration else 0;
        const delta_line = from.line - line;
        const delta_start = if (delta_line == 0) from.character - character else from.character;
        try data.appendSlice(gpa, &.{ delta_line, delta_start, to.character - from.character, @backingInt(t), mods });
        line = from.line;
        character = from.character;
    }
    return data.toOwnedSlice(gpa);
}

/// Whether the token after `i`, line ends aside, is `tag`.
fn nextIs(tags: []const Token.Tag, i: usize, tag: Token.Tag) bool {
    var j = i + 1;
    while (j < tags.len and tags[j] == .eol) j += 1;
    return j < tags.len and tags[j] == tag;
}

test {
    _ = @import("tokens.test.zig");
}
