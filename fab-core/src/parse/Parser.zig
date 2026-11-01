//! Turns tokens into a concrete syntax tree, following grammar.ebnf.
//!
//! Each grammar rule is one `parseX` function. Where the grammar writes
//! `a ~ b` (b touches a), the code checks `touchesPrev` or `touchesNext`.
//!
//! The parser never stops at the first error. A failure is recorded in
//! `errors` and unwinds, as `error.ParseError`, to the nearest statement or
//! block entry. That construct becomes an `invalid` node, the parser skips to
//! the next line at the same bracket depth, and continues.

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
/// Inside ( ) and [ ], newlines are insignificant and skipped.
skip_eol: bool = false,
/// How many brackets are open at the current position.
open: u32 = 0,
/// `open` at the moment of the last failure, for recovery.
fail_open: u32 = 0,

nodes: std.MultiArrayList(Node) = .empty,
extra: std.ArrayList(u32) = .empty,
errors: std.ArrayList(Cst.Error) = .empty,
/// Children of lists under construction. Nested lists share it as a stack.
scratch: std.ArrayList(Node.Index) = .empty,

/// Lexes and parses `source`. Syntax errors are returned inside the Cst.
pub fn parse(gpa: std.mem.Allocator, source: [:0]const u8) error{OutOfMemory}!Cst {
    var tokens = try Lexer.tokenize(gpa, source);
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

    p.parseRoot() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.ParseError => unreachable, // the root always recovers
    };

    const extra = try p.extra.toOwnedSlice(gpa);
    errdefer gpa.free(extra);
    const errors = try p.errors.toOwnedSlice(gpa);
    return .{
        .source = source,
        .tokens = tokens.toOwnedSlice(),
        .nodes = p.nodes.toOwnedSlice(),
        .extra = extra,
        .errors = errors,
    };
}

// ---------------------------------------------------------------------------
// program

fn parseRoot(p: *Parser) Error!void {
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
                p.recover(false);
                break :blk try p.addLeafLike(.invalid, start);
            },
        };
        try p.scratch.append(p.gpa, statement);

        switch (p.cur()) {
            .eol => p.skipEols(),
            .eof => {},
            else => {
                try p.warn(.expected_token, .eol);
                p.recover(false);
                p.skipEols();
            },
        }
    }

    const range = try p.listFrom(top);
    p.nodes.set(0, .{ .tag = .root, .main_token = 0, .data = .{ .range = range } });
}

fn parseStatement(p: *Parser) Error!Node.Index {
    if (p.cur() != .zone_id) return p.fail(.expected_statement, .invalid);
    const zone = p.next();
    switch (p.cur()) {
        .decl => {
            _ = p.next();
            const term = try p.parseTerm();
            return p.addNode(.relations, zone, .{ .node = term });
        },
        .attr_id => {
            const attr = p.next();
            const block = try p.parseBlock();
            return p.addNode(.layer, attr, .{ .node = block });
        },
        else => return p.fail(.expected_token, .decl),
    }
}

// ---------------------------------------------------------------------------
// terms

/// term = path { comma path }
fn parseTerm(p: *Parser) Error!Node.Index {
    const first = try p.parsePath();
    if (p.cur() != .comma) return first;

    const comma = p.tok_i;
    const top = p.scratch.items.len;
    try p.scratch.append(p.gpa, first);
    while (p.cur() == .comma) {
        _ = p.next();
        try p.scratch.append(p.gpa, try p.parsePath());
    }
    return p.addNode(.sum, comma, .{ .range = try p.listFrom(top) });
}

/// path = tight { tight }
fn parsePath(p: *Parser) Error!Node.Index {
    _ = p.cur(); // skip newlines first, so `start` is a real token
    const start = p.tok_i;
    const first = try p.parseTight();
    if (!p.startsUnit()) return first;

    const top = p.scratch.items.len;
    try p.scratch.append(p.gpa, first);
    while (p.startsUnit()) try p.scratch.append(p.gpa, try p.parseTight());
    return p.addNode(.path, start, .{ .range = try p.listFrom(top) });
}

