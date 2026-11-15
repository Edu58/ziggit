const std = @import("std");

const FileMetadata = @import("file_metadata.zig").FileMetadata;
const FileMetadataCollection = @import("file_metadata.zig").FileMetadataCollection;

pub const FileIndex = struct {
    files: std.StringHashMap(usize),
    inodes: std.AutoHashMap(u64, usize),
    collection: *const FileMetadataCollection,

    pub fn init(allocator: std.mem.Allocator, collection: *const FileMetadataCollection) !FileIndex {
        var self = FileIndex{ .files = std.StringHashMap(usize).init(allocator), .inodes = std.AutoHashMap(u64, usize).init(allocator), .collection = collection };
        errdefer self.deinit();

        const records = collection.all();

        try self.files.ensureTotalCapacity(@intCast(records.len));

        try self.inodes.ensureTotalCapacity(@intCast(records.len));

        for (records, 0..) |record, idx| {
            try self.files.put(record.path, idx);
            try self.inodes.put(record.inode, idx);
        }

        return self;
    }

    pub fn deinit(self: *FileIndex) void {
        self.files.deinit();
        self.inodes.deinit();

        self.* = undefined;
    }

    pub fn getByPath(self: *const FileIndex, path: *const []u8) ?*const FileMetadata {
        const idx = self.files.get(path) orelse return null;
        return &self.collection.all()[idx];
    }

    pub fn getByInode(self: *const FileIndex, inode: u64) ?*const FileMetadata {
        const idx = self.inodes.get(inode) orelse return null;
        return &self.collection.all()[idx];
    }
};
