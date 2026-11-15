const std = @import("std");
const Io = std.Io;

const FileError = error{
    InvalidPath,
};

const FileIndex = @import("file_index.zig").FileIndex;

pub fn main(init: std.process.Init) !void {
    var filesIdx = try FileIndex.init(init.gpa);
    defer filesIdx.deinit();

    const fileName = "/tmp/f.txt";
    if (!std.Io.Dir.path.isAbsolute(fileName)) return FileError.InvalidPath;

    const fileStat = try std.Io.Dir.cwd().statFile(init.io, fileName, .{ .follow_symlinks = true });

    try filesIdx.insert(init.io, fileName, fileStat);

    const idxLen = try filesIdx.count(init.io);
    const fileInIdx = try filesIdx.getByPath(init.io, init.gpa, fileName);

    if (fileInIdx) |f| {
        var snapshot = f;
        defer snapshot.deinit();
        std.debug.print("idx initialized with files: {d}\n", .{idxLen});
        std.debug.print("idx file path: {s}\n", .{snapshot.path});
    }
}
