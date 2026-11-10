const std = @import("std");
const testing = std.testing;
const version = @import("version.zig");
const Error = @import("analyse/Error.zig");

test "a version is X.Y.Z, and a dev build says so" {
    var parts = std.mem.splitScalar(u8, version.string, '.');
    for (0..3) |_| {
        const part = parts.next().?;
        const digits = std.mem.indexOfNone(u8, part, "0123456789") orelse part.len;
        try testing.expect(digits > 0);
    }
    try testing.expectEqual(!version.stable, std.mem.indexOf(u8, version.string, "-dev") != null);
}

test "incomplete exactly while a tag is unsupported (release.md §2)" {
    try testing.expectEqual(Error.incomplete, std.mem.endsWith(u8, version.string, ".incomplete"));
    try testing.expect(!(version.stable and Error.incomplete));
}
