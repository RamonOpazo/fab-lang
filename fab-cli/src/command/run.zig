//! Runs a command on source text. Pure apart from its writers: reading the
//! input, writing files and starting Graphviz is main.zig's job.

const std = @import("std");
const fab = @import("fab_core");
const render = @import("fab_render");
const place = @import("fab_layer_place");
const Command = @import("Args.zig").Command;
const report = @import("../output/report.zig");

const Writer = std.Io.Writer;

pub const Error = Writer.Error || error{OutOfMemory};

pub const Outcome = struct {
    /// 0: no errors. 1: the program has errors. 2: the command could not run.
    code: u8,
    /// For rendering: whether `out` holds a result to be written. Never true
    /// for a program with errors under `--strict`. For `fmt -w`: whether
    /// `out` holds the program formatted, to be written back, since it
    /// changed.
    produced: bool = false,
    /// For rendering: `out` holds DOT, which Graphviz must turn into this
    /// format before it is written. Null when `out` is the result itself.
    graphviz: ?Command.Format = null,
};

/// Runs `command` on `source`. Results go to `out`, diagnostics and messages
/// to `err`. `label` names the input in diagnostics.
pub fn run(gpa: std.mem.Allocator, command: Command, source: []const u8, label: []const u8, out: *Writer, err: *Writer) Error!Outcome {
    const tolerance: fab.Compilation.Tolerance = if (command.strict)
        .{ .warnings = .promote, .ir = .withhold }
    else
        .{ .warnings = .warn, .ir = .keep };
    var c = try fab.Compilation.init(gpa, source, tolerance);
    defer c.deinit();
    const options: report.Options = .{ .verbosity = command.verbosity, .color = command.color, .path = label };

    switch (command.action) {
        .fmt => {
            // Only the syntax runs: a program is formatted from its tree.
            const tree = try c.cst();
            if (tree.errors.len > 0) {
                try report.write(err, c.source, c.diags.items, options);
                return .{ .code = 1 };
            }
            var formatted: Writer.Allocating = .init(gpa);
            defer formatted.deinit();
            fab.print.program(gpa, tree, &formatted.writer) catch |e| switch (e) {
                error.SyntaxError => unreachable, // checked above
                error.OutOfMemory => return error.OutOfMemory,
                error.WriteFailed => return error.OutOfMemory, // an allocating writer fails only so
            };
            const same = std.mem.eql(u8, formatted.written(), source);
            switch (command.fmt) {
                .print => try out.writeAll(formatted.written()),
                .write => if (!same) {
                    try out.writeAll(formatted.written());
                    return .{ .code = 0, .produced = true };
                },
                .check => if (!same) {
                    try err.print("{s}: not formatted\n", .{label});
                    return .{ .code = 1 };
                },
            }
            return .{ .code = 0 };
        },
        .check => {
            var checked = try Checked.of(gpa, &c);
            defer checked.deinit(gpa);
            try report.write(err, c.source, checked.all, options);
            return .{ .code = checked.code };
        },
        .show => switch (command.stage) {
            .tokens => {
                if (command.json) try fab.json.writeTokens(&c, out) else try writeTokens(&c, out);
                return .{ .code = 0 };
            },
            .cst => {
                if (command.json) return notYet(err, "`show cst --json`", "use `show cst` for the text form");
                const tree = try c.cst();
                try tree.dump(out);
                // Only the syntax diagnostics: the CST is all that ran.
                try report.write(err, c.source, c.diags.items, options);
                return .{ .code = if (tree.errors.len > 0) 1 else 0 };
            },
            .ir => {
                if (command.json) {
                    try fab.json.writeCompilation(&c, out);
                    try out.writeByte('\n');
                } else if (try c.ir()) |ir| {
                    try ir.dump(out);
                }
                var checked = try Checked.of(gpa, &c);
                defer checked.deinit(gpa);
                try report.write(err, c.source, checked.all, options);
                return .{ .code = checked.code };
            },
            .place => {
                if (command.json) return notYet(err, "`show place --json`", "use `show place` for the text form");
                var checked = try Checked.of(gpa, &c);
                defer checked.deinit(gpa);
                if (checked.placed) |*p| try p.dump(out);
                try report.write(err, c.source, checked.all, options);
                return .{ .code = checked.code };
            },
        },
        .render => {
            if (command.zone != null) return notYet(err, "`--zone`", "it arrives with zone selection");
            if (command.preview) return notYet(err, "`--preview`", "it arrives with the preview page");
            switch (command.format) {
                .json => {},
                else => switch (command.engine) {
                    .native => return notYet(err, "the native engine", "try `-e graphviz`"),
                    .latex => return notYet(err, "the latex engine", "it arrives with 2tikz; try `-e graphviz`"),
                    .graphviz => {},
                },
            }

            var checked = try Checked.of(gpa, &c);
            defer checked.deinit(gpa);
            try report.write(err, c.source, checked.all, options);
            const code = checked.code;
            if (command.strict and code != 0) return .{ .code = code };

            if (command.format == .json) {
                try fab.json.writeCompilation(&c, out);
                try out.writeByte('\n');
                return .{ .code = code, .produced = true };
            }

            // Graphviz. Without --strict the IR is kept, holes and all, so
            // there is always something to draw; with it, only a clean program
            // gets here.
            var notes: render.Note.List = .init(gpa);
            defer notes.deinit();
            if (!try render.to_dot.draw(&c, out, &notes)) return .{ .code = code };
            try report.writeNotes(err, notes.items.items, options);
            return .{
                .code = code,
                .produced = true,
                .graphviz = if (command.format == .dot) null else command.format,
            };
        },
    }
}