/// tight = unit { ~ slash ~ unit } [ ~ slash ]
fn parseTight(p: *Parser) Error!Node.Index {
    var lhs = try p.parseUnit();
    while (p.cur() == .slash and p.touchesPrev()) {
        const slash = p.next();
        if (p.touchesPrev() and p.startsUnit()) {
            const rhs = try p.parseUnit();
            lhs = try p.addNode(.slash, slash, .{ .nodes = .{ lhs, rhs } });
        } else {
            // a slash touching only its left side: an undirected edge
            return p.addNode(.postfix, slash, .{ .node = lhs });
        }
    }
    return lhs;
}

/// unit = { prefix ~ } atom { ~ postfix }
/// Postfix operators bind tighter than prefix ones: +f? is +(f?).
fn parseUnit(p: *Parser) Error!Node.Index {
    switch (p.cur()) {
        .plus, .star => if (p.touchesNext()) {
            const op = p.next();
            const operand = try p.parseUnit();
            return p.addNode(.prefix, op, .{ .node = operand });
        },
        else => {},
    }
    var node = try p.parseAtom();
    while (true) switch (p.cur()) {
        .plus, .star, .quid, .bang => {
            if (!p.touchesPrev()) break;
            const op = p.next();
            node = try p.addNode(.postfix, op, .{ .node = node });
        },
        else => break,
    };
    return node;
}

fn parseAtom(p: *Parser) Error!Node.Index {
    switch (p.cur()) {
        .edge_id, .node_id, .at => return p.addLeafLike(.leaf, p.next()),
        .zone_id => {
            const zone = p.next();
            if (p.cur() != .dot or !p.touchesPrev()) return p.addLeafLike(.leaf, zone);
            _ = p.next();
            if (!p.touchesPrev()) return p.fail(.detached_dot, .invalid);
            const unit = try p.parseUnit();
            return p.addNode(.qualified, zone, .{ .node = unit });
        },
        .dot => return p.parseClass(),
        .l_par => return p.parseEnclosed(.group, .r_par),
        .l_brack => return p.parseEnclosed(.cells, .r_brack),
        else => return p.fail(.expected_atom, .invalid),
    }
}

/// class = dot ~ edge_id { ~ dot ~ edge_id }
fn parseClass(p: *Parser) Error!Node.Index {
    const first = p.next();
    var last = try p.expectTouching(.edge_id);
    while (p.cur() == .dot and p.touchesPrev()) {
        _ = p.next();
        last = try p.expectTouching(.edge_id);
    }
    return p.addNode(.class, first, .{ .token = last });
}

/// ( term ) and [ term ]. Newlines inside are skipped.
fn parseEnclosed(p: *Parser, tag: Node.Tag, close: Token.Tag) Error!Node.Index {
    const open = p.next();
    const saved = p.skip_eol;
    p.skip_eol = true;
    defer p.skip_eol = saved;
    p.open += 1;
    defer p.open -= 1;

    const term = try p.parseTerm();
    const close_tok = try p.expect(close);
    return p.addNode(tag, open, .{ .node_token = .{ term, close_tok } });
}

// ---------------------------------------------------------------------------
// layers

/// block = l_cur { eol } [ entry { eols entry } ] { eol } r_cur
fn parseBlock(p: *Parser) Error!Node.Index {
    const open = try p.expect(.l_cur);
    const saved = p.skip_eol;
    p.skip_eol = false;
    defer p.skip_eol = saved;
    p.open += 1;
    defer p.open -= 1;

    const top = p.scratch.items.len;
    p.skipEols();
    while (p.cur() != .r_cur and p.cur() != .eof) {
        const start = p.tok_i;
        const scratch_top = p.scratch.items.len;
        const entry = p.parseEntry() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ParseError => blk: {
                // Lists left half-built by the failure must not leak into ours.
                p.scratch.shrinkRetainingCapacity(scratch_top);
                p.recover(true);
                break :blk try p.addLeafLike(.invalid, start);
            },
        };
        try p.scratch.append(p.gpa, entry);

        switch (p.cur()) {
            .eol => p.skipEols(),
            .r_cur, .eof => {},
            else => {
                try p.warn(.expected_token, .eol);
                p.recover(true);
                p.skipEols();
            },
        }
    }
    const close = try p.expect(.r_cur);
    return p.addBraced(.block, open, top, close);
}

