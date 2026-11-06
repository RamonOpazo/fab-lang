//! What a bracket holds (statements.md §21): elements separated by `/`, each
//! read by its shape, each with an optional `!` that inverts it.
//!
//!   [>/solid!/>>]  symbol `>`, name `solid` inverted, symbol `>>`
//!   [0..*/1..1]    range 0..∞, range 1..1
//!   [/solid/>]     nil, then a name and a symbol
//!   []             one element, nil; [/] is two
//!
//! A bracket has one element more than it has slashes (statements.md
//! §22.2): the reader never yields none.
//!   [:Tip/:Tip]    two type names: a bracket in a type (statements.md §22.8)
//!
//! The reader checks shapes only. What a name refers to, and whether a type
//! fits, belong to the environment (plan step 8c). It allocates nothing:
//! whoever needs a bracket's elements reads it again.

const std = @import("std");
const Decimal = @import("Decimal.zig");
const Error = @import("Error.zig");

pub const Element = struct {
    kind: Kind,
    /// A trailing `!`: struck, inner, inward, off.
    inverted: bool = false,
    /// The element as written, `!` excluded.
    text: []const u8,
};

pub const Kind = union(enum) {
    /// Nil, nothing written: `[]`, the tail of `[/solid/>]`.
    empty,
    /// Lowercase-kebab: `red`, `warn-bg`. A named value or a label.
    name,
    /// Glyphs, with at most one capital letter: `>`, `|>`, `X`, `O{`, `⊸`.
    symbol,
    /// A type name, `:` then UpperCamel: `:Tip`. Only in a type's bracket.
    type,
    color: Rgba,
    number: Decimal,
    range: Range,
};

/// A colour written without alpha is opaque.
pub const Rgba = struct { r: u8, g: u8, b: u8, a: u8 = 0xff };

/// `lo..hi`; `hi` null is `*`, no upper bound.
pub const Range = struct { lo: Decimal, hi: ?Decimal };

/// The elements of a bracket token, `[` and `]` included.
pub fn read(token: []const u8) Reader {
    std.debug.assert(token.len >= 2 and token[0] == '[' and token[token.len - 1] == ']');
    const inner = token[1 .. token.len - 1];
    return .{ .rest = inner, .done = false };
}

pub const Reader = struct {
    rest: []const u8,
    done: bool,
    /// Why the last `next` failed.
    failure: Error.Tag = undefined,

    /// The next element, null after the last. On error.Malformed, `failure`
    /// says why; the elements after it can still be read.
    pub fn next(r: *Reader) error{Malformed}!?Element {
        if (r.done) return null;
        const end = std.mem.indexOfScalar(u8, r.rest, '/');
        const raw = r.rest[0 .. end orelse r.rest.len];
        if (end) |e| r.rest = r.rest[e + 1 ..] else r.done = true;
        return element(raw) catch |tag| {
            r.failure = tagOf(tag);
            return error.Malformed;
        };
    }
};

const Failure = error{
    UppercaseName,
    MalformedName,
    MalformedColor,
    NegativeNumber,
    MalformedNumber,
    EmptyRange,
    MalformedSymbol,
    MisplacedBang,
};

fn tagOf(failure: Failure) Error.Tag {
    return switch (failure) {
        error.UppercaseName => .uppercase_name,
        error.MalformedName => .malformed_name,
        error.MalformedColor => .malformed_color,
        error.NegativeNumber => .negative_number,
        error.MalformedNumber => .malformed_number,
        error.EmptyRange => .empty_range,
        error.MalformedSymbol => .malformed_symbol,
        error.MisplacedBang => .misplaced_bang,
    };
}

fn element(raw: []const u8) Failure!Element {
    if (raw.len == 0) return .{ .kind = .empty, .text = raw };

    // `!` comes last, once, after something.
    const inverted = raw[raw.len - 1] == '!';
    const text = if (inverted) raw[0 .. raw.len - 1] else raw;
    if (text.len == 0 or std.mem.indexOfScalar(u8, text, '!') != null) return error.MisplacedBang;

    const kind: Kind = switch (text[0]) {
        'a'...'z' => try name(text),
        ':' => if (text.len > 1 and std.ascii.isUpper(text[1])) try typeName(text[1..]) else try symbol(text),
        '#' => .{ .color = try color(text[1..]) },
        '0'...'9', '*' => if (std.mem.indexOf(u8, text, "..") != null)
            .{ .range = try range(text) }
        else if (text[0] == '*')
            try symbol(text)
        else
            .{ .number = try number(text) },
        '-', '.' => if (text.len > 1 and std.ascii.isDigit(text[1]))
            (if (text[0] == '-') return error.NegativeNumber else return error.MalformedNumber)
        else
            try symbol(text),
        else => try symbol(text),
    };
    return .{ .kind = kind, .inverted = inverted, .text = text };
}

