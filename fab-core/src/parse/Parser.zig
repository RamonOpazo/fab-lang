//! Turns tokens into a concrete syntax tree, following grammar.ebnf.
//!
//! Each grammar rule is one `parseX` function, recursive descent. Where the
//! grammar writes `a ~ b` (b touches a), the code checks `touchesPrev` or
//! `touchesNext`. There is no precedence table: chains are fixed by the
//! grammar, and the operators between chains share one level, read left to
//! right, so each list is a loop.
//!
//! A statement is one line; braces let it span lines. Inside `{ }`, at any
//! depth, a newline is a space and `cur` skips it. Outside them it ends the
//! statement, even inside `( )`.
//!
//! The parser never stops at the first error. A failure is recorded in
//! `errors` and unwinds, as `error.ParseError`, to the statement. The
//! statement becomes an `invalid` node, the parser skips to the next line
//! outside braces, and continues.

const std = @import("std");
const Token = @import("../lex/Token.zig");
const Lexer = @import("../lex/Lexer.zig");
const Cst = @import("Cst.zig");
const Node = Cst.Node;
const TokenIndex = Cst.TokenIndex;

const Parser = @This();

const Error = error{ OutOfMemory, ParseError };

gpa: std.mem.Allocator,
source: [:0]const u8,
tags: []const Token.Tag,
starts: []const u32,
ends: []const u32,

/// The current token.
tok_i: TokenIndex = 0,
/// The last token consumed, for `touchesPrev`. Skipped newlines don't count.
last: ?TokenIndex = null,
/// How many braces are open. While any is, newlines are spaces.
braces: u32 = 0,
/// How many parentheses are open, to tell a statement that spans lines.
parens: u32 = 0,
/// `braces` and `parens` at the moment of the last failure, for recovery.
fail_braces: u32 = 0,
fail_parens: u32 = 0,
/// The last failure was a statement spanning lines.
fail_spans: bool = false,

nodes: std.MultiArrayList(Node) = .empty,
extra: std.ArrayList(u32) = .empty,
errors: std.ArrayList(Cst.Error) = .empty,
/// Children of lists under construction. Nested lists share it as a stack.
scratch: std.ArrayList(Node.Index) = .empty,

/// Lexes and parses `source`. Syntax errors are returned inside the Cst.
pub fn parse(gpa: std.mem.Allocator, source: [:0]const u8) error{OutOfMemory}!Cst {
    var comments: std.ArrayList(Lexer.Comment) = .empty;
    defer comments.deinit(gpa);
    var tokens = try Lexer.tokenize(gpa, source, &comments);
    errdefer tokens.deinit(gpa);

    var p: Parser = .{
        .gpa = gpa,
        .source = source,
        .tags = tokens.items(.tag),
        .starts = tokens.items(.start),
        .ends = tokens.items(.end),
    };
    defer p.scratch.deinit(gpa);
    errdefer p.nodes.deinit(gpa);
    errdefer p.extra.deinit(gpa);
    errdefer p.errors.deinit(gpa);

    p.parseProgram() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.ParseError => unreachable, // the program always recovers
    };

    const extra = try p.extra.toOwnedSlice(gpa);
    errdefer gpa.free(extra);
    const errors = try p.errors.toOwnedSlice(gpa);
    errdefer gpa.free(errors);
    const kept = try comments.toOwnedSlice(gpa);
    return .{
        .source = source,
        .tokens = tokens.toOwnedSlice(),
        .nodes = p.nodes.toOwnedSlice(),
        .extra = extra,
        .errors = errors,
        .comments = kept,
    };
}

// ---------------------------------------------------------------------------
// Statements

/// program = [ statement ] { EOL [ statement ] } EOF
fn parseProgram(p: *Parser) Error!void {
    // The root must be node 0, so it is reserved first and filled in last.
    try p.nodes.append(p.gpa, undefined);
    const top = p.scratch.items.len;

    p.skipEols();
    while (p.cur() != .eof) {
        const start = p.tok_i;
        const scratch_top = p.scratch.items.len;
        const statement = p.parseStatement() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ParseError => blk: {
                // Lists left half-built by the failure must not leak into ours.
                p.scratch.shrinkRetainingCapacity(scratch_top);
                p.recover();
                break :blk try p.addLeaf(.invalid, start);
            },
        };
        try p.scratch.append(p.gpa, statement);

        switch (p.cur()) {
            .eol => p.skipEols(),
            .eof => {},
            else => {
                try p.warn(.expected_token, .eol);
                p.recover();
                p.skipEols();
            },
        }
    }

    const range = try p.listFrom(top);
    p.nodes.set(0, .{ .tag = .root, .main_token = 0, .data = .{ .range = range } });
}