/// entry = term attrs | term relation term
fn parseEntry(p: *Parser) Error!Node.Index {
    const start = p.tok_i;
    const subject = try p.parseTerm();
    switch (p.cur()) {
        .attr_id, .l_cur => {
            const attrs = try p.parseAttrs();
            return p.addNode(.entry, start, .{ .nodes = .{ subject, attrs } });
        },
        .iden, .cong => {
            const op = p.next();
            const rhs = try p.parseTerm();
            return p.addNode(.equation, op, .{ .nodes = .{ subject, rhs } });
        },
        else => return p.fail(.expected_attrs_or_relation, .invalid),
    }
}

/// attrs = attr { attr } | l_cur { attr | eol } r_cur
fn parseAttrs(p: *Parser) Error!Node.Index {
    const top = p.scratch.items.len;
    if (p.cur() == .l_cur) {
        const open = p.next();
        p.open += 1;
        defer p.open -= 1;
        while (true) switch (p.cur()) {
            .eol => _ = p.next(),
            .attr_id => try p.scratch.append(p.gpa, try p.parseAttr()),
            else => break,
        };
        const close = try p.expect(.r_cur);
        return p.addBraced(.attr_block, open, top, close);
    }
    const first = p.tok_i;
    while (p.cur() == .attr_id) try p.scratch.append(p.gpa, try p.parseAttr());
    return p.addNode(.attrs, first, .{ .range = try p.listFrom(top) });
}

/// attr = attr_id { value }
fn parseAttr(p: *Parser) Error!Node.Index {
    const name = try p.expect(.attr_id);
    const top = p.scratch.items.len;
    while (p.startsValue()) try p.scratch.append(p.gpa, try p.parseValue());
    return p.addNode(.attr, name, .{ .range = try p.listFrom(top) });
}

fn startsValue(p: *Parser) bool {
    return switch (p.cur()) {
        .number, .str, .math, .arrow, .l_cur => true,
        else => p.startsUnit(),
    };
}

/// value = number | card | string | math | arrow | ref
fn parseValue(p: *Parser) Error!Node.Index {
    switch (p.cur()) {
        .number => {
            const number = p.next();
            if (p.cur() != .range or !p.touchesPrev()) return p.addLeafLike(.leaf, number);
            // card = number ~ range ~ ( number | star )
            _ = p.next();
            switch (p.cur()) {
                .number, .star => if (p.touchesPrev()) {
                    _ = p.next();
                    return p.addLeafLike(.card, number);
                },
                else => {},
            }
            return p.fail(.expected_token, .number);
        },
        .str, .math, .arrow => return p.addLeafLike(.leaf, p.next()),
        else => return p.parseRef(),
    }
}

/// ref = segment { ~ segment }
fn parseRef(p: *Parser) Error!Node.Index {
    const start = p.tok_i;
    const first = try p.parseSegment();
    if (!p.continuesRef()) return first;

    const top = p.scratch.items.len;
    try p.scratch.append(p.gpa, first);
    while (p.continuesRef()) try p.scratch.append(p.gpa, try p.parseSegment());
    return p.addNode(.ref, start, .{ .range = try p.listFrom(top) });
}

fn continuesRef(p: *Parser) bool {
    return p.touchesPrev() and (p.cur() == .l_cur or p.startsUnit());
}

/// segment = unit | interp;  interp = l_cur unit attr r_cur
fn parseSegment(p: *Parser) Error!Node.Index {
    if (p.cur() != .l_cur) return p.parseUnit();
    const open = p.next();
    p.open += 1;
    defer p.open -= 1;
    const unit = try p.parseUnit();
    const attr = try p.parseAttr();
    _ = try p.expect(.r_cur);
    return p.addNode(.interp, open, .{ .nodes = .{ unit, attr } });
}

// ---------------------------------------------------------------------------
// tokens

