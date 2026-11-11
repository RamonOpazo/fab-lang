//! What other packages' tests share with fab-core's.

const std = @import("std");

/// An allocator that never resizes in place. The checker counts allocations
/// only, and whether the testing allocator can grow a list in place depends
/// on what earlier runs left free, so with in-place growth the count drifts
/// from run to run. Without it, every growth is a counted allocation.
pub const FixedInPlace = struct {
    backing: std.mem.Allocator,

    pub fn allocator(f: *FixedInPlace) std.mem.Allocator {
        return .{ .ptr = f, .vtable = &.{
            .alloc = alloc,
            .resize = std.mem.Allocator.noResize,
            .remap = std.mem.Allocator.noRemap,
            .free = free,
        } };
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const f: *FixedInPlace = @ptrCast(@alignCast(ctx));
        return f.backing.rawAlloc(len, alignment, ra);
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ra: usize) void {
        const f: *FixedInPlace = @ptrCast(@alignCast(ctx));
        f.backing.rawFree(memory, alignment, ra);
    }
};
