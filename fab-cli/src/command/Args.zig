//! Parses the command line into a Command. Pure: no I/O.
//!
//!   fab render <file> [options]          draw the diagram
//!   fab check <file> [options]           diagnostics only
//!   fab show tokens|cst|ir <file> [options]
//!
//! The command is always the first word, so a file may have any name:
//! `fab render check` draws a file called `check`. A bare `fab order.fab`
//! is a usage error with a hint. Options may appear anywhere after the
//! command; `--` ends options, and `-` reads standard input.
//!
//! Every mistake is reported: an unknown option, a missing value, an option
//! that means nothing for the chosen command, an engine that can't produce
//! the format asked for.

const std = @import("std");

pub const Command = struct {
    action: Action,
    /// For `show`: which stage.
    stage: Stage = .ir,
    /// A path, or "-" for standard input.
    input: []const u8,
    /// A path, or "-" for standard output. Render only.
    output: ?[]const u8 = null,
    /// Render only: what to produce, resolved from `-f`, the output's
    /// extension and the engine.
    format: Format = .svg,
    /// Render only: which path produces the format.
    engine: Engine = .native,
    /// `show` only.
    json: bool = false,
    /// No output on errors; warnings count as errors.
    strict: bool = false,
    /// Render only: draw just this zone.
    zone: ?[]const u8 = null,
    verbosity: Verbosity = .brief,
    color: bool = true,
    watch: bool = false,
    /// Render only: render to a temporary page and open it.
    preview: bool = false,

    pub const Action = enum { render, check, show };
    pub const Stage = enum { tokens, cst, ir };
    pub const Verbosity = enum { quiet, brief, full };

    pub const Format = enum {
        svg,
        png,
        pdf,
        dot,
        tex,
        /// The compilation itself, from fab-core: no engine is involved.
        json,

        /// The format a path's extension names, if any.
        pub fn ofPath(path: []const u8) ?Format {
            const ext = std.fs.path.extension(path);
            if (ext.len < 2) return null;
            return std.meta.stringToEnum(Format, ext[1..]);
        }

        /// The engine a format implies when none is given: a source format
        /// names its tool.
        fn impliedEngine(f: Format) Engine {
            return switch (f) {
                .dot => .graphviz,
                .tex => .latex,
                else => .native,
            };
        }

        /// Which engines can produce this format, as a hint.
        fn hint(f: Format) []const u8 {
            return switch (f) {
                .svg => "svg comes from `-e native` or `-e graphviz`",
                .png => "png comes from `-e graphviz`",
                .pdf => "pdf comes from `-e graphviz` or `-e latex`",
                .dot => "dot comes from `-e graphviz`",
                .tex => "tex comes from `-e latex`",
                .json => "json comes from fab-core itself; leave out `-e`",
            };
        }
    };

    /// The path from a program to a picture.
    pub const Engine = enum {
        /// fab-render's own layout, straight to SVG.
        native,
        /// fab-render writes DOT; Graphviz lays it out.
        graphviz,
        /// fab-render writes TikZ; LaTeX typesets it.
        latex,

        pub fn produces(e: Engine, f: Format) bool {
            return switch (e) {
                .native => f == .svg,
                .graphviz => f == .dot or f == .svg or f == .png or f == .pdf,
                .latex => f == .tex or f == .pdf,
            };
        }

        /// What the engine produces when no format is given.
        fn defaultFormat(e: Engine) Format {
            return switch (e) {
                .native, .graphviz => .svg,
                .latex => .pdf,
            };
        }
    };
};

pub const Parsed = union(enum) {
    command: Command,
    help,
    version,
    /// A usage error, with a one-line explanation.
    usage: Usage,
};

pub const Usage = struct {
    message: []const u8,
    /// The argument at fault, if any; printed after the message.
    argument: ?[]const u8 = null,
    /// What to do instead, if there is something better than `--help`.
    hint: ?[]const u8 = null,
};

