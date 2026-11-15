const std = @import("std");
const Io = std.Io;

const FileIndex = @import("file_index.zig").FileIndex;

pub fn main(init: std.process.Init) !void {
    var filesIdx = try FileIndex.init(init.gpa);
    defer filesIdx.deinit();

    const fileName = "f.txt";
    const file = std.Io.Dir.cwd().openFile(init.io, fileName, .{ .mode = .read_only }) catch |err| {
        return err;
    };

    var pathBuf: [std.Io.Dir.max_path_bytes]u8 = undefined;

    const bytesRead = try file.realPath(init.io, &pathBuf);
    const fileStat = try file.stat(init.io);

    try filesIdx.insert(pathBuf[0..bytesRead], fileStat);

    const idxLen = filesIdx.count();
    const fileInIdx = filesIdx.getByPath(pathBuf[0..bytesRead]);

    std.debug.print("idx initialized with files: {d}\n", .{idxLen});
    std.debug.print("idx file path: {s}\n", .{fileInIdx.?.path});
}
