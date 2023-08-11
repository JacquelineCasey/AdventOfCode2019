
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();


const directions: [4]struct {i32, i32} = .{.{1, 0}, .{-1, 0}, .{0, 1}, .{0, -1}};

const Position = struct {
    x: i32,
    y: i32,
    level: i32,
};


fn inc(pos: Position, map: *std.AutoHashMap(Position, u32)) !void {
    if (map.get(pos)) |count| {
        try map.put(pos, count + 1);
    }
    else {
        try map.put(pos, 1);
    }
}

fn add_neighbors(bug: Position, neighbors: *std.AutoHashMap(Position, u32)) !void {

    // Traditional directions first.
    for (directions) |direction| {
        const d_x = direction[0];
        const d_y = direction[1];

        // Ignore edges
        if (bug.x + d_x < 0 or bug.x + d_x >= 5 or bug.y + d_y < 0 or bug.y + d_y >= 5)
            continue;

        // Also ignore the middle
        if (bug.x + d_x == 2 and bug.y + d_y == 2)
            continue;

        try inc(.{ .x = bug.x + d_x, .y = bug.y + d_y, .level = bug.level }, neighbors);
    }


    // Now for edges. Recall outer grids have lower levels than inner grids.
    if (bug.x == 0)
        try inc(.{ .x = 1, .y = 2, .level = bug.level - 1}, neighbors);
    if (bug.x == 4)
        try inc(.{ .x = 3, .y = 2, .level = bug.level - 1}, neighbors);
    if (bug.y == 0)
        try inc(.{ .x = 2, .y = 1, .level = bug.level - 1}, neighbors);
    if (bug.y == 4)
        try inc(.{ .x = 2, .y = 3, .level = bug.level - 1}, neighbors);


    // Now for tiles adjacent to the inner layer.
    if (bug.x == 1 and bug.y == 2) {
        for (0..5) |i| {
            try inc(.{ .x = 0, .y = @as(i32, @intCast(i)), .level = bug.level + 1}, neighbors);
        }
    }
    if (bug.x == 3 and bug.y == 2) {
        for (0..5) |i| {
            try inc(.{ .x = 4, .y = @as(i32, @intCast(i)), .level = bug.level + 1}, neighbors);
        }
    }
    if (bug.x == 2 and bug.y == 1) {
        for (0..5) |i| {
            try inc(.{ .x = @as(i32, @intCast(i)), .y = 0, .level = bug.level + 1}, neighbors);
        }
    }
    if (bug.x == 2 and bug.y == 3) {
        for (0..5) |i| {
            try inc(.{ .x = @as(i32, @intCast(i)), .y = 4, .level = bug.level + 1}, neighbors);
        }
    }
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

    var bugs = std.AutoHashMap(Position, void).init(alloc);
    defer bugs.deinit();

    var line_iter = std.mem.splitSequence(u8, input, "\n");
    var y: i32 = 0;
    while (line_iter.next()) |line| {
        for (line, 0..) |ch, x| {
            if (ch == '#') {
                try bugs.put(.{ .x = @intCast(x), .y = y, .level = 0 }, {});
            }
        }

        y += 1;
    }

    var next_bugs = std.AutoHashMap(Position, void).init(alloc);
    defer next_bugs.deinit();

    for (0..200) |_| {
        var neighbors = std.AutoHashMap(Position, u32).init(alloc);
        defer neighbors.deinit();

        var bug_iter = bugs.keyIterator();
        while (bug_iter.next()) |bug| {
            try add_neighbors(bug.*, &neighbors);
        }

        var iter = neighbors.iterator();
        while (iter.next()) |entry| {
            if (bugs.contains(entry.key_ptr.*) and entry.value_ptr.* == 1) {
                try next_bugs.put(entry.key_ptr.*, {});
            }
            else if (!bugs.contains(entry.key_ptr.*) and (entry.value_ptr.* == 1 or entry.value_ptr.* == 2)) {
                try next_bugs.put(entry.key_ptr.*, {});
            }
        }

        const temp = bugs;
        bugs = next_bugs;
        next_bugs = temp;
        next_bugs.clearRetainingCapacity();
    }

    try std_out.print("{d}\n", .{bugs.count()});
}


// Nice! The only bug (:P) I encountered was setting up the bug spawning logic
// incorrectly. I think theres a common trap I fell into where I did:
// if (A and B)
//     ... // logic that should execute if A and B
// else if (C)
//     ... // logic that should execute if not A and C
//
// Where, since it was placed in an else, I was assuming that A was false. Of course.
// A could be true, B could be false, and C could be true, and you would have incorrect
// behavior. I think my aversion towards nesting conditionals bit me here.

// Zig's integer pickiness was annoying in part1 when working with array indices.
// Here though, things were better, since I stored just about everything as an i32
// in hash tables.

// The problem was pretty cool. I was not expecting recursion to be the twist, I
// was mostly worried about a larger board or a longer timeframe. However, all you
// really have to do is figure out how to store your infinite board, and then get
// the tricky neighbor logic correct, and you're good.