fn usage(message: []const u8, argument: ?[]const u8) Parsed {
    return .{ .usage = .{ .message = message, .argument = argument } };
}

fn usageHint(message: []const u8, argument: ?[]const u8, hint: []const u8) Parsed {
    return .{ .usage = .{ .message = message, .argument = argument, .hint = hint } };
}

/// Parses `args`, the arguments after the program's name.
pub fn parse(args: []const []const u8) Parsed {
    if (args.len == 0) return .help;

    const first = args[0];
    var i: usize = 1;
    var c: Command = .{ .action = .render, .input = "" };
    if (std.mem.eql(u8, first, "render")) {
        c.action = .render;
    } else if (std.mem.eql(u8, first, "check")) {
        c.action = .check;
    } else if (std.mem.eql(u8, first, "show")) {
        c.action = .show;
        if (args.len < 2) return usage("`show` needs a stage: tokens, cst or ir", null);
        c.stage = std.meta.stringToEnum(Command.Stage, args[1]) orelse
            return usage("unknown stage; expected tokens, cst or ir", args[1]);
        i = 2;
    } else if (eql(first, "-h", "--help")) {
        return .help;
    } else if (std.mem.eql(u8, first, "--version")) {
        return .version;
    } else if (first.len > 1 and first[0] == '-') {
        return usage("expected a command first: render, check or show", first);
    } else {
        return usageHint("expected a command first", first, "to draw it, run `fab render <file>`");
    }

    var input: ?[]const u8 = null;
    var format: ?Command.Format = null;
    var engine: ?Command.Engine = null;
    var options_done = false;

    while (i < args.len) : (i += 1) {
        const arg = args[i];
        const is_option = !options_done and arg.len > 1 and arg[0] == '-';
        if (!is_option) {
            if (input != null) return usage("only one input file can be given", arg);
            input = arg;
            continue;
        }
        if (std.mem.eql(u8, arg, "--")) {
            options_done = true;
        } else if (eql(arg, "-h", "--help")) {
            return .help;
        } else if (std.mem.eql(u8, arg, "--version")) {
            return .version;
        } else if (eql(arg, "-o", "--output")) {
            c.output = value(args, &i) orelse return usage("missing path after", arg);
        } else if (eql(arg, "-f", "--format")) {
            const name = value(args, &i) orelse return usage("missing format after", arg);
            format = std.meta.stringToEnum(Command.Format, name) orelse
                return usage("unknown format; expected svg, png, pdf, dot, tex or json", name);
        } else if (eql(arg, "-e", "--engine")) {
            const name = value(args, &i) orelse return usage("missing engine after", arg);
            engine = std.meta.stringToEnum(Command.Engine, name) orelse
                return usage("unknown engine; expected native, graphviz or latex", name);
        } else if (std.mem.eql(u8, arg, "--json")) {
            c.json = true;
        } else if (std.mem.eql(u8, arg, "--strict")) {
            c.strict = true;
        } else if (std.mem.eql(u8, arg, "--zone")) {
            c.zone = value(args, &i) orelse return usage("missing zone name after", arg);
        } else if (std.mem.eql(u8, arg, "--verbosity")) {
            const name = value(args, &i) orelse return usage("missing verbosity after", arg);
            c.verbosity = std.meta.stringToEnum(Command.Verbosity, name) orelse
                return usage("unknown verbosity; expected quiet, brief or full", name);
        } else if (std.mem.eql(u8, arg, "--no-color")) {
            c.color = false;
        } else if (std.mem.eql(u8, arg, "--watch")) {
            c.watch = true;
        } else if (std.mem.eql(u8, arg, "--preview")) {
            c.preview = true;
        } else {
            return usage("unknown option", arg);
        }
    }

    c.input = input orelse return usage("no input file; use `-` for standard input", null);

    // Options that mean nothing for the chosen command.
    if (c.action != .render) {
        if (c.output != null) return usage("`-o` applies to `render` only", null);
        if (format != null) return usage("`-f` applies to `render` only", null);
        if (engine != null) return usage("`-e` applies to `render` only", null);
        if (c.zone != null) return usage("`--zone` applies to `render` only", null);
        if (c.preview) return usage("`--preview` applies to `render` only", null);
    }
    if (c.action != .show and c.json) return usageHint("`--json` applies to `show` only", null, "render with `-f json` instead");
    if (c.watch and std.mem.eql(u8, c.input, "-")) return usage("`--watch` needs a file, not standard input", null);
    if (c.preview and c.output != null and std.mem.eql(u8, c.output.?, "-")) {
        return usage("`--preview` writes a page to open; it can't go to standard output", null);
    }
    if (c.action != .render) return .{ .command = c };

    // The format: `-f`, else the output's extension.
    if (format == null) {
        if (c.output) |out| {
            if (!std.mem.eql(u8, out, "-")) {
                format = Command.Format.ofPath(out) orelse
                    return usageHint("can't tell the format from the extension", out, "add `-f`");
            }
        }
    }

    // JSON is the compilation itself: no engine is involved.
    if (format == .json) {
        if (engine != null) return usageHint("`-f json` doesn't use an engine", null, Command.Format.json.hint());
        c.format = .json;
        return .{ .command = c };
    }

    // The engine: `-e`, else the one the format implies, else native. Then
    // the format: as asked, else the engine's default.
    c.engine = engine orelse if (format) |f| f.impliedEngine() else .native;
    c.format = format orelse c.engine.defaultFormat();
    if (!c.engine.produces(c.format)) {
        return usageHint(switch (c.engine) {
            .native => "the native engine can't produce this format",
            .graphviz => "the graphviz engine can't produce this format",
            .latex => "the latex engine can't produce this format",
        }, @tagName(c.format), c.format.hint());
    }
    return .{ .command = c };
}