/// Where rendering writes: a path, or null for standard output. With no
/// `-o`, a file next to the input with the format's extension; for standard
/// input, standard output.
pub fn outputPath(arena: std.mem.Allocator, command: Command) error{OutOfMemory}!?[]const u8 {
    if (command.output) |out| return if (std.mem.eql(u8, out, "-")) null else out;
    if (std.mem.eql(u8, command.input, "-")) return null;
    const ext = std.fs.path.extension(command.input);
    const stem = command.input[0 .. command.input.len - ext.len];
    return try std.fmt.allocPrint(arena, "{s}.{s}", .{ stem, @tagName(command.format) });
}

/// A program checked by the language and its layers (statements.md §29):
/// fab-core's diagnostics, then the place layer's, which runs only when
/// there is an IR. The layers' warnings are promoted as the language's are.
const Checked = struct {
    all: []fab.Diagnostic,
    placed: ?place.Place,
    code: u8,

    fn of(gpa: std.mem.Allocator, c: *fab.Compilation) error{OutOfMemory}!Checked {
        var placed = try place.of(gpa, c);
        errdefer if (placed) |*p| p.deinit();
        var all: std.ArrayList(fab.Diagnostic) = .empty;
        errdefer all.deinit(gpa);
        try all.appendSlice(gpa, try c.diagnostics());
        if (placed) |p| for (p.diagnostics) |d| {
            var promoted = d;
            if (d.severity == .warning and c.tolerance.warnings == .promote) promoted.severity = .promoted;
            try all.append(gpa, promoted);
        };
        var status: fab.Compilation.Status = .ok;
        for (all.items) |d| status = status.join(.of(d.severity));
        return .{ .all = try all.toOwnedSlice(gpa), .placed = placed, .code = if (status.isError()) 1 else 0 };
    }

    fn deinit(ch: *Checked, gpa: std.mem.Allocator) void {
        gpa.free(ch.all);
        if (ch.placed) |*p| p.deinit();
    }
};

fn notYet(err: *Writer, what: []const u8, why: []const u8) Error!Outcome {
    try err.print("fab: {s} is not available yet: {s}\n", .{ what, why });
    return .{ .code = 2 };
}

/// One token per line: position, tag, text.
fn writeTokens(c: *fab.Compilation, out: *Writer) Error!void {
    const tokens = try c.tokens();
    for (tokens.items(.tag), tokens.items(.start), tokens.items(.end)) |tag, start, end| {
        const at = report.locate(c.source, start);
        var position: [24]u8 = undefined;
        const pos = std.fmt.bufPrint(&position, "{d}:{d}", .{ at.line, at.column }) catch unreachable;
        const text = switch (tag) {
            .eol => "\\n",
            else => c.source[start..end],
        };
        // No padding after the tag when there is no text, so lines never
        // end in spaces.
        if (text.len == 0) {
            try out.print("{s: <8} {s}\n", .{ pos, @tagName(tag) });
        } else {
            try out.print("{s: <8} {s: <12} {s}\n", .{ pos, @tagName(tag), text });
        }
    }
}

test {
    _ = @import("run.test.zig");
}
