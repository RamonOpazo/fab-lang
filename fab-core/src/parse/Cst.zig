//! Concrete syntax tree: what the parser produces from tokens.
//!
//! The layout follows Zig's own AST. Nodes are stored struct-of-arrays, and
//! each node is a tag, a main token and a small `data` payload. Children that
//! don't fit in the payload (lists, closing tokens) live in `extra`, a flat
//! array of u32. A node never stores text: names and literals are tokens,
//! and their text is a span of the source.
//!
//! Two conventions keep the tag set small:
//!   - The node tag says what shape a node has; the token tag at `main_token`
//!     says which variant. A `postfix` node is `f+`, `f*`, `f?`, `f!` or `f/`
//!     depending on its operator token, and a `leaf` is a name, `@` or a
//!     literal depending on its token.
//!   - List nodes (`sum`, `path`, `ref`) exist only for two or more elements.
//!     A single element is its own node, so `f` is a leaf, not a path of one.

const std = @import("std");
const Token = @import("../lex/Token.zig");

const Cst = @This();

source: [:0]const u8,
tokens: std.MultiArrayList(Token).Slice,
nodes: std.MultiArrayList(Node).Slice,
extra: []const u32,
errors: []const Error,

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
        /// `G :: term`.
        /// main_token: the zone name; `::` follows. data.node: the term.
        relations,
        /// `G :format { … }`.
        /// main_token: the attribute; the zone name precedes it. data.node: the block.
        layer,

        // -- terms -----------------------------------------------------------

        /// `s, t, …`: disjoint union.
        /// main_token: the first comma. data.range: two or more terms.
        sum,
        /// `s t …`: juxtaposition.
        /// main_token: the first token. data.range: two or more terms.
        path,
        /// `s/t`: a back edge.
        /// main_token: the slash. data.nodes: left, right.
        slash,
        /// `+u`, `*u`.
        /// main_token: the operator. data.node: the operand.
        prefix,
        /// `u+`, `u*`, `u?`, `u!`, and `u/` (an undirected edge).
        /// main_token: the operator. data.node: the operand.
        postfix,
        /// One token: an edge, node or zone name, `@`, or a literal
        /// (number, string, math, arrow).
        /// main_token: that token. data.none.
        leaf,
        /// `A.u`: u inside zone A.
        /// main_token: the zone name; the dot follows. data.node: u.
        qualified,
        /// `.iso`, `.node.id`: a class.
        /// main_token: the first dot. data.token: the last name.
        class,
        /// `( term )`.
        /// main_token: `(`. data.node_token: the term, `)`.
        group,
        /// `[ term ]`: edge-to-edge relations.
        /// main_token: `[`. data.node_token: the term, `]`.
        cells,

        // -- layers ----------------------------------------------------------

        /// `{ entries }`: a layer's body.
        /// main_token: `{`. data.extra: a `Braced` list of entries.
        block,
        /// `subject attrs`.
        /// main_token: the subject's first token. data.nodes: subject, attributes
        /// (an `attrs` or `attr_block` node).
        entry,
        /// `lhs == rhs`, `lhs ~= rhs`.
        /// main_token: `==` or `~=`. data.nodes: left, right.
        equation,
        /// Attributes written inline: `:label "x" :shape circle`.
        /// main_token: the first attribute. data.range: one or more `attr` nodes.
        attrs,
        /// Attributes written as a block: `{ :label "x" … }`.
        /// main_token: `{`. data.extra: a `Braced` list of `attr` nodes.
        attr_block,
        /// `:name value…`.
        /// main_token: the attribute name. data.range: the values, possibly none.
        attr,
        /// `0..*`, `0..1`.
        /// main_token: the first number; `..` and the bound follow. data.none.
        card,
        /// Touching segments: `{.edge+ :snakecase}_id`.
        /// main_token: the first token. data.range: two or more segments.
        ref,
        /// `{ unit attr }`: an interpolation inside a value.
        /// main_token: `{`. data.nodes: the unit, the attribute.
        interp,

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
        token: TokenIndex,
        range: Range,
        extra: ExtraIndex,
    };
};

/// A position in `extra`.
pub const ExtraIndex = enum(u32) { _ };

/// `extra[start..end]` holds node indices.
pub const Range = struct {
    start: u32,
    end: u32,
};

/// A list with a closing token: `extra[start..end]` holds node indices.
pub const Braced = struct {
    start: u32,
    end: u32,
    close: TokenIndex,
};

pub const Error = struct {
    tag: Tag,
    /// Where the error is reported.
    token: TokenIndex,
    /// For `expected_token`: the token that was expected.
    expected: Token.Tag = .invalid,

    pub const Tag = enum {
        expected_token,
        expected_statement,
        expected_atom,
        expected_attrs_or_relation,
        /// `f /g`: a slash touching only what follows it.
        slash_has_no_prefix_form,
        /// `+ f`, `f / g`: a tight operator touching nothing.
        operator_touches_nothing,
        /// `A. f`, `A .f`: a dot must touch both sides.
        detached_dot,
        /// A token the lexer couldn't classify.
        invalid_token,
    };
};

