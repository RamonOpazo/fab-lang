//! The fab command: the only part of fAB that does I/O.
//!
//! It reads the arguments and the input, runs the command, writes the result
//! (through Graphviz, for its formats), and with `--watch` does it again
//! whenever the input changes. Everything else comes from the pure module
//! `fab_cli` (root.zig); this file imports nothing else of its own.

const std = @import("std");
const Io = std.Io;
const fab_cli = @import("fab_cli");
const Args = fab_cli.Args;
const run = fab_cli.run;

const version = "0.0.0";

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(arena);

    var out_buffer: [4096]u8 = undefined;
    var stdout = Io.File.stdout().writer(io, &out_buffer);
    var err_buffer: [4096]u8 = undefined;
    var stderr = Io.File.stderr().writer(io, &err_buffer);

    const code = dispatch(init.gpa, io, arena, argv[1..], &stdout.interface, &stderr.interface);
    stdout.interface.flush() catch {};
    stderr.interface.flush() catch {};
    std.process.exit(code);
}

fn dispatch(gpa: std.mem.Allocator, io: Io, arena: std.mem.Allocator, args: []const []const u8, out: *Io.Writer, err: *Io.Writer) u8 {
    const command = switch (Args.parse(args)) {
        .command => |c| c,
        .help => {
            out.writeAll(Args.help) catch {};
            return 0;
        },
        .version => {
            out.print(
                \\fab {s}
                \\Copyright (C) 2026 Ramón Opazo
                \\License AGPL-3.0-or-later <https://www.gnu.org/licenses/agpl-3.0.html>
                \\This is free software: you are free to change and redistribute it.
                \\There is NO WARRANTY, to the extent permitted by law.
                \\
            , .{version}) catch {};
            return 0;
        },
        .usage => |u| {
            if (u.argument) |a| err.print("fab: {s}: {s}\n", .{ u.message, a }) catch {} else err.print("fab: {s}\n", .{u.message}) catch {};
            if (u.hint) |h| err.print("hint: {s}\n", .{h}) catch {} else err.writeAll("Run `fab --help` for usage.\n") catch {};
            return 2;
        },
    };
    if (!command.watch) return once(gpa, io, arena, command, out, err);
    return watch(gpa, io, arena, command, out, err);
}

/// Runs the command once, start to finish.
fn once(gpa: std.mem.Allocator, io: Io, arena: std.mem.Allocator, command: Args.Command, out: *Io.Writer, err: *Io.Writer) u8 {
    return attempt(gpa, io, arena, command, out, err) catch |e| {
        err.print("fab: {s}\n", .{@errorName(e)}) catch {};
        return 2;
    };
}

fn attempt(gpa: std.mem.Allocator, io: Io, arena: std.mem.Allocator, command: Args.Command, out: *Io.Writer, err: *Io.Writer) !u8 {
    const source = readInput(gpa, io, command.input) catch |e| {
        try err.print("fab: cannot read {s}: {s}\n", .{ command.input, @errorName(e) });
        return 2;
    };
    defer gpa.free(source);
    const label = if (std.mem.eql(u8, command.input, "-")) "<stdin>" else command.input;

    if (command.action != .render) {
        const outcome = try run.run(gpa, command, source, label, out, err);
        return outcome.code;
    }

    // Rendering goes to a buffer first, so that nothing is written when
    // `--strict` refuses a program with errors.
    var rendered: Io.Writer.Allocating = .init(gpa);
    defer rendered.deinit();
    const outcome = try run.run(gpa, command, source, label, &rendered.writer, err);
    if (!outcome.produced) return outcome.code;

    const path = try run.outputPath(arena, command);
    if (outcome.graphviz) |format| {
        if (!try graphviz(gpa, io, format, rendered.written(), path, out, err)) return 2;
    } else if (path) |p| {
        Io.Dir.cwd().writeFile(io, .{ .sub_path = p, .data = rendered.written() }) catch |e| {
            try err.print("fab: cannot write {s}: {s}\n", .{ p, @errorName(e) });
            return 2;
        };
    } else {
        try out.writeAll(rendered.written());
    }
    return outcome.code;
}

