const std = @import("std");

const Day = enum {
    MONDAY,
    TUESDAY,
    WEDNESDAY,

    pub fn isMonday(self: Day) bool {
        return self == Day.MONDAY;
    }
};

const apiErr = error{ InvalidPayload, NOT_FOUND, BAD_REQUEST };

const UserInpu = union { name: []const u8, age: i16, wealthy: bool };

pub fn main(init: std.process.Init) !void {
    const number: i32 = 657798;
    const items: [3][]const u8 = .{ "name", "zig", "master" };

    switch (number) {
        657748 => std.debug.print("bigger than", .{}),
        else => std.debug.print("smaller than", .{}),
    }

    for (items) |item| {
        std.debug.print("{s}\n", .{item});
    }

    const day: Day = .TUESDAY;

    std.debug.print("The day is {s}\n", .{@tagName(day)});

    const info = @typeInfo(Day);
    const enumInfo = info.@"enum";

    std.debug.print("Enum tag type: {s}\n", .{@typeName(enumInfo.tag_type)});

    inline for (enumInfo.field_names) |field| {
        std.debug.print("Field: {s}\n", .{field});
    }

    switch (day) {
        .MONDAY => std.debug.print("Its that day\n", .{}),
        else => std.debug.print("Some other day\n", .{}),
    }

    const num = std.fmt.parseFloat(f16, "12.222") catch 0.0;
    std.debug.print("FLoat is equal to {d} \n", .{num});

    var nums = [_]i32{ 1, 2, 3, 4, 4, 6, 7, 8 };

    for (&nums, 0..) |*item, i| {
        item.* = @intCast(i);
    }

    std.debug.print("IDX 7 is {d}\n", .{nums[7]});

    const Point = struct { x: u8 = 10, y: u8, z: u8 };
    const PointData = Point{ .y = 4, .z = 3 };

    const T = @TypeOf(PointData);
    const pointInfo = @typeInfo(T).@"struct";

    std.debug.print("The point is:\n", .{});
    inline for (pointInfo.field_names) |field| {
        const value = @field(PointData, field);
        std.debug.print("{s}: {d}\n", .{ field, value });
    }

    var slots = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    const slotsPtr = &slots[3];

    slotsPtr.* += 6;
    std.debug.print("Slot idx 3 is now {d} \n", .{slotsPtr.*});

    var alloc: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{});
    defer std.debug.assert(alloc.deinit() == 0);

    const allocator = alloc.allocator();
    const ptr = try allocator.dupe(u8, "Hello birdie");
    defer allocator.free(ptr);

    std.debug.print("Length of PTR is {d}\n", .{ptr.len});

    var mapHash = std.StringHashMap([*]const u8).init(std.heap.page_allocator);
    defer mapHash.deinit();

    try mapHash.put("name", "Edwin Karimi");
    try mapHash.put("place", "Singapore");
    try mapHash.put("status", "Billionaire");

    try std.testing.expect(mapHash.contains("name"));

    // Files
    const io = init.io;
    var myFile = try std.Io.Dir.cwd().openFile(io, "book.pdf", .{ .mode = .read_only });

    defer myFile.close(io);

    var readBuf: [4096]u8 = undefined;

    while (true) {
        const chunk = myFile.readStreaming(io, &.{readBuf[0..]}) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        std.debug.print("{d}\n", .{chunk});
    }

    // Buffered reader
    //     var buffer: [4096]u8 = undefined;
    //     var file_reader = myFile.reader(io, &buffer);
    //     const reader = &file_reader.interface;
    //
    //     while (true) {
    //         const line = reader.takeDelimiter('\n') catch |err| switch (err) {
    //             error.ReadFailed => break,
    //             error.StreamTooLong => break,
    //         };
    //
    //         if (line) |l| {
    //             std.debug.print("Buffered read {s}", .{l});
    //         }
    //     }

    // mmap dark magic
    const sampleFile = try std.Io.Dir.cwd().openFile(io, "/tmp/f.txt", .{ .mode = .read_write });

    const sampleFileStat = std.Io.Dir.cwd().statFile(io, "/tmp/f.txt", .{}) catch |err| {
        std.debug.print("getting file stats failed", .{});
        return err;
    };

    const fileData = std.posix.mmap(null, sampleFileStat.size, .{ .WRITE = true }, .{ .TYPE = .SHARED }, sampleFile.handle, 0) catch |err| {
        std.debug.print("mapping file failed", .{});
        return err;
    };
    defer std.posix.munmap(fileData);

    std.debug.print("Length of mapped file is {d} \n", .{fileData.len});
    fileData[12] = 'Z';

    std.Thread.spawn(.{}, comptime function: anytype, args: anytype)
}
