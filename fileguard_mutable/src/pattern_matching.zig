const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @import("c");

pub fn matches(pattern: []const u8, name: []const u8) !bool {
    const nameC = try std.posix.toPosixPath(name);
    const patternC = try std.posix.toPosixPath(pattern);
    return c.fnmatch(&patternC, &nameC, 0) == 0;
}

pub fn matchesAnyPattern(patterns: []const []const u8, name: []const u8) !bool {
    for (patterns) |pattern| {
        if (try matches(pattern, name)) return true;
    }

    return false;
}