fn eql(arg: []const u8, short: []const u8, long: []const u8) bool {
    return std.mem.eql(u8, arg, short) or std.mem.eql(u8, arg, long);
}

/// The value after an option, advancing `i` past it.
fn value(args: []const []const u8, i: *usize) ?[]const u8 {
    if (i.* + 1 >= args.len) return null;
    i.* += 1;
    return args[i.*];
}

pub const help =
    \\fab: draw diagrams from fAB programs
    \\
    \\Usage:
    \\  fab render <file> [options]             draw the diagram
    \\  fab check <file> [options]              report problems only
    \\  fab show tokens|cst|ir <file> [options] show a stage of compilation
    \\
    \\<file> is a path, or `-` for standard input.
    \\
    \\Rendering:
    \\  -e, --engine <name>    native, graphviz or latex (default: native)
    \\  -f, --format <name>    native:   svg
    \\                         graphviz: dot, svg, png, pdf
    \\                         latex:    tex, pdf
    \\                         json:     the compilation, from any engine
    \\                         (default: from the output's extension, or
    \\                         the engine's own: svg, or pdf for latex)
    \\  -o, --output <path>    where to write; `-` for standard output
    \\                         (default: next to the input)
    \\  --preview              render to a temporary page and open it
    \\  --zone <name>          draw only this zone
    \\
    \\  `-f dot` implies `-e graphviz`, and `-f tex` implies `-e latex`.
    \\
    \\Showing:
    \\  --json                 machine-readable output (tokens and ir)
    \\
    \\Everywhere:
    \\  --strict               no output when there are errors, and
    \\                         warnings count as errors
    \\  --watch                run again whenever the file changes
    \\  --verbosity <level>    quiet, brief or full (default: brief)
    \\  --no-color             plain text output
    \\  -h, --help             show this help
    \\  --version              show the version
    \\
    \\Exit codes: 0 no errors, 1 the program has errors, 2 the command
    \\could not run (bad usage, unreadable file).
    \\
;

test {
    _ = @import("args.test.zig");
}
