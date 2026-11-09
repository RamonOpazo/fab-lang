//! Decoded values (statements.md §22.4, plan step 9d2): what a binding
//! binds, read once by the analyser, so the style pass reads no CST.
//!
//! A value is decoded by the type expected where it is written. Named values
//! are resolved as they are read (`[epi]` is its tuple, `[pink]` its
//! colour); labels stay by name, theme tokens among them, since `[ink]`
//! means one colour in one diagram and another in the next. A bracket of
//! one element is that element, except where a list is expected (`:theme
//! [dark]`); tuples and lists are both `elements`, the type saying which.
//!
//! Slices live in the environment's arena; names are slices of the source.

const std = @import("std");
const Decimal = @import("Decimal.zig");
const value = @import("value.zig");
const Env = @import("Env.zig");

pub const Value = union(enum) {
    /// `[]`, an empty slot, and what failed to decode (its error said so).
    nil,
    /// `:hide` is on, `:hide!` off.
    flag: bool,
    /// `"…"`, its escapes undone.
    text: []const u8,
    /// `$…$`, as written but for `\$`: LaTeX's backslashes are its own.
    math: []const u8,
    color: value.Rgba,
    number: Decimal,
    range: value.Range,
    /// `[circle]`, `[>]`, `[ink]`: a label, by name, with its `!`.
    label: Label,
    /// A tuple's slots, or a list's items.
    elements: []const Value,
    /// `{ … }`, or a named record (`[dark]`).
    record: RecordIndex,
};

pub const Label = struct { name: []const u8, inverted: bool = false };

/// An index into the environment's records.
pub const RecordIndex = enum(u32) { _ };

/// A named record (`:Style [dark] := { … }`) or a bundle's body (`:ref :=
/// :shape [round], :fill [muted]`): what it binds, and its tokens.
pub const Record = struct {
    bindings: []const Binding,
    /// `[ink] := [#dddddd]`.
    tokens: []const Token,
};

pub const Binding = struct {
    /// The classes it binds; null in a bundle, which binds where it is used.
    /// In a theme, nothing written is the diagram it is applied to, `&zone`.
    classes: ?Env.Classes,
    /// The descriptor's name, `:` included.
    descriptor: []const u8,
    /// A table's key, `[a]` in `:lemma.[a]`, brackets excluded.
    key: ?[]const u8 = null,
    value: Value,
};

/// A label bound to a value: `[ink] := [#333333]`, `[circle] := [box]`.
pub const Token = struct { label: []const u8, value: Value };

/// A value as text, for tests and dumps: `nil`, `on`/`off`, `"text"`,
/// `$math$`, `#rrggbb` (`#rrggbbaa` if not opaque), numbers and ranges in
/// their normal form, labels by name with their `!`, `[a/b]` for elements,
/// `record N`.
pub fn write(v: Value, w: *std.Io.Writer) std.Io.Writer.Error!void {
    switch (v) {
        .nil => try w.writeAll("nil"),
        .flag => |on| try w.writeAll(if (on) "on" else "off"),
        .text => |t| try w.print("\"{s}\"", .{t}),
        .math => |m| try w.print("${s}$", .{m}),
        .color => |c| {
            try w.print("#{x:0>2}{x:0>2}{x:0>2}", .{ c.r, c.g, c.b });
            if (c.a != 0xff) try w.print("{x:0>2}", .{c.a});
        },
        .number => |n| try n.format(w),
        .range => |r| {
            try r.lo.format(w);
            try w.writeAll("..");
            if (r.hi) |hi| try hi.format(w) else try w.writeByte('*');
        },
        .label => |l| try w.print("{s}{s}", .{ l.name, if (l.inverted) "!" else "" }),
        .elements => |es| {
            try w.writeByte('[');
            for (es, 0..) |e, i| {
                if (i > 0) try w.writeByte('/');
                try write(e, w);
            }
            try w.writeByte(']');
        },
        .record => |r| try w.print("record {d}", .{@backingInt(r)}),
    }
}
