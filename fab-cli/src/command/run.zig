//! Runs a command on source text. Pure apart from its writers: reading the
//! input, writing files and starting Graphviz is main.zig's job.

const std = @import("std");
const fab = @import("fab_core");
const render = @import("fab_render");
const Command = @import("Args.zig").Command;
const report = @import("../output/report.zig");

const Writer = std.Io.Writer;

pub const Error = Writer.Error || error{OutOfMemory};

pub const Outcome = struct {
    /// 0: no errors. 1: the program has errors. 2: the command could not run.
    code: u8,
    /// For rendering: whether `out` holds a result to be written. Never true
    /// for a program with errors under `--strict`.
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
        .check => {
            try report.write(err, c.source, try c.diagnostics(), options);
            return .{ .code = try exitCode(&c) };
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
                try report.write(err, c.source, try c.diagnostics(), options);
                return .{ .code = try exitCode(&c) };
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

            try report.write(err, c.source, try c.diagnostics(), options);
            const code = try exitCode(&c);
            if (command.strict and code != 0) return .{ .code = code };

            if (command.format == .json) {
                try fab.json.writeCompilation(&c, out);
                try out.writeByte('\n');
                return .{ .code = code, .produced = true };
            }

            // Graphviz. Without --strict the IR is kept, holes and all, so
            // there is always a sheet; with it, only a clean program gets here.
            const sheet = (try c.sheet()) orelse return .{ .code = code };
            var notes: render.Note.List = .init(gpa);
            defer notes.deinit();
            try render.to_dot.write(sheet, out, &notes);
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

fn exitCode(c: *fab.Compilation) error{OutOfMemory}!u8 {
    return if ((try c.status()).isError()) 1 else 0;
}

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
