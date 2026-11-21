const std = @import("std");
const Allocator = std.mem.Allocator;
const Sha256 = std.crypto.hash.sha2.Sha256;

pub const FileMetadata = struct {
    md: std.Io.File.Stat,
    path: []const u8,
    checksum: ?[Sha256.digest_length]u8 = null,

    pub fn checksumHex(self: *const FileMetadata) ?[64]u8 {
        const digest = self.checksum orelse return null;
        return std.fmt.bytesToHex(digest, .lower);
    }
};

pub const FileMetadataSnapshot = struct {
    md: std.Io.File.Stat,
    path: []const u8,
    checksum: ?[Sha256.digest_length]u8 = null,
    allocator: Allocator,

    pub fn deinit(self: *FileMetadataSnapshot) void {
        self.allocator.free(self.path);
        self.* = undefined;
    }
};

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
