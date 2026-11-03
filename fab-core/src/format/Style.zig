//! The resolved presentation of one entity (node, edge or zone).
//!
//! Resolving and realizing are separate steps:
//!
//!   σ   : Ir → (V ⊔ E ⊔ Z → Style)    resolving: the cascade, once, here in core
//!   ρ_b : Style → syntax of b          realizing: one per backend, in fab-render
//!
//! A backend reads a Style ("label `f+`, italic, muted") and translates it;
//! it never decides it. Values the theme decides, such as what "muted" means,
//! stay symbolic until a backend realizes them.
//!
//! The cascade folds layers of partial attributes, `Attrs`, with `over`: the
//! later layer wins wherever it sets a value. `over` is associative and the
//! empty Attrs is its identity, so the layers form a monoid and the cascade
//! is a fold of them in order:
//!
//!   kind defaults ⊕ built-in classes ⊕ named classes ⊕ direct attributes ⊕ marks
//!
//! Marks come last, so no program can paint over an issue (statements.md
//! §18).
//!
//! Field names follow the spec's format methods, where they exist.

const std = @import("std");

const Style = @This();

/// The text drawn for the entity. May be empty, as for a hole.
label: []const u8,
/// A short line above the label: "unsupported", on a diagram the compiler
/// can't draw in full (statements.md §15.3).
caption: ?[]const u8,
italic: bool,
/// `:ink`: the colour of text.
ink: ?Color,
/// `:stroke`: the colour of lines and borders.
stroke: ?Color,
/// `:fill`: the colour of areas.
fill: ?Color,
/// `:line`: how lines are drawn.
line: Line,
/// `:shape`: nodes only.
shape: Shape,
/// `:as`: zones only. How the zone appears inside another diagram.
as: As,

pub const Color = union(enum) {
    /// `0xc0392b`
    rgb: u24,
    /// A colour the theme decides, realized by each backend.
    token: Token,

    pub const Token = enum { accent, muted, @"error", warning, unsupported };
};

/// How serious an issue is, as drawn: the colour of its mark. A promoted
/// warning is drawn as an error.
pub const Mark = enum(u2) {
    unsupported,
    warning,
    @"error",

    pub fn max(a: Mark, b: Mark) Mark {
        return if (@backingInt(a) >= @backingInt(b)) a else b;
    }

    pub fn color(m: Mark) Color {
        return .{ .token = switch (m) {
            .unsupported => .unsupported,
            .warning => .warning,
            .@"error" => .@"error",
        } };
    }
};

/// `:line` values that apply to lines.
pub const Line = enum { solid, dashed, dotted, double, wavy, none };

/// `:as` values: how a zone appears from outside. (`:layout` is the other
/// direction: how a zone arranges its own contents.)
pub const As = enum {
    /// Its nodes are drawn directly in the parent, ungrouped.
    flat,
    /// Its nodes are grouped and laid out together. Framed only if it has a
    /// stroke or a fill.
    cluster,
    /// Contracted to a single node: every node the zone owns is identified
    /// with one point, labelled with the zone's `:label` or its name.
    node,
    /// For schemas: one node listing the edges that leave `@`, as rows.
    table,
    /// A statement that drew nothing: a small square crossed corner to
    /// corner. Set from the IR only; no program writes it.
    placeholder,
};

/// `:shape` values, as listed in the spec.
pub const Shape = enum {
    none,
    box,
    round,
    circle,
    double_circle,
    ellipse,
    stadium,
    diamond,
    hexagon,
    parallelogram,
    cylinder,
    document,
    bar,
    point,
    terminal,
    bullseye,
};

/// Partial attributes: one layer of the cascade. Unset fields are null.
pub const Attrs = struct {
    label: ?[]const u8 = null,
    caption: ?[]const u8 = null,
    italic: ?bool = null,
    ink: ?Color = null,
    stroke: ?Color = null,
    fill: ?Color = null,
    line: ?Line = null,
    shape: ?Shape = null,
    as: ?As = null,

    /// The empty layer, the identity of `over`.
    pub const empty: Attrs = .{};

    /// `base` with `top` laid over it: `top` wins wherever it sets a value.
    pub fn over(base: Attrs, top: Attrs) Attrs {
        var result = base;
        inline for (comptime std.meta.fieldNames(Attrs)) |name| {
            if (@field(top, name)) |value| @field(result, name) = value;
        }
        return result;
    }

    /// The Style these attributes describe, with defaults for whatever no
    /// layer set.
    pub fn resolve(a: Attrs) Style {
        return .{
            .label = a.label orelse "",
            .caption = a.caption,
            .italic = a.italic orelse false,
            .ink = a.ink,
            .stroke = a.stroke,
            .fill = a.fill,
            .line = a.line orelse .solid,
            .shape = a.shape orelse .none,
            .as = a.as orelse .cluster,
        };
    }
};
