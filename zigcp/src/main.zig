const std = @import("std");
const Io = std.Io;

const Args = enum {
    source,
    destination,
};

pub fn printHelp() []const u8 {
    return "Not enough arguments\n\n Usage: \n\tzig build run -- source=path destination=path\n";
}

pub fn main(init: std.process.Init) !void {
    var out_buf: [1024]u8 = undefined;
    const stdout = std.Io.File.stdout();
    var out_writer = stdout.writer(init.io, &out_buf);

    const out = &out_writer.interface;

    var args = init.minimal.args.iterate();
    _ = args.next(); // program name

    const src = args.next() orelse {
        try out.print("Error: missing source\n", .{});
        try out.print(printHelp(), .{});
        try out.flush();
        return;
    };

    const dst = args.next() orelse {
        try out.print("Error: missing destination\n", .{});
        try out.print(printHelp(), .{});
        try out.flush();

        return;
    };

    const source = try Io.Dir.cwd().openFile(init.io, src, .{ .mode = .read_only });
    defer source.close(init.io);

    const destination = try Io.Dir.cwd().createFile(init.io, dst, .{});
    defer destination.close(init.io);

    var read_buf: [8192]u8 = undefined;
    var write_buf: [8192]u8 = undefined;

    var reader = source.reader(init.io, &read_buf);
    var writer = destination.writer(init.io, &write_buf);

    const bytes_copied = try reader.interface.streamRemaining(&writer.interface);
    _ = bytes_copied;

    try writer.interface.flush();

    try out.print("file copied successful\n", .{});
    try out.flush();

    return;
}
