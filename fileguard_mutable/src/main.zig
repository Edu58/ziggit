const std = @import("std");
const Io = std.Io;

const FileIndex = @import("file_index.zig").FileIndex;
const Traversal = @import("traversal.zig");
const Watcher = @import("watcher.zig").Watcher;

const FileError = error{
    InvalidPath,
};

pub fn visit(fileIdx: *FileIndex, io: Io, full_path: []const u8, hashFile: bool) !void {
    const fileStat = try Io.Dir.cwd().statFile(io, full_path, .{ .follow_symlinks = false });
    try fileIdx.insert(io, full_path, fileStat, hashFile);
}

pub fn main(init: std.process.Init) !void {
    const config = Traversal.TraversalConfig{
        .max_depth = 10,
        .include_patters = &.{"*"},
        .exclude_patters = &.{ ".env", "*.env", "secret", "node_modules", ".git", ".gitignore" },
        .hash_content = true,
    };

    var filesIdx = try FileIndex.init(init.gpa);
    defer filesIdx.deinit();

    var watcher = try Watcher.init(init.gpa, config);
    defer watcher.deinit();

    const root_wd = try watcher.addWatch("/home/ed/Dev/ziggit/fileguard");
    const src_wd = try watcher.addWatch("/home/ed/Dev/ziggit/fileguard/src");
    const helloz_wd = try watcher.addWatch("/home/ed/Dev/ziggit/helloz");

    std.debug.print(
        "Registered watches: root={d}, src={d}, config={d}\n",
        .{ root_wd, src_wd, helloz_wd },
    );

    try watcher.run();
}
