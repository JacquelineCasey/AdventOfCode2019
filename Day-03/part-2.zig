
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();


const Point = struct {x: i32, y: i32};


/// Allocates a coord list
pub fn to_coord_list(line: []const u8, alloc: std.mem.Allocator) !std.ArrayList(Point) {
    var coordinates = std.ArrayList(Point).init(alloc);
 
    var x: i32 = 0;
    var y: i32 = 0;

    var iter = std.mem.splitSequence(u8, line, ",");
    while (iter.next()) |instruction| {
        const direction = instruction[0];
        const amount = try std.fmt.parseInt(usize, instruction[1..], 10);

        for (0..amount) |_| {
            switch (direction) {  // switch does work here, need default case
                'R' => x += 1,
                'L' => x -= 1,
                'U' => y += 1,
                'D' => y -= 1,
                else => unreachable  // I guess I prefer _ => ..., but this looks fine too tbh. 
                // else is overloaded a lot in Zig, we have it in for loops, while loops, here, 'orelse', and in ternary op.
            }

            try coordinates.append(Point {.x = x, .y = y});  // No name punning :(
        }
    }

    return coordinates;
}


pub fn main() !void {
    const alloc = blk: {
        var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
        break :blk gpa.allocator();
    }; // experimenting with where to put this...

    const input = try std_in.readToEndAlloc(alloc, 2_000_000);
    defer alloc.free(input);

    var coord_list_1 = std.ArrayList(usize).init(alloc);
    defer coord_list_1.deinit();

    var coord_list_2 = std.ArrayList(usize).init(alloc);
    defer coord_list_2.deinit();

    var lines = std.mem.splitSequence(u8, input, "\n");
    const line_1 = lines.next() orelse return error.MissingLine;  // adhoc errors feel convenient
    const line_2 = lines.next() orelse return error.MissingLine;  // Like in Rust, I'd have some ParseError("yadda yadda yadda".to_string())

    const coordinates_1 = try to_coord_list(line_1, alloc);
    defer coordinates_1.deinit();

    const coordinates_2 = try to_coord_list(line_2, alloc);
    defer coordinates_2.deinit();  // Lots and lots of defer...

    var map = std.AutoHashMap(Point, u32).init(alloc);  // Maps coordinate to time

    var time: u32 = 1;
    for (coordinates_1.items) |coordinate| {
        if (!map.contains(coordinate)) {
            try map.put(coordinate, time);
        }

        time += 1;
    }

    time = 1;
    var min_time: u32 = std.math.maxInt(u32);
    for (coordinates_2.items) |coordinate| {
        if (map.contains(coordinate)) {
            min_time = @min(min_time, map.get(coordinate).? + time);  // That .? means "orelse unreachable"
        }

        time += 1;
    }

    try std_out.print("{d}\n", .{min_time});
}
