const std = @import("std");
const Io = std.Io;

const FileIndex = @import("file_index.zig").FileIndex;
const Traversal = @import("traversal.zig");

const FileError = error{
    InvalidPath,
};

pub fn visit(fileIdx: *FileIndex, io: Io, full_path: []const u8, hashFile: bool) !void {
    const fileStat = try Io.Dir.cwd().statFile(io, full_path, .{ .follow_symlinks = false });
    try fileIdx.insert(io, full_path, fileStat, hashFile);
}

pub fn main(init: std.process.Init) !void {
    var filesIdx = try FileIndex.init(init.gpa);
    defer filesIdx.deinit();

    const config = Traversal.TraversalConfig{
        .max_depth = 10,
        .include_patters = &.{"*"},
        .exclude_patters = &.{ ".env", "*.env", "secret", "node_modules", ".git", ".gitignore" },
        .hash_content = true,
    };

    // const root_path = "/etc";
    const root_path = "/etc";

    const traversalStats = try Traversal.traverse(init.io, init.gpa, root_path, config, &filesIdx, visit);

    const idxLen = try filesIdx.count(init.io);

    std.debug.print("traversal stats: \n indexed: {d}\n skipped: {d}\n", .{ traversalStats.files_indexed, traversalStats.files_skipped });
    std.debug.print("idx initialized with files: {d}\n", .{idxLen});
}