/// `[a-z][a-z0-9]*(-[a-z0-9]+)*`
fn name(text: []const u8) Failure!Kind {
    for (text) |c| if (std.ascii.isUpper(c)) return error.UppercaseName;
    var after_hyphen = false;
    for (text) |c| switch (c) {
        'a'...'z', '0'...'9' => after_hyphen = false,
        '-' => {
            if (after_hyphen) return error.MalformedName;
            after_hyphen = true;
        },
        else => return error.MalformedName,
    };
    if (after_hyphen) return error.MalformedName;
    return .name;
}

/// UpperCamel: letters and digits, after the capital.
fn typeName(text: []const u8) Failure!Kind {
    for (text) |c| if (!std.ascii.isAlphanumeric(c)) return error.MalformedSymbol;
    return .type;
}

/// 3, 4, 6 or 8 hex digits: `f00`, `f00a`, `d1242f`, `d1242f22`.
fn color(hex: []const u8) Failure!Rgba {
    for (hex) |c| if (!std.ascii.isHex(c)) return error.MalformedColor;
    return switch (hex.len) {
        3, 4 => .{
            .r = nibble(hex[0]) * 0x11,
            .g = nibble(hex[1]) * 0x11,
            .b = nibble(hex[2]) * 0x11,
            .a = if (hex.len == 4) nibble(hex[3]) * 0x11 else 0xff,
        },
        6, 8 => .{
            .r = byte(hex[0..2]),
            .g = byte(hex[2..4]),
            .b = byte(hex[4..6]),
            .a = if (hex.len == 8) byte(hex[6..8]) else 0xff,
        },
        else => error.MalformedColor,
    };
}

fn nibble(c: u8) u8 {
    return std.fmt.charToDigit(c, 16) catch unreachable;
}

fn byte(two: []const u8) u8 {
    return nibble(two[0]) * 16 + nibble(two[1]);
}

fn number(text: []const u8) Failure!Decimal {
    return Decimal.parse(text) catch return error.MalformedNumber;
}

/// `lo..hi`, from a number up to a number or `*`.
fn range(text: []const u8) Failure!Range {
    const dots = std.mem.indexOf(u8, text, "..").?;
    const lo_text = text[0..dots];
    const hi_text = text[dots + 2 ..];
    if (lo_text.len == 0 or lo_text[0] == '*' or hi_text.len == 0) return error.EmptyRange;
    const lo = try number(lo_text);
    if (std.mem.eql(u8, hi_text, "*")) return .{ .lo = lo, .hi = null };
    const hi = try number(hi_text);
    if (lo.order(hi) == .gt) return error.EmptyRange;
    return .{ .lo = lo, .hi = hi };
}

/// Glyphs, with at most one capital letter. ASCII punctuation, less what a
/// bracket uses itself (`/`, `!`, `#`, `[`, `]`; `(`, `)` and `,` end the
/// token, statements.md §22.8), and the Unicode blocks of
/// arrows, mathematical operators and geometric symbols: never a space, a
/// control, a combining mark or a letter of any script.
fn symbol(text: []const u8) Failure!Kind {
    var capitals: usize = 0;
    var lowercase = false;
    const view = std.unicode.Utf8View.init(text) catch return error.MalformedSymbol;
    var it = view.iterator();
    while (it.nextCodepoint()) |c| {
        switch (c) {
            'A'...'Z' => capitals += 1,
            'a'...'z' => lowercase = true,
            // ASCII punctuation, less `!`, `#`, `/`, `[` and `]`.
            '"', 0x24...0x2e, 0x3a...0x40, '\\', 0x5e...0x60, 0x7b...0x7e => {},
            '0'...'9', '/', '!', '#', '[', ']' => return error.MalformedSymbol,
            else => if (!isGlyph(c)) return error.MalformedSymbol,
        }
    }
    // `Warn`, `Ok`: a capital, then lowercase letters, is a name misspelt.
    if (lowercase) return if (std.ascii.isUpper(text[0])) error.UppercaseName else error.MalformedSymbol;
    if (capitals > 1) return error.MalformedSymbol;
    return .symbol;
}

/// The Unicode blocks a symbol may draw from (statements.md §21).
const glyph_blocks = [_][2]u21{
    .{ 0x2190, 0x21ff }, // Arrows
    .{ 0x2200, 0x22ff }, // Mathematical Operators
    .{ 0x2300, 0x23ff }, // Miscellaneous Technical
    .{ 0x25a0, 0x25ff }, // Geometric Shapes
    .{ 0x2600, 0x27bf }, // Miscellaneous Symbols, Dingbats
    .{ 0x27c0, 0x27ff }, // Miscellaneous Mathematical Symbols-A, Supplemental Arrows-A
    .{ 0x2900, 0x29ff }, // Supplemental Arrows-B, Miscellaneous Mathematical Symbols-B
    .{ 0x2a00, 0x2aff }, // Supplemental Mathematical Operators
    .{ 0x2b00, 0x2bff }, // Miscellaneous Symbols and Arrows
};

fn isGlyph(c: u21) bool {
    for (glyph_blocks) |block| if (c >= block[0] and c <= block[1]) return true;
    return false;
}

test {
    _ = @import("value.test.zig");
}