/// statement = part ( DECL | DEFN ) ( levels | block ) | part
/// The head is read as a part; which heads each operator allows is the
/// analyser's call. With no operator the part must be an entry: a
/// description, `G :style { … }` (statements.md §22.1).
fn parseStatement(p: *Parser) Error!Node.Index {
    if (!p.startsItem()) return p.fail(.expected_statement, .invalid);
    const head = try p.parsePart();
    switch (p.cur()) {
        .decl, .defn => {},
        // A description: an entry, with no operator (statements.md §22.1).
        else => return if (p.nodes.items(.tag)[@backingInt(head)] == .entry) head else p.fail(.expected_token, .decl),
    }
    const op = p.next();
    const body = if (p.emptyRecordAhead(op)) try p.parseBlock(true) else try p.parseLevels();
    return p.addNode(.statement, op, .{ .nodes = .{ head, body } });
}

// ---------------------------------------------------------------------------
// Items

/// levels = items { BAR items }
fn parseLevels(p: *Parser) Error!Node.Index {
    const first = try p.parseItems();
    if (p.cur() != .bar) return first;

    const bar = p.tok_i;
    const top = p.scratch.items.len;
    try p.scratch.append(p.gpa, first);
    while (p.cur() == .bar) {
        const this = p.next();
        switch (p.cur()) {
            .bar, .r_cur, .eol, .eof => return p.failAt(.empty_level, this),
            else => {},
        }
        try p.scratch.append(p.gpa, try p.parseItems());
    }
    return p.addNode(.levels, bar, .{ .range = try p.listFrom(top) });
}

/// items = item { COMMA item }
/// Two local fixes keep the rest of the list: a missing comma is reported and
/// assumed, and a trailing comma is reported and ends the list.
fn parseItems(p: *Parser) Error!Node.Index {
    const top = p.scratch.items.len;
    var main: ?TokenIndex = null;
    try p.scratch.append(p.gpa, try p.parseItemRecovering());
    while (true) {
        switch (p.cur()) {
            .comma => {
                const comma = p.next();
                main = main orelse comma;
                switch (p.cur()) {
                    // A newline right after a comma, inside parentheses: the
                    // statement was meant to go on.
                    .eol => if (p.parens > 0) return p.fail(.statement_spans_lines, .invalid) else {
                        try p.warnAt(.trailing_comma, comma);
                        break;
                    },
                    .r_par, .r_cur, .bar, .eof => {
                        try p.warnAt(.trailing_comma, comma);
                        break;
                    },
                    else => {},
                }
            },
            .r_par, .r_cur, .bar, .eol, .eof => break,
            else => if (p.startsItem()) {
                main = main orelse p.tok_i;
                try p.warn(.missing_comma, .invalid);
            } else if (p.braces > 0) {
                // A stray token after an item, inside braces: skip to the next item.
                const stray = p.tok_i;
                main = main orelse stray;
                try p.warn(.expected_token, .comma);
                p.recoverItem();
                try p.scratch.append(p.gpa, try p.addLeaf(.invalid, stray));
                continue;
            } else break,
        }
        try p.scratch.append(p.gpa, try p.parseItemRecovering());
    }
    if (p.scratch.items.len - top == 1) return p.scratch.pop().?;
    return p.addNode(.items, main.?, .{ .range = try p.listFrom(top) });
}

/// An item. Inside braces, one that fails becomes an `invalid` node, and
/// parsing goes on with the next item.
fn parseItemRecovering(p: *Parser) Error!Node.Index {
    if (p.braces == 0) return p.parseItem();
    _ = p.cur();
    const start = p.tok_i;
    const scratch_top = p.scratch.items.len;
    return p.parseItem() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.ParseError => {
            // Lists left half-built by the failure must not leak into ours.
            p.scratch.shrinkRetainingCapacity(scratch_top);
            p.recoverItem();
            return p.addLeaf(.invalid, start);
        },
    };
}

