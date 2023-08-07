
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
            if (direction == 'R') x += 1;
            if (direction == 'L') x -= 1;
            if (direction == 'U') y += 1;
            if (direction == 'D') y -= 1;

            try coordinates.append(Point {.x = x, .y = y});  // Not name punning. Order matters!
        }
    }

    return coordinates;
}


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    const alloc = gpa.allocator();

    const input = try std_in.readToEndAlloc(gpa.allocator(), 2_000_000);
    defer alloc.free(input);

    var coord_list_1 = std.ArrayList(usize).init(alloc);
    defer coord_list_1.deinit();

    var coord_list_2 = std.ArrayList(usize).init(gpa.allocator());
    defer coord_list_2.deinit();

    var lines = std.mem.splitSequence(u8, input, "\n");
    const line_1 = lines.next() orelse return error.MissingLine;  // adhoc errors feel convenient
    const line_2 = lines.next() orelse return error.MissingLine;  // Like in Rust, I'd have some ParseError("yadda yadda yadda".to_string())

    const coordinates_1 = try to_coord_list(line_1, alloc);
    defer coordinates_1.deinit();

    const coordinates_2 = try to_coord_list(line_2, alloc);
    defer coordinates_2.deinit();  // Lots and lots of defer...

    var map = std.AutoHashMap(Point, void).init(alloc);
    
    for (coordinates_1.items) |coordinate| {
        try map.put(coordinate, {});
    }

    var min_distance: u32 = std.math.maxInt(u32);
    for (coordinates_2.items) |coordinate| {
        if (map.contains(coordinate)) {
            min_distance = @min(min_distance, std.math.absCast(coordinate.x) + std.math.absCast(coordinate.y));
        }
    }

    try std_out.print("{d}\n", .{min_distance});
}
