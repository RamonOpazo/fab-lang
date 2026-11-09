//! Byte offsets as UTF-16 offsets and Language Server Protocol positions:
//! lines and characters from 0, characters in UTF-16 code units, lines
//! ending at "\n". Used by the JSON output and the language server.

const std = @import("std");

const Lines = @This();

source: []const u8,
/// The byte offset where each line starts.
starts: []const u32,
/// The UTF-16 offset where each line starts.
utf16_starts: []const u32,

pub const Position = struct { line: u32, character: u32 };

pub fn init(gpa: std.mem.Allocator, source: []const u8) error{OutOfMemory}!Lines {
    var starts: std.ArrayList(u32) = .empty;
    defer starts.deinit(gpa);
    var utf16_starts: std.ArrayList(u32) = .empty;
    defer utf16_starts.deinit(gpa);

    try starts.append(gpa, 0);
    try utf16_starts.append(gpa, 0);
    var units: u32 = 0;
    var i: usize = 0;
    while (i < source.len) {
        const step, const width = unitAt(source, i);
        i += step;
        units += width;
        if (source[i - step] == '\n') {
            try starts.append(gpa, @intCast(i));
            try utf16_starts.append(gpa, units);
        }
    }
    const owned_starts = try starts.toOwnedSlice(gpa);
    errdefer gpa.free(owned_starts);
    return .{ .source = source, .starts = owned_starts, .utf16_starts = try utf16_starts.toOwnedSlice(gpa) };
}

pub fn deinit(lines: *Lines, gpa: std.mem.Allocator) void {
    gpa.free(lines.starts);
    gpa.free(lines.utf16_starts);
    lines.* = undefined;
}

/// The line and UTF-16 character of a byte offset.
pub fn position(lines: *const Lines, offset: u32) Position {
    const line = lines.lineOf(offset);
    return .{ .line = line, .character = lines.unitsBetween(lines.starts[line], offset) };
}

/// The UTF-16 offset of a byte offset.
pub fn utf16(lines: *const Lines, offset: u32) u32 {
    const line = lines.lineOf(offset);
    return lines.utf16_starts[line] + lines.unitsBetween(lines.starts[line], offset);
}

fn lineOf(lines: *const Lines, offset: u32) u32 {
    // The last line starting at or before `offset`.
    var lo: usize = 0;
    var hi: usize = lines.starts.len;
    while (hi - lo > 1) {
        const mid = (lo + hi) / 2;
        if (lines.starts[mid] <= offset) lo = mid else hi = mid;
    }
    return @intCast(lo);
}

fn unitsBetween(lines: *const Lines, from: u32, to: u32) u32 {
    var units: u32 = 0;
    var i: usize = from;
    while (i < to) {
        const step, const width = unitAt(lines.source, i);
        i += step;
        units += width;
    }
    return units;
}

/// The bytes and UTF-16 units of the character at `i`. An invalid byte
/// counts as one byte and one unit, as U+FFFD does.
fn unitAt(source: []const u8, i: usize) struct { usize, u32 } {
    const len = utf8Length(source[i..]);
    if (len == 0) return .{ 1, 1 };
    return .{ len, if (len == 4) 2 else 1 };
}

/// The length of the valid UTF-8 sequence at the start of `s`, or 0.
pub fn utf8Length(s: []const u8) usize {
    const len = std.unicode.utf8ByteSequenceLength(s[0]) catch return 0;
    if (len > s.len) return 0;
    _ = std.unicode.utf8Decode(s[0..len]) catch return 0;
    return len;
}