/// item = part [ ( DECL | DEFN ) part ]
/// Inside a record, a naming or a declaration is a statement of its own:
/// `[ink] := [#dddddd]`. Which ones a record allows is the analyser's call.
fn parseItem(p: *Parser) Error!Node.Index {
    const head = try p.parsePart();
    switch (p.cur()) {
        .decl, .defn => {
            const op = p.next();
            const body = if (p.emptyRecordAhead(op)) try p.parseBlock(true) else try p.parsePart();
            return p.addNode(.statement, op, .{ .nodes = .{ head, body } });
        },
        else => return head,
    }
}

/// part = [ chain ] ( attr | block ) | chain { operator chain }
fn parsePart(p: *Parser) Error!Node.Index {
    _ = p.cur(); // skip newlines first, so `start` is a real token
    const start = p.tok_i;
    switch (p.cur()) {
        .attr_id => return p.parseEntry(.root, start),
        .l_cur => return p.parseBlock(false),
        else => {},
    }
    const chain = try p.parseChain();
    return switch (p.cur()) {
        .attr_id, .l_cur => p.parseEntry(chain, start),
        .iden, .cong => p.parseOperation(chain),
        else => chain,
    };
}

/// The rest of an entry: its attribute, or its block. Attributes side by
/// side are an error, never a missing comma: an assumed comma would make the
/// next one bind the owner. The tree keeps them all.
fn parseEntry(p: *Parser, subject: Node.Index, start: TokenIndex) Error!Node.Index {
    const top = p.scratch.items.len;
    try p.scratch.append(p.gpa, subject);
    if (p.cur() == .l_cur) {
        try p.scratch.append(p.gpa, try p.parseBlock(false));
    } else {
        try p.scratch.append(p.gpa, try p.parseAttr());
        if (p.cur() == .attr_id) try p.warnAt(.attributes_side_by_side, p.tok_i);
        while (p.cur() == .attr_id) try p.scratch.append(p.gpa, try p.parseAttr());
    }
    return p.addNode(.entry, start, .{ .range = try p.listFrom(top) });
}

/// attr = ATTR_ID [ ~ DOT ~ VAL ] [ ~ BANG ] [ literal | L_PAR items R_PAR | block ]
/// A `!` touching the attribute is part of it: `:hide!` turns a flag off.
/// Apart, `:hide !`, it is a node, as anywhere else.
fn parseAttr(p: *Parser) Error!Node.Index {
    const name = p.next();
    // A key, `:lemma.[a]`: the node stores nothing, as for `!` (Cst.key).
    if (p.cur() == .dot and p.touchesPrev() and p.touchesNext() and p.tags[p.tok_i + 1] == .val) {
        _ = p.next();
        _ = p.next();
    }
    if (p.cur() == .bang and p.touchesPrev()) _ = p.next();
    const value: Node.Index = switch (p.cur()) {
        .str, .math, .val => try p.addLeaf(.leaf, p.next()),
        // A proposition, the fifth shape of a value: `:axiom (f == g)`.
        .l_par => try p.parseGroup(),
        // A record: `G :style { … }`.
        .l_cur => try p.parseBlock(true),
        else => .root,
    };
    return p.addNode(.attr, name, .{ .node = value });
}

/// The rest of an operation: { operator chain }. One level, left to right;
/// whether the operators agree is the analyser's call.
fn parseOperation(p: *Parser, first: Node.Index) Error!Node.Index {
    const op = p.tok_i;
    const top = p.scratch.items.len;
    try p.scratch.append(p.gpa, first);
    while (true) switch (p.cur()) {
        .iden, .cong => {
            _ = p.next();
            try p.scratch.append(p.gpa, try p.parseChain());
        },
        else => break,
    };
    return p.addNode(.operation, op, .{ .range = try p.listFrom(top) });
}

/// block = L_CUR levels R_CUR. `{}`, the empty record, is a value: after a
/// descriptor, or a naming's body (`empty`); it holds an empty `items`.
fn parseBlock(p: *Parser, empty: bool) Error!Node.Index {
    const open = p.next();
    p.braces += 1;
    defer p.braces -= 1;

    if (p.cur() == .r_cur) {
        if (!empty) return p.failAt(.empty_braces, open);
        const nothing = try p.addNode(.items, open, .{ .range = try p.listFrom(p.scratch.items.len) });
        return p.addNode(.block, open, .{ .node_token = .{ nothing, p.next() } });
    }
    const body = try p.parseLevels();
    const close = try p.expect(.r_cur);
    return p.addNode(.block, open, .{ .node_token = .{ body, close } });
}