pub fn deinit(cst: *Cst, gpa: std.mem.Allocator) void {
    cst.tokens.deinit(gpa);
    cst.nodes.deinit(gpa);
    gpa.free(cst.extra);
    gpa.free(cst.errors);
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
pub fn list(cst: Cst, start: u32, end: u32) []const Node.Index {
    return @ptrCast(cst.extra[start..end]);
}

/// The `Braced` list stored in `extra` at `index`.
pub fn braced(cst: Cst, index: ExtraIndex) Braced {
    const i = @backingInt(index);
    return .{ .start = cst.extra[i], .end = cst.extra[i + 1], .close = cst.extra[i + 2] };
}

/// The direct children of a node, in source order.
pub fn children(cst: Cst, node: Node.Index) []const Node.Index {
    const d = cst.data(node);
    return switch (cst.tag(node)) {
        .root, .sum, .path, .attrs, .attr, .ref => cst.list(d.range.start, d.range.end),
        .block, .attr_block => blk: {
            const b = cst.braced(d.extra);
            break :blk cst.list(b.start, b.end);
        },
        .relations, .layer, .prefix, .postfix, .qualified => (&cst.nodes.items(.data)[@backingInt(node)].node)[0..1],
        .group, .cells => (&cst.nodes.items(.data)[@backingInt(node)].node_token[0])[0..1],
        .slash, .entry, .equation, .interp => &cst.nodes.items(.data)[@backingInt(node)].nodes,
        .leaf, .class, .card, .invalid => &.{},
    };
}

// ---------------------------------------------------------------------------
// Spans

/// The first token that belongs to a node.
pub fn firstToken(cst: Cst, node: Node.Index) TokenIndex {
    const main = cst.mainToken(node);
    return switch (cst.tag(node)) {
        .layer => main - 1,
        .sum, .path, .ref, .slash, .postfix, .entry, .equation => cst.firstToken(cst.children(node)[0]),
        .root,
        .relations,
        .prefix,
        .leaf,
        .qualified,
        .class,
        .group,
        .cells,
        .block,
        .attrs,
        .attr_block,
        .attr,
        .card,
        .interp,
        .invalid,
        => main,
    };
}

/// The last token that belongs to a node.
pub fn lastToken(cst: Cst, node: Node.Index) TokenIndex {
    const main = cst.mainToken(node);
    const d = cst.data(node);
    return switch (cst.tag(node)) {
        .root => @intCast(cst.tokens.len - 1),
        .postfix, .leaf, .invalid => main,
        .class => d.token,
        .card => main + 2,
        .group, .cells => d.node_token[1],
        .block, .attr_block => cst.braced(d.extra).close,
        .interp => cst.lastToken(d.nodes[1]) + 1,
        .attr => if (cst.children(node).len == 0) main else cst.lastLeaf(node),
        .relations,
        .layer,
        .sum,
        .path,
        .slash,
        .prefix,
        .qualified,
        .entry,
        .equation,
        .attrs,
        .ref,
        => cst.lastLeaf(node),
    };
}

fn lastLeaf(cst: Cst, node: Node.Index) TokenIndex {
    const kids = cst.children(node);
    return cst.lastToken(kids[kids.len - 1]);
}

// ---------------------------------------------------------------------------
// Dump: one node per line, children indented. The format of `fab cst` and of
// the golden files in test/cases/parse/.

pub fn dump(cst: Cst, w: *std.Io.Writer) std.Io.Writer.Error!void {
    try cst.dumpNode(w, .root, 0);
}

fn dumpNode(cst: Cst, w: *std.Io.Writer, node: Node.Index, depth: usize) std.Io.Writer.Error!void {
    for (0..depth) |_| try w.writeAll("  ");
    const t = cst.tag(node);
    const main = cst.mainToken(node);
    try w.writeAll(@tagName(t));
    switch (t) {
        .relations, .qualified, .attr, .prefix, .postfix, .slash, .equation => try w.print(" {s}", .{cst.tokenText(main)}),
        .layer => try w.print(" {s} {s}", .{ cst.tokenText(main - 1), cst.tokenText(main) }),
        .leaf => try w.print(" {s} {s}", .{ @tagName(cst.tokenTag(main)), cst.tokenText(main) }),
        .class, .card => try w.print(" {s}", .{cst.spanText(main, cst.lastToken(node))}),
        .invalid => try w.print(" '{s}'", .{cst.tokenText(main)}),
        .root, .sum, .path, .group, .cells, .block, .entry, .attrs, .attr_block, .ref, .interp => {},
    }
    try w.writeAll("\n");
    for (cst.children(node)) |child| try cst.dumpNode(w, child, depth + 1);
}

fn spanText(cst: Cst, first: TokenIndex, last: TokenIndex) []const u8 {
    return cst.source[cst.tokens.items(.start)[first]..cst.tokens.items(.end)[last]];
}
