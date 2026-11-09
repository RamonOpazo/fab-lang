//! Concrete syntax tree: what the parser produces from tokens.
//!
//! The layout follows Zig's own AST. Nodes are stored struct-of-arrays, and
//! each node is a tag, a main token and a small `data` payload. Children that
//! don't fit in the payload (lists, closing tokens) live in `extra`, a flat
//! array of u32. A node never stores text: names and literals are tokens,
//! and their text is a span of the source.
//!
//! Three conventions keep the tag set small:
//!   - The node tag says what shape a node has; the token tag at `main_token`
//!     says which variant. A `postfix` node is `f+`, `f?`, `f!` or `f/`
//!     depending on its operator token, and a `leaf` is a name, `@`, `*`, a
//!     class or a literal depending on its token.
//!   - List nodes (`levels`, `items`, `operation`, `o_chain`, `c_chain`) exist
//!     only for two or more elements. A single element is its own node, so
//!     `f` is a leaf, not a chain of one.
//!   - An absent child is `.root`, which is never anyone's child.

const std = @import("std");
const Token = @import("../lex/Token.zig");
const Lexer = @import("../lex/Lexer.zig");

const Cst = @This();

source: [:0]const u8,
tokens: std.MultiArrayList(Token).Slice,
nodes: std.MultiArrayList(Node).Slice,
extra: []const u32,
errors: []const Error,
/// The comments, in order, each before a line end or the end: trivia to the
/// tree, kept for the printer.
comments: []const Lexer.Comment = &.{},

pub const TokenIndex = u32;

pub const Node = struct {
    tag: Tag,
    main_token: TokenIndex,
    data: Data,

    /// A node's position in `nodes`. Distinct from token indices and extra
    /// indices, so the compiler rejects mixing them up.
    pub const Index = enum(u32) {
        root = 0,
        _,
    };

    pub const Tag = enum(u8) {
        // -- program ---------------------------------------------------------

        /// The whole program.
        /// main_token: 0. data.range: the statements.
        root,
        /// `head :: body`, `head := body`.
        /// main_token: `::` or `:=`. data.nodes: head, body.
        statement,

        // -- items -----------------------------------------------------------

        /// `items | items | …`.
        /// main_token: the first `|`. data.range: two or more.
        levels,
        /// `item, item, …`.
        /// main_token: the first comma. data.range: two or more.
        items,
        /// `{ levels }`.
        /// main_token: `{`. data.node_token: what it holds, `}`.
        block,
        /// `subject :attr v :attr …`, `:attr v …`, `subject { … }`.
        /// main_token: the first token. data.range: the subject (`.root` if
        /// there is none), then the attributes or the block.
        entry,
        /// `:attr`, `:attr literal`.
        /// main_token: the attribute. data.node: the literal, or `.root`.
        attr,
        /// `a == b == c`, `a ~= b`: chains joined by operators, one level, a
        /// flat run. The operators are the tokens between the operands.
        /// main_token: the first operator. data.range: two or more operands.
        operation,

        // -- chains ----------------------------------------------------------

        /// `a b …`: an open chain, joined by spaces.
        /// main_token: the first token. data.range: two or more.
        o_chain,
        /// `a/b/…`: a closed chain, joined by touching slashes.
        /// main_token: the first slash. data.range: two or more.
        c_chain,
        /// `+a`, `?a`, `!a`.
        /// main_token: the marker. data.node: the operand.
        prefix,
        /// `a+`, `a?`, `a!`, and `a/` (a trailing slash).
        /// main_token: the operator. data.node: the operand.
        postfix,
        /// `a.b`.
        /// main_token: the dot. data.nodes: left, right.
        juxtafix,
        /// One token: an edge, node or zone name, a class, `@`, `*`, or a
        /// literal (string, math, value).
        /// main_token: that token. data.none.
        leaf,
        /// `( items )`.
        /// main_token: `(`. data.node_token: what it holds, `)`.
        group,

        // -- recovery --------------------------------------------------------

        /// Something the parser couldn't shape. An `Error` explains why.
        /// main_token: where the problem starts. data.none.
        invalid,
    };

    /// Which field is valid is fixed by the node's tag, as documented above.
    pub const Data = union {
        none: void,
        node: Index,
        nodes: [2]Index,
        node_token: struct { Index, TokenIndex },
        range: Range,
    };
};