// ---------------------------------------------------------------------------
// Chains

/// chain = c_chain { _ c_chain }: an open chain, joined by spaces.
fn parseChain(p: *Parser) Error!Node.Index {
    _ = p.cur();
    const start = p.tok_i;
    const first = try p.parseCChain();
    if (!try p.continuesChain()) return first;

    const top = p.scratch.items.len;
    try p.scratch.append(p.gpa, first);
    while (try p.continuesChain()) try p.scratch.append(p.gpa, try p.parseCChain());
    return p.addNode(.o_chain, start, .{ .range = try p.listFrom(top) });
}

/// Another atom follows, apart from the last one. Touching it is an error:
/// only `/` joins atoms that touch.
fn continuesChain(p: *Parser) Error!bool {
    if (!p.startsAtomAt(p.tok_i)) return false;
    if (p.touchesPrev()) return p.fail(.atoms_touch, .invalid);
    return true;
}

/// c_chain = atom { ~ SLASH ~ atom }: a closed chain, joined by slashes.
fn parseCChain(p: *Parser) Error!Node.Index {
    const first = try p.parseAtom();
    if (!p.atInfixSlash()) return first;

    const slash = p.tok_i;
    const top = p.scratch.items.len;
    try p.scratch.append(p.gpa, first);
    while (p.atInfixSlash()) {
        _ = p.next();
        try p.scratch.append(p.gpa, try p.parseAtom());
    }
    return p.addNode(.c_chain, slash, .{ .range = try p.listFrom(top) });
}

/// A slash touching an atom on each side.
fn atInfixSlash(p: *Parser) bool {
    return p.cur() == .slash and p.touchesPrev() and p.touchesNext() and p.startsAtomAt(p.tok_i + 1);
}

// ---------------------------------------------------------------------------
// Atoms

/// atom = prefix | juxtafix | postfix
/// prefix = marker ~ atom;  juxtafix = postfix ~ DOT ~ atom
fn parseAtom(p: *Parser) Error!Node.Index {
    switch (p.cur()) {
        // `+` touching anything is a prefix. `?` and `!` are one only when
        // they touch an atom; otherwise they are nodes, read as primaries.
        .plus => if (p.touchesNext()) {
            const op = p.next();
            const operand = try p.parseAtom();
            return p.addNode(.prefix, op, .{ .node = operand });
        },
        .quid, .bang => if (p.touchesNext() and p.startsAtomAt(p.tok_i + 1)) {
            const op = p.next();
            const operand = try p.parseAtom();
            return p.addNode(.prefix, op, .{ .node = operand });
        },
        else => {},
    }
    const left = try p.parsePostfix();
    if (p.cur() != .dot or !p.touchesPrev()) return left;
    if (!p.touchesNext()) return p.fail(.detached_dot, .invalid);
    const dot = p.next();
    const right = try p.parseAtom();
    return p.addNode(.juxtafix, dot, .{ .nodes = .{ left, right } });
}

/// postfix = primary [ ~ marker | ~ SLASH ]
/// A slash touching an atom on its right too is infix, not postfix.
fn parsePostfix(p: *Parser) Error!Node.Index {
    const primary = try p.parsePrimary();
    if (!p.touchesPrev()) return primary;
    switch (p.cur()) {
        .plus, .quid, .bang => {
            if (p.touchesNext() and p.startsAtomAt(p.tok_i + 1)) return p.fail(.marker_touches_both_sides, .invalid);
        },
        .slash => if (p.atInfixSlash()) return primary,
        else => return primary,
    }
    const op = p.next();
    return p.addNode(.postfix, op, .{ .node = primary });
}

/// primary = EDGE_ID | NODE_ID | ZONE_ID | CLASS_ID | TYPE_ID | AT | STAR
///         | QUID | BANG | literal | L_PAR items R_PAR
/// A `?` or `!` gets here only when it touches no atom on its right: a node
/// of that kind, as in `f/?`. A type is a primary so that its twins are a
/// postfix, `:Number!`; `:Color.(:Text)` parses, for the analyser to refuse.
fn parsePrimary(p: *Parser) Error!Node.Index {
    switch (p.cur()) {
        .edge_id, .node_id, .zone_id, .class_id, .type_id, .at, .star, .quid, .bang, .str, .math, .val => return p.addLeaf(.leaf, p.next()),
        .l_par => return p.parseGroup(),
        else => return p.fail(.expected_atom, .invalid),
    }
}