/// The current token's tag. Inside ( ) and [ ], newlines are skipped first.
fn cur(p: *Parser) Token.Tag {
    if (p.skip_eol) {
        while (p.tags[p.tok_i] == .eol) p.tok_i += 1;
    }
    return p.tags[p.tok_i];
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

/// Expects `tag` touching the previous token, as after a dot.
fn expectTouching(p: *Parser, tag: Token.Tag) Error!TokenIndex {
    if (p.cur() == tag and !p.touchesPrev()) return p.fail(.detached_dot, .invalid);
    return p.expect(tag);
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

/// Could the current token begin a unit?
fn startsUnit(p: *Parser) bool {
    return switch (p.cur()) {
        .edge_id, .node_id, .zone_id, .at, .dot, .l_par, .l_brack => true,
        .plus, .star => p.touchesNext(),
        else => false,
    };
}

// ---------------------------------------------------------------------------
// building nodes

fn addNode(p: *Parser, tag: Node.Tag, main_token: TokenIndex, data: Node.Data) Error!Node.Index {
    const index: Node.Index = @fromBackingInt(@intCast(p.nodes.len));
    try p.nodes.append(p.gpa, .{ .tag = tag, .main_token = main_token, .data = data });
    return index;
}

/// A node with no payload: leaf, card, invalid.
fn addLeafLike(p: *Parser, tag: Node.Tag, main_token: TokenIndex) Error!Node.Index {
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

/// A list with a closing token: block, attr_block.
fn addBraced(p: *Parser, tag: Node.Tag, open: TokenIndex, top: usize, close: TokenIndex) Error!Node.Index {
    const range = try p.listFrom(top);
    const index: Cst.ExtraIndex = @fromBackingInt(@intCast(p.extra.items.len));
    try p.extra.appendSlice(p.gpa, &.{ range.start, range.end, close });
    return p.addNode(tag, open, .{ .extra = index });
}

// ---------------------------------------------------------------------------
// errors and recovery

/// Records an error at the current token and unwinds to the nearest
/// statement or entry.
fn fail(p: *Parser, tag: Cst.Error.Tag, expected: Token.Tag) Error {
    try p.warn(tag, expected);
    return error.ParseError;
}

/// Records an error at the current token without unwinding.
fn warn(p: *Parser, tag: Cst.Error.Tag, expected: Token.Tag) error{OutOfMemory}!void {
    _ = p.cur();
    p.fail_open = p.open;
    const refined = p.refine(tag);
    try p.errors.append(p.gpa, .{
        .tag = refined,
        .token = p.tok_i,
        .expected = if (refined == .expected_token) expected else .invalid,
    });
}

/// A more precise error when the current token explains the failure better
/// than what the parser was looking for: a lexer error, or an operator
/// attached to the wrong side.
fn refine(p: *Parser, tag: Cst.Error.Tag) Cst.Error.Tag {
    const prev = p.touchesPrev();
    const next_ = p.touchesNext();
    return switch (p.cur()) {
        .invalid => .invalid_token,
        .slash => if (prev) tag else if (next_) .slash_has_no_prefix_form else .operator_touches_nothing,
        .plus, .star, .quid, .bang => if (!prev and !next_) .operator_touches_nothing else tag,
        .dot => if (!prev or !next_) .detached_dot else tag,
        else => tag,
    };
}

/// Skips the rest of a failed statement or entry: up to the next newline at
/// the depth where it began, the end of input, or (inside a block) the
/// block's closing brace. Brackets opened inside the failed construct are
/// skipped with it.
fn recover(p: *Parser, stop_at_r_cur: bool) void {
    var depth = p.fail_open - p.open;
    while (true) {
        switch (p.tags[p.tok_i]) {
            .eof => return,
            .eol => if (depth == 0) return,
            .l_par, .l_brack, .l_cur => depth += 1,
            .r_par, .r_brack, .r_cur => |t| {
                if (depth > 0) {
                    depth -= 1;
                } else if (stop_at_r_cur and t == .r_cur) {
                    return;
                }
            },
            else => {},
        }
        p.tok_i += 1;
    }
}

test {
    _ = @import("parse.test.zig");
}
