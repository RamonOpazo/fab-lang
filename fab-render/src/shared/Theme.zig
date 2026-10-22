//! What the colour tokens mean. Every backend resolves a token through the
//! same theme, so `muted` is one grey whether Graphviz, TikZ or the native
//! renderer draws it.
//!
//! A Color is either a literal RGB or a token; the theme sends both to RGB:
//!
//!   rgb : Color → u24,   rgb(.rgb = x) = x,   rgb(.token = t) = theme(t)
//!
//! Backends only format the result (`#rrggbb`, `\definecolor`, …).
//!
//! Besides the tokens, a theme has the colours a backend uses where the Sheet
//! sets none: `ink` for lines, shapes and node text, `soft` for edge labels.

const Style = @import("fab_core").Style;

const Theme = @This();

ink: u24,
soft: u24,
muted: u24,
accent: u24,

pub const default: Theme = .{
    .ink = 0x333333,
    .soft = 0x555555,
    .muted = 0x888888,
    .accent = 0x1f6feb,
};

pub fn rgb(theme: Theme, c: Style.Color) u24 {
    return switch (c) {
        .rgb => |x| x,
        .token => |t| switch (t) {
            .muted => theme.muted,
            .accent => theme.accent,
        },
    };
}

test "literals pass through; tokens come from the theme" {
    const std = @import("std");
    try std.testing.expectEqual(@as(u24, 0x336699), default.rgb(.{ .rgb = 0x336699 }));
    try std.testing.expectEqual(@as(u24, 0x888888), default.rgb(.{ .token = .muted }));
    try std.testing.expectEqual(@as(u24, 0x1f6feb), default.rgb(.{ .token = .accent }));
}
