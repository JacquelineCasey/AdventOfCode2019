
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();


const PatternIterator = struct {
    n: u32,
    i: u32,

    fn next(self: *PatternIterator) ?i32 {
        self.i += 1;  // Therefore we really start at 1.

        const pos = (self.i % (4 * self.n)) / self.n;

        return switch (pos) {
            0 => 0,
            1 => 1,
            2 => 0,
            3 => -1,
            else => unreachable
        };
    }
};

// Expects n to be position in an array (i.e. >= 0)
fn pattern_iterator(n: u32) PatternIterator {
    return .{.n = n + 1, .i = 0};
}


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    const alloc = gpa.allocator();
    defer {
        const code = gpa.deinit();
        if (code == .leak) @panic("Memory leaked");
    }

    const input = try std_in.readToEndAlloc(alloc, 1_000_000_000);  
    defer alloc.free(input);

    var nums = std.ArrayList(i32).init(alloc);
    defer nums.deinit();

    var next_nums = std.ArrayList(i32).init(alloc);
    defer next_nums.deinit();

    for (input) |ch| {
        try nums.append(ch - '0');
        try next_nums.append(0);
    }

    for (0..100) |_| {
        for (0..nums.items.len) |i| {
            next_nums.items[i] = 0;

            var iter = pattern_iterator(@intCast(i));
            for (0..nums.items.len) |j| {
                next_nums.items[i] += iter.next().? * nums.items[j];
            }

            next_nums.items[i] = try std.math.absInt(@rem(next_nums.items[i], 10));
        }

        var tmp = nums;
        nums = next_nums;
        next_nums = tmp;
    }

    for (0..8) |i| {
        try std_out.print("{d}", .{nums.items[i]});
    }

    try std_out.print("\n", .{});
}