fn parseGroup(p: *Parser) Error!Node.Index {
    const open = p.next();
    p.parens += 1;
    defer p.parens -= 1;

    const inner = try p.parseItems();
    if (p.cur() == .bar) return p.fail(.bar_in_group, .invalid);
    const close = try p.expect(.r_par);
    return p.addNode(.group, open, .{ .node_token = .{ inner, close } });
}

// ---------------------------------------------------------------------------
// Tokens

/// The current token's tag. Inside braces, newlines are skipped first.
fn cur(p: *Parser) Token.Tag {
    if (p.braces > 0) {
        while (p.tags[p.tok_i] == .eol) p.tok_i += 1;
    }
    return p.tags[p.tok_i];
}

/// After `:=`, `{` and `}` with only line ends between: the empty record,
/// a naming's body.
fn emptyRecordAhead(p: *Parser, op: TokenIndex) bool {
    if (p.tags[op] != .defn or p.cur() != .l_cur) return false;
    var i = p.tok_i + 1;
    while (p.tags[i] == .eol) i += 1;
    return p.tags[i] == .r_cur;
}

/// Consumes the current token and returns its index.
fn next(p: *Parser) TokenIndex {
    _ = p.cur();
    const i = p.tok_i;
    if (p.tags[i] != .eof) p.tok_i += 1;
    p.last = i;
    return i;
}

fn skipEols(p: *Parser) void {
    while (p.tags[p.tok_i] == .eol) p.tok_i += 1;
}

fn expect(p: *Parser, tag: Token.Tag) Error!TokenIndex {
    if (p.cur() != tag) return p.fail(.expected_token, tag);
    return p.next();
}

/// The current token starts exactly where the last consumed one ended.
fn touchesPrev(p: *Parser) bool {
    const last = p.last orelse return false;
    return p.ends[last] == p.starts[p.tok_i];
}

/// The token after the current one starts exactly where the current one ends.
/// A newline or the end of input never counts as touching.
fn touchesNext(p: *Parser) bool {
    const i = p.tok_i;
    if (p.tags[i] == .eof) return false;
    return switch (p.tags[i + 1]) {
        .eol, .eof => false,
        else => p.ends[i] == p.starts[i + 1],
    };
}

/// Could the token at `i` begin an atom? `+` begins one only as a prefix,
/// touching what follows it; `?` and `!` always do, as a prefix or a node.
fn startsAtomAt(p: *Parser, i: TokenIndex) bool {
    return switch (p.tags[i]) {
        .edge_id, .node_id, .zone_id, .class_id, .type_id, .at, .star, .quid, .bang, .str, .math, .val, .l_par => true,
        .plus => switch (p.tags[i + 1]) {
            .eol, .eof => false,
            else => p.ends[i] == p.starts[i + 1],
        },
        else => false,
    };
}

/// Could the current token begin an item?
fn startsItem(p: *Parser) bool {
    return switch (p.cur()) {
        .attr_id, .l_cur => true,
        else => p.startsAtomAt(p.tok_i),
    };
}

// ---------------------------------------------------------------------------
// Building nodes

fn addNode(p: *Parser, tag: Node.Tag, main_token: TokenIndex, data: Node.Data) Error!Node.Index {
    const index: Node.Index = @fromBackingInt(@intCast(p.nodes.len));
    try p.nodes.append(p.gpa, .{ .tag = tag, .main_token = main_token, .data = data });
    return index;
}

/// A node with no payload: leaf, invalid.
fn addLeaf(p: *Parser, tag: Node.Tag, main_token: TokenIndex) Error!Node.Index {
    return p.addNode(tag, main_token, .{ .none = {} });
}

/// Moves `scratch[top..]` into `extra` and returns its range.
fn listFrom(p: *Parser, top: usize) Error!Cst.Range {
    const items = p.scratch.items[top..];
    const start: u32 = @intCast(p.extra.items.len);
    try p.extra.appendSlice(p.gpa, @ptrCast(items));
    p.scratch.shrinkRetainingCapacity(top);
    return .{ .start = start, .end = start + @as(u32, @intCast(items.len)) };
}

// ---------------------------------------------------------------------------
// Errors and recovery

/// Records an error at the current token and unwinds to the statement.
fn fail(p: *Parser, tag: Cst.Error.Tag, expected: Token.Tag) Error {
    try p.warn(tag, expected);
    return error.ParseError;
}

