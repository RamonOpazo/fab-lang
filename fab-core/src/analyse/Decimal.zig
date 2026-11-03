//! An exact decimal: `mantissa` × 10^−`scale`, so 1.5 is (15, 1).
//!
//! fAB never computes with numbers: they go from the source to a renderer
//! unchanged (statements.md §21). So a number is kept exact, compared
//! exactly, and printed as its normal form; only a renderer, laying out
//! geometry, turns one into a float.
//!
//! Every Decimal is normal: no trailing zero after the point, and scale 0
//! for zero. So `1.50` and `1.5` are the same struct, and `007` is 7.

const std = @import("std");

const Decimal = @This();

mantissa: u64,
scale: u5,

/// At most 18 digits from the first nonzero one or the point, whichever
/// comes first, to the last nonzero one: the mantissa always fits a u64.
pub const max_digits = 18;

pub const zero: Decimal = .{ .mantissa = 0, .scale = 0 };

pub const ParseError = error{ Malformed, TooManyDigits };

/// `digits [ "." digits ]`: digits on both sides of a point, no sign, no
/// exponent. Leading zeros and trailing fractional zeros are not counted.
pub fn parse(text: []const u8) ParseError!Decimal {
    const point = std.mem.indexOfScalar(u8, text, '.');
    const whole = text[0 .. point orelse text.len];
    const fraction = if (point) |p| text[p + 1 ..] else "";
    if (whole.len == 0 or !allDigits(whole)) return error.Malformed;
    if (point != null and (fraction.len == 0 or !allDigits(fraction))) return error.Malformed;

    // The digits counted are the mantissa's: from the first nonzero digit of
    // the whole part, or the point, to the last nonzero digit. So 0.05 has
    // two, and both the mantissa and the scale stay within 18 digits, which
    // keeps `order` inside a u128.
    const leading = std.mem.trimStart(u8, whole, "0");
    const trailing = std.mem.trimEnd(u8, fraction, "0");
    if (leading.len + trailing.len > max_digits) return error.TooManyDigits;

    var mantissa: u64 = 0;
    for (leading) |c| mantissa = mantissa * 10 + (c - '0');
    for (trailing) |c| mantissa = mantissa * 10 + (c - '0');
    if (mantissa == 0) return zero;
    return .{ .mantissa = mantissa, .scale = @intCast(trailing.len) };
}

fn allDigits(text: []const u8) bool {
    for (text) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}

/// Exact comparison.
pub fn order(a: Decimal, b: Decimal) std.math.Order {
    // Bring both to the larger scale. The product fits a u128: a mantissa
    // under 10^18, times at most 10^18.
    const scale = @max(a.scale, b.scale);
    const x = @as(u128, a.mantissa) * pow10(scale - a.scale);
    const y = @as(u128, b.mantissa) * pow10(scale - b.scale);
    return std.math.order(x, y);
}

pub fn eql(a: Decimal, b: Decimal) bool {
    return a.mantissa == b.mantissa and a.scale == b.scale;
}

fn pow10(n: u5) u128 {
    var p: u128 = 1;
    for (0..n) |_| p *= 10;
    return p;
}

/// The normal form: `1.5`, `7`, `0.05`.
pub fn format(d: Decimal, w: *std.Io.Writer) std.Io.Writer.Error!void {
    if (d.scale == 0) return w.print("{d}", .{d.mantissa});
    var buf: [32]u8 = undefined;
    const digits = std.fmt.bufPrint(&buf, "{d}", .{d.mantissa}) catch unreachable;
    if (digits.len > d.scale) {
        const cut = digits.len - d.scale;
        try w.print("{s}.{s}", .{ digits[0..cut], digits[cut..] });
    } else {
        try w.writeAll("0.");
        for (0..d.scale - digits.len) |_| try w.writeByte('0');
        try w.writeAll(digits);
    }
}

/// For renderers only, when they lay out geometry.
pub fn toFloat(d: Decimal) f64 {
    return @as(f64, @floatFromInt(d.mantissa)) / @as(f64, @floatFromInt(pow10(d.scale)));
}
