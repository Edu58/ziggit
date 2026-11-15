const std = @import("std");

const Allocator = std.mem.Allocator;
const SHA256 = std.crypto.hash.sha2.Sha256;
const FileMetadata = @import("file_metadata.zig").FileMetadata;

const errors = error{ PathAlreadyExists, InodeAlreadyExists, FileNotFound, InodeChanged };

pub const FileIndex = struct {
    files: std.StringHashMap(*FileMetadata),
    inodes: std.AutoHashMap(u64, *FileMetadata),
    allocator: Allocator,

    pub fn init(allocator: std.mem.Allocator) !FileIndex {
        const file_index = FileIndex{ .files = std.StringHashMap(*FileMetadata).init(allocator), .inodes = std.AutoHashMap(u64, *FileMetadata).init(allocator), .allocator = allocator };
        return file_index;
    }

    pub fn deinit(self: *FileIndex) void {
        self.inodes.deinit();

        var iterator = self.files.iterator();

        while (iterator.next()) |file| {
            self.allocator.free(file.key_ptr.*);
            self.allocator.destroy(file.value_ptr.*);
        }

        self.files.deinit();

        self.* = undefined;
    }

    pub fn insert(self: *FileIndex, path: []const u8, stat: std.Io.File.Stat) !void {
        if (self.files.contains(path)) {
            return errors.PathAlreadyExists;
        }

        if (self.inodes.contains(stat.inode)) {
            return errors.InodeAlreadyExists;
        }

        try self.files.ensureTotalCapacity(1);
        try self.inodes.ensureTotalCapacity(1);

        const owned_path = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned_path);

        const record = try self.allocator.create(FileMetadata);
        errdefer self.allocator.destroy(record);

        record.* = .{
            .md = stat,
            .path = owned_path,
        };

        self.files.putAssumeCapacityNoClobber(owned_path, record);
        self.inodes.putAssumeCapacityNoClobber(stat.inode, record);
    }

    pub fn count(self: *const FileIndex) usize {
        return self.files.count();
    }

    pub fn getByPath(self: *const FileIndex, path: []const u8) ?*const FileMetadata {
        return self.files.get(path);
    }

    pub fn getByInode(self: *const FileIndex, inode: u64) ?*const FileMetadata {
        return self.inodes.get(inode);
    }

    pub fn update(self: *FileIndex, path: []const u8, stat: std.Io.File.Stat) !void {
        const record = self.files.get(path) orelse {
            return errors.FileNotFound;
        };

        if (record.md.inode != stat.inode) {
            return errors.InodeChanged;
        }

        record.md = stat;
    }

    pub fn remove(self: *FileIndex, path: []const u8) bool {
        const record = self.files.get(path) orelse {
            return false;
        };

        const inode_removed = self.inodes.remove(record.md.inode);
        std.debug.assert(inode_removed);

        const file_removed = self.files.fetchRemove(path).?;
        self.allocator.free(file_removed.key);
        self.allocator.destroy(file_removed.value);

        return true;
    }
};