/// Records an error at `token`, as is, and unwinds to the statement.
fn failAt(p: *Parser, tag: Cst.Error.Tag, token: TokenIndex) Error {
    try p.warnAt(tag, token);
    return error.ParseError;
}

/// Records an error at the current token without unwinding.
fn warn(p: *Parser, tag: Cst.Error.Tag, expected: Token.Tag) error{OutOfMemory}!void {
    _ = p.cur();
    const refined = p.refine(tag);
    try p.record(.{
        .tag = refined,
        .token = p.tok_i,
        .expected = if (refined == .expected_token) expected else .invalid,
    });
}

/// Records an error at `token`, as is, without unwinding.
fn warnAt(p: *Parser, tag: Cst.Error.Tag, token: TokenIndex) error{OutOfMemory}!void {
    try p.record(.{ .tag = tag, .token = token });
}

/// Records an error, and where it happened, for recovery.
fn record(p: *Parser, err: Cst.Error) error{OutOfMemory}!void {
    p.fail_braces = p.braces;
    p.fail_parens = p.parens;
    p.fail_spans = err.tag == .statement_spans_lines;
    try p.errors.append(p.gpa, err);
}

/// A more precise error when the current token explains the failure better
/// than what the parser was looking for: a lexer error, a newline inside
/// parentheses, or an operator attached to the wrong side.
fn refine(p: *Parser, tag: Cst.Error.Tag) Cst.Error.Tag {
    const prev = p.touchesPrev();
    const next_ = p.touchesNext();
    return switch (p.cur()) {
        .invalid => if (p.groupsInBracket()) .expression_in_bracket else .invalid_token,
        .eol => if (p.parens > 0) .statement_spans_lines else tag,
        .slash => if (prev) tag else if (next_) .slash_has_no_prefix_form else .operator_touches_nothing,
        .plus => if (!prev and !next_) .operator_touches_nothing else tag,
        .dot => if (!prev or !next_) .detached_dot else tag,
        else => tag,
    };
}

/// The current token is a `[` that stopped at `(`, `)` or `,` before its
/// `]` or a space: a bracket holding an expression.
fn groupsInBracket(p: *Parser) bool {
    var i: usize = p.starts[p.tok_i];
    if (p.source[i] != '[') return false;
    i += 1;
    while (true) : (i += 1) switch (p.source[i]) {
        '(', ')', ',' => return true,
        0, ' ', '\t', '\r', '\n', '[', ']' => return false,
        else => {},
    };
}

/// Skips the rest of a failed statement: up to the next newline outside
/// braces, or the end of input. Braces opened inside it are skipped with it.
/// A statement that spans lines is skipped up to the line where its
/// parentheses balance, unless a line before that starts a new statement.
fn recover(p: *Parser) void {
    var braces = p.fail_braces;
    var parens = if (p.fail_spans) p.fail_parens else 0;
    while (true) {
        switch (p.tags[p.tok_i]) {
            .eof => return,
            .eol => if (braces == 0 and (parens == 0 or p.lineStartsStatement(p.tok_i + 1))) return,
            .l_cur => braces += 1,
            .r_cur => braces -|= 1,
            .l_par => parens += @intFromBool(p.fail_spans),
            .r_par => parens -|= 1,
            else => {},
        }
        p.tok_i += 1;
    }
}

/// Whether the line starting at `i` holds `::` or `:=`: a new statement.
fn lineStartsStatement(p: *Parser, i: TokenIndex) bool {
    var j = i;
    while (true) : (j += 1) switch (p.tags[j]) {
        .decl, .defn => return true,
        .eol, .eof => return false,
        else => {},
    };
}

/// Skips the rest of a failed item inside braces: up to the next `,` or `|`
/// at its depth, or the bracket that closes it. Newlines are spaces there.
fn recoverItem(p: *Parser) void {
    var depth = (p.fail_braces - p.braces) + (p.fail_parens - p.parens);
    while (true) {
        switch (p.tags[p.tok_i]) {
            .eof => return,
            .comma, .bar => if (depth == 0) return,
            .l_cur, .l_par => depth += 1,
            .r_cur, .r_par => if (depth == 0) return else {
                depth -= 1;
            },
            else => {},
        }
        p.tok_i += 1;
    }
}

test {
    _ = @import("parse.test.zig");
}
