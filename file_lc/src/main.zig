const std = @import("std");
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const file_name = "test.txt";

    std.debug.print("creating or truncating file - {s}\n", .{file_name});

    var write_file = try Io.Dir.cwd().createFile(init.io, file_name, .{ .truncate = true });
    defer write_file.close(init.io);

    std.debug.print("writing to file\n", .{});

    var buffer: [4096]u8 = undefined;
    var writer = write_file.writerStreaming(init.io, &buffer);
    var w = &writer.interface;

    for (0..10) |_| {
        try w.writeAll("away away away away away\n");
    }

    try w.flush();

    std.debug.print("finished writing.\n", .{});

    std.debug.print("reading the file\n", .{});

    const read_file = try Io.Dir.cwd().openFile(init.io, file_name, .{ .mode = .read_only });
    defer read_file.close(init.io);

    var read_buf: [4096]u8 = undefined;
    var reader = read_file.reader(init.io, &read_buf);
    var r = &reader.interface;

    var num_lines: i32 = 0;
    var chars: i32 = 0;

    while (try r.takeDelimiter('\n')) |line| {
        num_lines += 1;

        for (0..line.len) |_| chars += 1;
    }

    std.debug.print("Num of lines {d}\n", .{num_lines});
    std.debug.print("Num of chars {d}\n", .{chars});
    std.debug.print("Average chars {d}\n", .{@divExact(chars, num_lines)});
}
