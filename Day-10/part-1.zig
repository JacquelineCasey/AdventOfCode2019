
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();


const Pair = struct {x: u32, y: u32};


fn reduce(a: *i32, b: *i32) !void {
    if (a.* == 0) {
        b.* = @divExact(b.*, try std.math.absInt(b.*));
    }
    else if (b.* == 0) {
        a.* = @divExact(a.*, try std.math.absInt(a.*));
    }
    else {
        const gcd = std.math.gcd(std.math.absCast(a.*), std.math.absCast(b.*));
        a.* = @divExact(a.*, @as(i32, @intCast(gcd)));
        b.* = @divExact(b.*, @as(i32, @intCast(gcd)));
    }
}   


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    const alloc = gpa.allocator();
    defer {
        const code = gpa.deinit();
        if (code == .leak) @panic("Memory leaked");
    }

    // hashmap maps coordinates to number of visible asteroids. 
    var pairs = blk: {
        const input = try std_in.readToEndAlloc(alloc, 1_000_000_000);
        defer alloc.free(input);

        var list = std.AutoHashMap(Pair, u32).init(alloc);
        errdefer list.deinit();

        var lines_iter = std.mem.splitSequence(u8, input, "\n");
        var y: u32 = 0;
        while (lines_iter.next()) |line| : (y += 1)  {
            for (line, 0..) |char, x| {
                if (char == '#') {
                    try list.put(.{.x = @intCast(x), .y = y}, 0);
                }
            }
        }

        break :blk list;
    };
    defer pairs.deinit();


    var iter_1 = pairs.keyIterator();
    while (iter_1.next()) |pair_1| {
        const x_1 = pair_1.x;
        const y_1 = pair_1.y;

        var iter_2 = pairs.keyIterator();
        next_pair: while (iter_2.next()) |pair_2| {
            const x_2 = pair_2.x;
            const y_2 = pair_2.y;

            if (x_1 == x_2 and y_1 == y_2) continue;

            var x_diff: i32 = @as(i32, @intCast(x_2)) - @as(i32, @intCast(x_1));
            var y_diff: i32 = @as(i32, @intCast(y_2)) - @as(i32, @intCast(y_1));

            try reduce(&x_diff, &y_diff);

            var x_curr = @as(i32, @intCast(x_1)) + x_diff;
            var y_curr = @as(i32, @intCast(y_1)) + y_diff;

            while (x_curr != x_2 or y_curr != y_2) : ({x_curr += x_diff; y_curr += y_diff;}) {
                if (pairs.contains(.{.x = @intCast(x_curr), .y = @intCast(y_curr)})) continue :next_pair;
            }

            // Asteroids can see each other.
            try pairs.put(pair_1.*, pairs.get(pair_1.*).? + 1);
            // Other direction will be counted later on.
        }
    }

    var max: u32 = 0;
    var val_iter = pairs.valueIterator();
    while (val_iter.next()) |val| {
        max = @max(max, val.*);
    }

    try std_out.print("{d}\n", .{max});
}