/// `extra[start..end]` holds node indices.
pub const Range = struct {
    start: u32,
    end: u32,
};

pub const Error = struct {
    tag: Tag,
    /// Where the error is reported.
    token: TokenIndex,
    /// For `expected_token`: the token that was expected.
    expected: Token.Tag = .invalid,

    pub const Tag = enum {
        expected_token,
        /// A line that can't start a statement.
        expected_statement,
        expected_atom,
        /// `Db :: (` with `)` on a later line: outside braces, a newline ends
        /// the statement.
        statement_spans_lines,
        /// `#Done :terminal f :label "x"`: two items with no comma between.
        missing_comma,
        /// `(f, g,)`: a comma with no item after it.
        trailing_comma,
        /// `f :label "x" :bend [inner]`: an entry has one attribute; several
        /// go in braces (statements.md §19).
        attributes_side_by_side,
        /// `G :: {}`.
        empty_braces,
        /// `f | | m`: a level with nothing in it.
        empty_level,
        /// `f (g | h)`: levels are written at the top of a body only.
        bar_in_group,
        /// `f(g)`, `*f`: two atoms touching, with no operator between them.
        atoms_touch,
        /// `f?(g, h)`: a marker touching both sides.
        marker_touches_both_sides,
        /// `f /g`: a slash touching only what follows it.
        slash_has_no_prefix_form,
        /// `+ f`, `f / g`: a tight operator touching nothing.
        operator_touches_nothing,
        /// `A. f`, `A .f`: a dot must touch both sides.
        detached_dot,
        /// A token the lexer couldn't classify.
        invalid_token,
        /// `[:Tip/(:Line,:Nil)/:Tip]`, `[a,b]`: a bracket holds no `(`, `)`
        /// or `,`.
        expression_in_bracket,
    };
};

pub fn deinit(cst: *Cst, gpa: std.mem.Allocator) void {
    cst.tokens.deinit(gpa);
    cst.nodes.deinit(gpa);
    gpa.free(cst.extra);
    gpa.free(cst.errors);
    gpa.free(cst.comments);
    cst.* = undefined;
}

// ---------------------------------------------------------------------------
// Access

pub fn tag(cst: Cst, node: Node.Index) Node.Tag {
    return cst.nodes.items(.tag)[@backingInt(node)];
}

pub fn mainToken(cst: Cst, node: Node.Index) TokenIndex {
    return cst.nodes.items(.main_token)[@backingInt(node)];
}

pub fn data(cst: Cst, node: Node.Index) Node.Data {
    return cst.nodes.items(.data)[@backingInt(node)];
}

pub fn tokenTag(cst: Cst, token: TokenIndex) Token.Tag {
    return cst.tokens.items(.tag)[token];
}

pub fn tokenText(cst: Cst, token: TokenIndex) []const u8 {
    return cst.source[cst.tokens.items(.start)[token]..cst.tokens.items(.end)[token]];
}

/// The node indices stored in `extra[start..end]`.
pub fn list(cst: Cst, range: Range) []const Node.Index {
    return @ptrCast(cst.extra[range.start..range.end]);
}

/// An entry's subject, if it has one.
pub fn subject(cst: Cst, entry: Node.Index) ?Node.Index {
    const first = cst.list(cst.data(entry).range)[0];
    return if (first == .root) null else first;
}

/// The direct children of a node, in source order. Absent children are left out.
pub fn children(cst: Cst, node: Node.Index) []const Node.Index {
    const d = &cst.nodes.items(.data)[@backingInt(node)];
    return switch (cst.tag(node)) {
        .root, .levels, .items, .operation, .o_chain, .c_chain => cst.list(d.range),
        .entry => blk: {
            const all = cst.list(d.range);
            break :blk if (all[0] == .root) all[1..] else all;
        },
        .statement, .juxtafix => &d.nodes,
        .prefix, .postfix => (&d.node)[0..1],
        .attr => if (d.node == .root) &.{} else (&d.node)[0..1],
        .block, .group => (&d.node_token[0])[0..1],
        .leaf, .invalid => &.{},
    };
}

// ---------------------------------------------------------------------------
// Spans