/// Runs `dot -T<format>` on `dot_source`, writing to `path`, or to standard
/// output if null. Returns false, having said why, if Graphviz is missing or
/// fails; a partly written file is then removed.
fn graphviz(gpa: std.mem.Allocator, io: Io, format: Args.Command.Format, dot_source: []const u8, path: ?[]const u8, out: *Io.Writer, err: *Io.Writer) !bool {
    var flag_buffer: [8]u8 = undefined;
    const flag = try std.fmt.bufPrint(&flag_buffer, "-T{s}", .{@tagName(format)});

    // Graphviz writes straight to the destination: the file, or our own
    // standard output, flushed first so the two never interleave.
    const file: ?Io.File = if (path) |p| Io.Dir.cwd().createFile(io, p, .{}) catch |e| {
        try err.print("fab: cannot write {s}: {s}\n", .{ p, @errorName(e) });
        return false;
    } else null;
    defer if (file) |f| f.close(io);
    try out.flush();

    var child = std.process.spawn(io, .{
        .argv = &.{ "dot", flag },
        .stdin = .pipe,
        .stdout = if (file) |f| .{ .file = f } else .inherit,
        .stderr = .pipe,
    }) catch |e| {
        try err.print("fab: cannot start Graphviz: {s}\n", .{@errorName(e)});
        try err.writeAll("hint: install Graphviz (https://graphviz.org/download), or write DOT with `-f dot`\n");
        discard(io, path);
        return false;
    };
    defer child.kill(io);

    // The DOT goes in whole, then stdin closes so `dot` starts drawing. If
    // `dot` dies early the write fails, and its exit status says why.
    child.stdin.?.writeStreamingAll(io, dot_source) catch {};
    child.stdin.?.close(io);
    child.stdin = null;
    var buffer: [1024]u8 = undefined;
    var complaints = child.stderr.?.readerStreaming(io, &buffer);
    const said = try complaints.interface.allocRemaining(gpa, .limited(64 * 1024));
    defer gpa.free(said);
    const term = try child.wait(io);

    if (term.success()) {
        // Graphviz warnings are worth seeing, but the drawing exists.
        if (said.len > 0) try err.print("graphviz: {s}", .{said});
        return true;
    }
    try err.print("fab: Graphviz {f}\n", .{term});
    if (said.len > 0) try err.print("graphviz: {s}", .{said});
    discard(io, path);
    return false;
}

/// Removes a partly written output.
fn discard(io: Io, path: ?[]const u8) void {
    if (path) |p| Io.Dir.cwd().deleteFile(io, p) catch {};
}

fn readInput(gpa: std.mem.Allocator, io: Io, path: []const u8) ![]u8 {
    if (std.mem.eql(u8, path, "-")) {
        var buffer: [4096]u8 = undefined;
        var reader = Io.File.stdin().readerStreaming(io, &buffer);
        return reader.interface.allocRemaining(gpa, .unlimited);
    }
    return Io.Dir.cwd().readFileAlloc(io, path, gpa, .unlimited);
}

/// Runs the command, then again each time the input file changes, until the
/// process is interrupted.
fn watch(gpa: std.mem.Allocator, io: Io, arena: std.mem.Allocator, command: Args.Command, out: *Io.Writer, err: *Io.Writer) u8 {
    var last = modified(io, command.input);
    while (true) {
        if (command.color) out.writeAll("\x1b[2J\x1b[H") catch {}; // clear the screen
        _ = once(gpa, io, arena, command, out, err);
        err.print("watching {s}; press Ctrl-C to stop\n", .{command.input}) catch {};
        out.flush() catch {};
        err.flush() catch {};

        while (true) {
            io.sleep(.fromMilliseconds(250), .awake) catch return 0;
            const now = modified(io, command.input);
            if (now != last) {
                last = now;
                break;
            }
        }
        if (!command.color) err.writeAll("\n--- changed ---\n\n") catch {};
    }
}

/// The input's modification time, or null if it can't be read right now
/// (editors often replace a file while saving it).
fn modified(io: Io, path: []const u8) ?i96 {
    const stat = Io.Dir.cwd().statFile(io, path, .{}) catch return null;
    return stat.mtime.nanoseconds;
}
