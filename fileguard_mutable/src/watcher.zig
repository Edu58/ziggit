const std = @import("std");
const Allocator = std.mem.Allocator;
const linux = std.os.linux;
const Event = linux.inotify_event;

const Traversal = @import("traversal.zig");

const watch_mask: u32 =
    linux.IN.CREATE |
    linux.IN.DELETE |
    linux.IN.MODIFY |
    linux.IN.CLOSE_WRITE |
    linux.IN.ATTRIB |
    linux.IN.MOVED_FROM |
    linux.IN.MOVED_TO |
    linux.IN.DELETE_SELF |
    linux.IN.MOVE_SELF;

pub const Watch = struct {
    path: []u8,
    pending_removal: bool = false,
};

pub const Watcher = struct {
    allocator: Allocator,
    fd: linux.fd_t,
    watches: std.AutoHashMap(i32, Watch),
    needs_recon: bool = false,
    config: Traversal.TraversalConfig,

    pub fn init(allocator: Allocator, config: Traversal.TraversalConfig) !Watcher {
        const fd_result = linux.inotify_init1(linux.IN.CLOEXEC);

        switch (linux.errno(fd_result)) {
            .SUCCESS => {},
            else => return error.InotifyInitFailed,
        }

        const watches = std.AutoHashMap(i32, Watch).init(allocator);

        return .{ .allocator = allocator, .fd = @intCast(fd_result), .watches = watches, .config = config };
    }

    pub fn deinit(self: *Watcher) void {
        _ = linux.close(self.fd);

        var it = self.watches.valueIterator();

        while (it.next()) |watch| {
            self.allocator.free(watch.path);
        }

        self.watches.deinit();
        self.* = undefined;
    }

    pub fn addWatch(self: *Watcher, path: []const u8) !i32 {
        const path_z = try std.posix.toPosixPath(path);
        try self.watches.ensureUnusedCapacity(1);

        const owned_path = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned_path);

        const result = linux.inotify_add_watch(self.fd, &path_z, watch_mask);

        switch (linux.errno(result)) {
            .SUCCESS => {},
            else => return error.AddWatchFailed,
        }

        const wd: i32 = @intCast(result);

        self.watches.putAssumeCapacity(wd, .{ .path = owned_path });

        return wd;
    }

    pub fn removeWatch(self: *Watcher, wd: i32) !void {
        const watch = self.watches.get(wd) orelse return error.NotFound;

        if (watch.pending_removal) return;
        const result = linux.inotify_rm_watch(self.fd, wd);
        switch (linux.errno(result)) {
            .SUCCESS => watch.pending_removal = true,
            else => return error.RemoveWatchFailed,
        }
    }

    pub fn run(self: *Watcher) !void {
        var buffer: [64 * 1024]u8 align(@alignOf(Event)) = undefined;

        while (true) {
            const result = linux.read(self.fd, &buffer, buffer.len);
            switch (linux.errno(result)) {
                .SUCCESS => {},
                .INTR => continue,
                .AGAIN => continue,
                else => return error.InotifyReadFailed,
            }

            if (result == 0) return error.UnexepectedEndOfStream;

            try self.processBatch(buffer[0..result]);
        }
    }

    fn processBatch(self: *Watcher, bytes: []const u8) !void {
        const header_size = @sizeOf(Event);
        var offset: usize = 0;

        while (offset < bytes.len) {
            if (bytes.len - offset < header_size) return error.TruncatedEventHeader;

            const event = std.mem.bytesToValue(Event, bytes[offset..][0..header_size]);

            const name_len: usize = @intCast(event.len);
            const remaining = bytes.len - offset - header_size;

            if (name_len > remaining) return error.TruncatedEventName;

            const name_bytes = bytes[offset + header_size .. offset + header_size + name_len];

            const name: []const u8 =
                if (name_len == 0) "" else blk: {
                    const end = std.mem.findScalar(u8, name_bytes, 0) orelse return error.InvalidEventName;
                    break :blk name_bytes[0..end];
                };

            processEvent(self, event, name);
            offset += header_size + name_len;
        }
    }

    fn processEvent(
        self: *Watcher,
        event: Event,
        name: []const u8,
    ) void {
        if (event.mask & linux.IN.Q_OVERFLOW != 0) {
            self.needs_recon = true;

            std.debug.print(
                "WARNING: inotify queue overflow; " ++
                    "reconciliation required\n",
                .{},
            );
            return;
        }

        if (event.mask & linux.IN.IGNORED != 0) {
            if (self.watches.fetchRemove(event.wd)) |removed| {
                std.debug.print(
                    "Watch removed: wd={d} path={s}\n",
                    .{ event.wd, removed.value.path },
                );

                self.allocator.free(removed.value.path);
            }

            return;
        }

        const watch = self.watches.get(event.wd) orelse {
            std.debug.print(
                "Unknown watch descriptor: {d}\n",
                .{event.wd},
            );

            self.needs_recon = true;
            return;
        };

        // Event name is relative to the watched directory.
        // If empty, the event concerns the watched
        // directory itself (DELETE_SELF, MOVE_SELF, etc).
        if (name.len == 0) {
            std.debug.print(
                "Directory event: {s}, mask=0x{x}\n",
                .{ watch.path, event.mask },
            );
        } else {
            const traversalStats = try Traversal.traverse(init.io, init.gpa, path, config, &filesIdx, visit);
            std.debug.print(
                "File event: {s}/{s}, mask=0x{x}\n",
                .{ watch.path, name, event.mask },
            );
        }

        if ((event.mask & linux.IN.ISDIR) != 0) {
            std.debug.print("  is_directory=true\n", .{});
        }

        if ((event.mask & linux.IN.MOVED_FROM) != 0 or
            (event.mask & linux.IN.MOVED_TO) != 0)
        {
            std.debug.print(
                "  rename_cookie={d}\n",
                .{event.cookie},
            );
        }

        if ((event.mask & (linux.IN.DELETE_SELF | linux.IN.MOVE_SELF |
            linux.IN.UNMOUNT)) != 0)
        {
            // A watched directory was removed, renamed,
            // or its filesystem was unmounted.
            // Its registry path may no longer be valid.
            self.needs_recon = true;
        }
    }
};
