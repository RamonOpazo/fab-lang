//! The Language Server Protocol's framing: each message is a JSON body after
//! a header, `Content-Length: <bytes>\r\n\r\n`. Other header fields are
//! allowed and skipped.
//!
//! Over any reader and writer, so tests run on fixed buffers and `fab lsp`
//! on the standard streams.

const std = @import("std");
const Io = std.Io;

pub const ReadError = error{ ReadFailed, OutOfMemory, BadHeader, StreamTooLong };

/// The next message's body, owned by the caller, or null at the end of the
/// input.
pub fn read(gpa: std.mem.Allocator, r: *Io.Reader) ReadError!?[]u8 {
    var length: ?usize = null;
    while (true) {
        const line = r.takeDelimiterInclusive('\n') catch |err| switch (err) {
            error.EndOfStream => {
                // The end of the input between messages is the end.
                if (length == null) return null;
                return error.BadHeader;
            },
            error.ReadFailed => return error.ReadFailed,
            error.StreamTooLong => return error.StreamTooLong,
        };
        const field = std.mem.trimEnd(u8, line, "\r\n");
        if (field.len == 0) break; // the blank line ends the header
        const colon = std.mem.indexOfScalar(u8, field, ':') orelse return error.BadHeader;
        const name = std.mem.trim(u8, field[0..colon], " ");
        if (!std.ascii.eqlIgnoreCase(name, "Content-Length")) continue;
        length = std.fmt.parseInt(usize, std.mem.trim(u8, field[colon + 1 ..], " "), 10) catch return error.BadHeader;
    }
    const n = length orelse return error.BadHeader;
    return r.readAllocAll(gpa, n) catch |err| switch (err) {
        error.EndOfStream => error.BadHeader,
        error.ReadFailed => error.ReadFailed,
        error.OutOfMemory => error.OutOfMemory,
    };
}

/// Writes one message: its header, then `body`.
pub fn write(w: *Io.Writer, body: []const u8) Io.Writer.Error!void {
    try w.print("Content-Length: {d}\r\n\r\n", .{body.len});
    try w.writeAll(body);
}

test {
    _ = @import("transport.test.zig");
}
