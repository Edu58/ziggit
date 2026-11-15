const std = @import("std");
const Io = std.Io;

// const fileguard = @import("fileguard");
const fileMetadataCollection = @import("file_metadata.zig").FileMetadataCollection;
const fileIndex = @import("file_index.zig").FileIndex;

pub fn main(init: std.process.Init) !void {
    var collection = fileMetadataCollection.init(init.gpa);
    defer collection.deinit();

    try collection.add(init.io, "/tmp/f.txt", true);

    for (collection.all()) |record| {
        std.debug.print("Path is: {s}\n", .{record.path});

        if (record.checksumHex()) |checksum| {
            std.debug.print("checksum is: {s}\n", .{checksum[0..]});
        } else {
            std.debug.print("checkum not calculated\n", .{});
        }
    }

    var filesIdx = try fileIndex.init(init.gpa, &collection);
    defer filesIdx.deinit();

    const idxLen = filesIdx.files.count();
    std.debug.print("idx initialized with files: {d}\n", .{idxLen});
}