/// The first token that belongs to a node.
pub fn firstToken(cst: Cst, node: Node.Index) TokenIndex {
    return switch (cst.tag(node)) {
        .statement,
        .levels,
        .items,
        .entry,
        .operation,
        .o_chain,
        .c_chain,
        .postfix,
        .juxtafix,
        => cst.firstToken(cst.children(node)[0]),
        .root, .attr, .block, .prefix, .leaf, .group, .invalid => cst.mainToken(node),
    };
}

/// The last token that belongs to a node.
pub fn lastToken(cst: Cst, node: Node.Index) TokenIndex {
    const d = cst.data(node);
    return switch (cst.tag(node)) {
        .root => @intCast(cst.tokens.len - 1),
        .postfix, .leaf, .invalid => cst.mainToken(node),
        .block, .group => d.node_token[1],
        .attr => if (d.node != .root) cst.lastToken(d.node) else if (cst.inverted(node)) cst.bangOf(node) else cst.key(node) orelse cst.mainToken(node),
        .statement,
        .levels,
        .items,
        .entry,
        .operation,
        .o_chain,
        .c_chain,
        .prefix,
        .juxtafix,
        => blk: {
            const kids = cst.children(node);
            break :blk cst.lastToken(kids[kids.len - 1]);
        },
    };
}

/// An attribute turned off by a `!` touching it: `:hide!`. The `!` is the
/// token right after the attribute's name, or after its key, so the node
/// stores nothing.
pub fn inverted(cst: Cst, attr: Node.Index) bool {
    const bang = cst.bangOf(attr);
    return cst.tokenTag(bang) == .bang and cst.touch(bang - 1, bang);
}

/// Where an attribute's `!` would be: after its name, or after its key.
fn bangOf(cst: Cst, attr: Node.Index) TokenIndex {
    return if (cst.key(attr)) |k| k + 1 else cst.mainToken(attr) + 1;
}

/// A table's key, `:lemma.[a]`: a bracket after a dot, all three touching.
pub fn key(cst: Cst, attr: Node.Index) ?TokenIndex {
    const name = cst.mainToken(attr);
    if (cst.tokenTag(name + 1) != .dot or cst.tokenTag(name + 2) != .val) return null;
    if (!cst.touch(name, name + 1) or !cst.touch(name + 1, name + 2)) return null;
    return name + 2;
}

/// Token `b` starts where token `a` ends.
fn touch(cst: Cst, a: TokenIndex, b: TokenIndex) bool {
    return cst.tokens.items(.end)[a] == cst.tokens.items(.start)[b];
}

/// The operators of an `operation`, in order: the tokens between its operands.
pub fn operator(cst: Cst, operation: Node.Index, i: usize) TokenIndex {
    return cst.lastToken(cst.children(operation)[i]) + 1;
}

// ---------------------------------------------------------------------------
// Dump: one node per line, children indented. The format of `fab show cst`.

pub fn dump(cst: Cst, w: *std.Io.Writer) std.Io.Writer.Error!void {
    try cst.dumpNode(w, .root, 0);
}

fn dumpNode(cst: Cst, w: *std.Io.Writer, node: Node.Index, depth: usize) std.Io.Writer.Error!void {
    for (0..depth) |_| try w.writeAll("  ");
    const t = cst.tag(node);
    const main = cst.mainToken(node);
    try w.writeAll(@tagName(t));
    switch (t) {
        .statement, .prefix, .postfix => try w.print(" {s}", .{cst.tokenText(main)}),
        .attr => {
            try w.print(" {s}", .{cst.tokenText(main)});
            if (cst.key(node)) |k| try w.print(".{s}", .{cst.tokenText(k)});
            if (cst.inverted(node)) try w.writeAll("!");
        },
        .operation => for (0..cst.children(node).len - 1) |i| {
            try w.print(" {s}", .{cst.tokenText(cst.operator(node, i))});
        },
        .leaf => try w.print(" {s} {s}", .{ @tagName(cst.tokenTag(main)), cst.tokenText(main) }),
        .invalid => try w.print(" '{s}'", .{cst.tokenText(main)}),
        .root, .levels, .items, .block, .entry, .o_chain, .c_chain, .juxtafix, .group => {},
    }
    try w.writeAll("\n");
    for (cst.children(node)) |child| try cst.dumpNode(w, child, depth + 1);
}
