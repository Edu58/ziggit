const std = @import("std");

fn RingBuffer(comptime T: type, comptime capacity: usize) type {
    if (capacity > 5) @compileError("capacity must be < 5");

    return struct {
        items: [capacity]T = undefined,
        head: usize = 0,
        count: usize = 0,

        const Self = @This();

        fn push(self: *Self, value: T) void {
            const idx = (self.head + self.count) % capacity;
            self.items[idx] = value;

            if (self.count < capacity) {
                self.count += 1;
            } else {
                self.head = (self.head + 1) % capacity;
            }
        }

        fn latest(self: Self) ?T {
            if (self.count == 0) return null;
            return self.items[(self.head + self.count - 1) % capacity];
        }

        fn oldest(self: Self) ?T {
            if (self.count == 0) return null;
            return self.items[self.head];
        }

        fn isFull(self: Self) bool {
            return self.count == capacity;
        }

        fn get(self: Self, index: usize) ?T {
            if (index > self.count) return null;
            return self.items[(self.head + index) % capacity];
        }

        fn average(self: Self) f64 {
            if (self.count == 0) return 0;
            var sum: f64 = 0;
            for (0..self.count) |idx| {
                sum += @as(f64, @floatFromInt(self.items[(self.head + idx) % capacity]));
            }
            return sum / @as(f64, @floatFromInt(self.count));
        }
    };
}

pub fn main() void {
    var buf = RingBuffer(u32, 5){};

    buf.push(64000);
    buf.push(65200);
    buf.push(63800);
    buf.push(67100);
    buf.push(68400); // buffer is now full
    buf.push(66900); // overwrites 64000
    buf.push(69200);

    std.debug.print("Count: {d} (capacity: 5)\n", .{buf.count});
    std.debug.print("Full: {}\n", .{buf.isFull()});
    std.debug.print("Oldest: {d}\n", .{buf.oldest().?});
    std.debug.print("Latest: {d}\n", .{buf.latest().?});
    std.debug.print("5-period SMA: {d:.0}\n", .{buf.average()});

    std.debug.print("\nAll values (oldest to newest):\n", .{});
    for (0..buf.count) |i| {
        std.debug.print("  [{d}] = {d}\n", .{ i, buf.get(i).? });
    }
}
