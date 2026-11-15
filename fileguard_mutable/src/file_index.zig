const std = @import("std");

const Allocator = std.mem.Allocator;
const SHA256 = std.crypto.hash.sha2.Sha256;
const FileMetadata = @import("file_metadata.zig").FileMetadata;
const FileMetadataSnapshot = @import("file_metadata.zig").FileMetadataSnapshot;

const errors = error{ PathAlreadyExists, InodeAlreadyExists, FileNotFound, InodeChanged };

pub const FileIndex = struct {
    files: std.StringHashMap(*FileMetadata),
    inodes: std.AutoHashMap(u64, *FileMetadata),
    allocator: Allocator,
    mux: std.Io.RwLock,

    pub fn init(allocator: std.mem.Allocator) !FileIndex {
        const str_hashmap = std.StringHashMap(*FileMetadata).init(allocator);
        const in_hashmap = std.AutoHashMap(u64, *FileMetadata).init(allocator);
        const mux: std.Io.RwLock = .init;

        const file_index = FileIndex{ .files = str_hashmap, .inodes = in_hashmap, .allocator = allocator, .mux = mux };
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

    pub fn insert(self: *FileIndex, io: std.Io, path: []const u8, stat: std.Io.File.Stat) !void {
        try self.mux.lock(io);
        defer self.mux.unlock(io);

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

    pub fn count(self: *FileIndex, io: std.Io) !usize {
        try self.mux.lockShared(io);
        defer self.mux.unlockShared(io);

        return self.files.count();
    }

    pub fn getByPath(self: *FileIndex, io: std.Io, allocator: Allocator, path: []const u8) !?FileMetadataSnapshot {
        try self.mux.lockShared(io);
        defer self.mux.unlockShared(io);

        const record = self.files.get(path) orelse return null;
        return try file_metadata_snapshot(allocator, record);
    }

    pub fn getByInode(self: *FileIndex, io: std.Io, allocator: Allocator, inode: u64) !?FileMetadataSnapshot {
        try self.mux.lockShared(io);
        defer self.mux.unlockShared(io);

        const record = self.inodes.get(inode) orelse return null;
        return try file_metadata_snapshot(allocator, record);
    }

    pub fn update(self: *FileIndex, io: std.Io, path: []const u8, stat: std.Io.File.Stat) !void {
        try self.mux.lock(io);
        defer self.mux.unlock(io);

        const record = self.inodes.get(path) orelse {
            return errors.FileNotFound;
        };

        if (record.md.inode != stat.inode) {
            return errors.InodeChanged;
        }

        record.md = stat;
    }

    pub fn remove(self: *FileIndex, io: std.Io, path: []const u8) !bool {
        try self.mux.lock(io);
        defer self.mux.unlock(io);

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

    fn file_metadata_snapshot(allocator: Allocator, record: *const FileMetadata) !FileMetadataSnapshot {
        const owned_path = try allocator.dupe(u8, record.path);

        return .{
            .md = record.md,
            .path = owned_path,
            .checksum = record.checksum,
            .allocator = allocator,
        };
    }
};

fn testStat(inode: u64, size: u64) std.Io.File.Stat {
    var stat = std.mem.zeroes(std.Io.File.Stat);
    stat.inode = inode;
    stat.size = size;
    return stat;
}

test "insert, lookup and remove" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var index = try FileIndex.init(allocator);
    defer index.deinit();

    try index.insert(io, "/tmp/f.txt", testStat(42, 4096));

    try std.testing.expectEqual(
        @as(usize, 1),
        try index.count(io),
    );

    const maybe_snapshot = try index.getByPath(
        io,
        allocator,
        "/tmp/f.txt",
    );

    var snapshot = maybe_snapshot.?;
    defer snapshot.deinit();

    try std.testing.expectEqual(
        @as(u64, 4096),
        snapshot.md.size,
    );

    try std.testing.expect(
        try index.remove(io, "/tmp/f.txt"),
    );

    try std.testing.expectEqual(
        @as(usize, 0),
        try index.count(io),
    );

    // The independent snapshot remains valid.
    try std.testing.expectEqualStrings(
        "/tmp/f.txt",
        snapshot.path,
    );
}

test "snapshot survives deletion" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var index = try FileIndex.init(allocator);
    defer index.deinit();

    try index.insert(io, "book.pdf", testStat(100, 8192));

    var snapshot = (try index.getByInode(
        io,
        allocator,
        100,
    )).?;
    defer snapshot.deinit();

    _ = try index.remove(io, "book.pdf");

    // This is safe because snapshot.path is independently owned.
    try std.testing.expectEqualStrings(
        "book.pdf",
        snapshot.path,
    );
}

fn writerTask(
    io: std.Io,
    index: *FileIndex,
    id: usize,
) void {
    var buffer: [64]u8 = undefined;

    for (0..1000) |i| {
        const path = std.fmt.bufPrint(
            &buffer,
            "/tmp/worker-{d}-file-{d}",
            .{ id, i },
        ) catch unreachable;

        index.insert(
            io,
            path,
            testStat(@intCast(id * 100_000 + i + 1), 128),
        ) catch unreachable;

        const removed = index.remove(io, path) catch unreachable;
        std.debug.assert(removed);
    }
}

fn readerTask(
    io: std.Io,
    index: *FileIndex,
) void {
    for (0..5000) |_| {
        // A record may or may not exist at this instant.
        // Both outcomes are valid.
        const snapshot = index.getByPath(
            io,
            std.heap.smp_allocator,
            "/tmp/f.txt",
        ) catch unreachable;

        if (snapshot) |value| {
            var owned = value;
            owned.deinit();
        }
    }
}

test "concurrent readers and writers" {
    const io = std.testing.io;

    // Use a thread-capable allocator for shared index
    // allocations rather than assuming the testing
    // allocator is appropriate for concurrent access.
    var index = try FileIndex.init(
        std.heap.smp_allocator,
    );
    defer index.deinit();

    var group: std.Io.Group = .init;
    defer group.cancel(io);

    for (0..4) |i| {
        group.async(io, writerTask, .{ io, &index, i });
    }

    for (0..4) |_| {
        group.async(io, readerTask, .{ io, &index });
    }

    // All tasks must finish before deinit.
    try group.await(io);

    try std.testing.expectEqual(
        @as(usize, 0),
        try index.count(io),
    );
}
