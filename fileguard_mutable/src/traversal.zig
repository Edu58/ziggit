const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const PatternMatching = @import("pattern_matching.zig");

pub const TraversalConfig = struct {
    max_depth: ?usize = null,
    include_patters: []const []const u8 = &.{"*"},
    exclude_patters: []const []const u8 = &.{},
    hash_content: bool = false,
    follow_symlinks: bool = false,
};

pub const TraversalStats = struct {
    files_indexed: usize = 0,
    files_skipped: usize = 0,
    directories_entered: usize = 0,
};

pub fn traverse(io: Io, allocator: Allocator, root_path: []const u8, config: TraversalConfig, context: anytype, comptime visit: anytype) !TraversalStats {
    if (config.follow_symlinks) {
        return error.SymlinkFollowingNotImplemented;
    }

    const root = try Io.Dir.cwd().openDir(io, root_path, .{ .iterate = true, .follow_symlinks = false });
    defer root.close(io);

    var walker = try root.walkSelectively(allocator);
    defer walker.deinit();

    var stats = TraversalStats{};

    while (try walker.next(io)) |entry| {
        const depth = entry.depth();

        std.debug.print("Processing Entry name: {s}, kind: ${t}, depth: {d} \n", .{ entry.basename, entry.kind, depth });

        if (config.max_depth) |max_depth| {
            if (depth > max_depth) {
                continue;
            }
        }

        const exclusions_match = try PatternMatching.matchesAnyPattern(config.exclude_patters, entry.basename);

        if (exclusions_match) {
            if (entry.kind != .directory) {
                stats.files_skipped += 1;
            }

            continue;
        }

        switch (entry.kind) {
            .directory => {
                if (config.max_depth) |max_depth| {
                    if (depth >= max_depth) continue;
                }

                walker.enter(io, entry) catch |err| {
                    std.debug.print("ERROR entering dir - {s}", .{@errorName(err)});
                    continue;
                };

                stats.directories_entered += 1;
            },

            .file => {
                const inclusions_match = try PatternMatching.matchesAnyPattern(config.include_patters, entry.basename);
                if (!inclusions_match) {
                    stats.files_skipped += 1;
                    continue;
                }

                const full_path = try allocator.print("{s}/{s}", .{ root_path, entry.path });
                defer allocator.free(full_path);

                try visit(context, io, full_path, config.hash_content);
                stats.files_indexed += 1;
            },

            .sym_link => {
                if (config.follow_symlinks) {
                    var link_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
                    const bytes_read = try std.Io.Dir.cwd().readLink(io, entry.path, &link_buffer);
                    const resolved_path = try std.Io.Dir.path.resolveAlloc(allocator, &.{ root_path, link_buffer[0..bytes_read] });
                    defer allocator.free(resolved_path);

                    const inclusions_match = try PatternMatching.matchesAnyPattern(config.include_patters, std.Io.Dir.path.basename(resolved_path));

                    if (!inclusions_match) {
                        stats.files_skipped += 1;
                        continue;
                    }

                    try visit(context, io, resolved_path, config.hash_content);
                    stats.files_indexed += 1;
                }
            },

            else => {
                stats.files_skipped += 1;
            },
        }
    }

    return stats;
}
