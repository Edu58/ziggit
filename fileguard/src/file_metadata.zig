const std = @import("std");

const Allocator = std.mem.Allocator;
const Sha256 = std.crypto.hash.sha2.Sha256;

pub const FileMetadata = struct {
    md: std.Io.File.Stat,
    path: []const u8,
    inode: u64,
    checksum: ?[Sha256.digest_length]u8 = null,

    pub fn checksumHex(self: *const FileMetadata) ?[64]u8 {
        const digest = self.checksum orelse return null;
        return std.fmt.bytesToHex(digest, .lower);
    }
};

pub const FileMetadataCollection = struct {
    arena: std.heap.ArenaAllocator,
    records: std.ArrayList(FileMetadata) = .empty,

    pub fn init(backing_allocator: Allocator) FileMetadataCollection {
        return .{ .arena = std.heap.ArenaAllocator.init(backing_allocator) };
    }

    pub fn deinit(self: *FileMetadataCollection) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn add(self: *FileMetadataCollection, io: std.Io, path: []const u8, hash_content: bool) !void {
        const file = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_only });
        defer file.close(io);

        var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const path_len = try file.realPath(io, &path_buffer);
        const absPath = path_buffer[0..path_len];

        const md = try file.stat(io);

        const checksum: ?[Sha256.digest_length]u8 = if (hash_content) try hashFile(io, file) else null;

        var allocator = self.arena.allocator();

        try self.records.ensureUnusedCapacity(allocator, 1);

        const owned_path = try allocator.dupe(u8, absPath);

        self.records.appendAssumeCapacity(.{ .md = md, .path = owned_path, .checksum = checksum, .inode = md.inode });
    }

    pub fn all(self: *const FileMetadataCollection) []const FileMetadata {
        return self.records.items;
    }

    pub fn hashFile(io: std.Io, file: std.Io.File) ![Sha256.digest_length]u8 {
        var hasher = Sha256.init(.{});
        var buffer: [16 * 1024]u8 = undefined;

        while (true) {
            const bytes_read = file.readStreaming(io, &.{buffer[0..]}) catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };

            if (bytes_read == 0) continue;

            hasher.update(buffer[0..bytes_read]);
        }

        var digest: [Sha256.digest_length]u8 = undefined;
        hasher.final(&digest);
        return digest;
    }
};
