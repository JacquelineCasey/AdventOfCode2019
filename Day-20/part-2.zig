
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();


const Pair = struct {i32, i32};

const Link = struct {Pair, ?Pair};

const State = struct { tile: Pair, level: u32 };  // A position and a recursion level. 0 means outer. 

const directions = [4] Pair {.{0, 1}, .{0, -1}, .{1, 0}, .{-1, 0}};


fn find_label(lines: std.ArrayList([]const u8), x: usize, y: usize) ?[2]u8 {
    var label: [2]u8 = undefined;
    
    if (std.ascii.isUpper(lines.items[y - 2][x]) and std.ascii.isUpper(lines.items[y - 1][x])) {
        label[0] = lines.items[y - 2][x];
        label[1] = lines.items[y - 1][x];
        return label;
    }
    if (std.ascii.isUpper(lines.items[y + 2][x]) and std.ascii.isUpper(lines.items[y + 1][x])) {
        label[0] = lines.items[y + 1][x];
        label[1] = lines.items[y + 2][x];
        return label;
    }
    if (std.ascii.isUpper(lines.items[y][x - 2]) and std.ascii.isUpper(lines.items[y][x - 1])) {
        label[0] = lines.items[y][x - 2];
        label[1] = lines.items[y][x - 1];
        return label;
    }
    if (std.ascii.isUpper(lines.items[y][x + 2]) and std.ascii.isUpper(lines.items[y][x + 1])) {
        label[0] = lines.items[y][x + 1];
        label[1] = lines.items[y][x + 2];
        return label;
    }

    return null;
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

    var lines = std.ArrayList([]const u8).init(alloc);
    defer lines.deinit();

    var iter = std.mem.splitSequence(u8, input, "\n");
    while (iter.next()) |line| {
        try lines.append(line);
    }

    // Mapping positions to their labels.
    var tiles = std.AutoHashMap(Pair, ?[2]u8).init(alloc);
    defer tiles.deinit();

    var labels = std.AutoHashMap([2]u8, Link).init(alloc);
    defer labels.deinit();

    // These refer to '.' tiles
    var min_x: u32 = 1_000_000;
    var min_y: u32 = 1_000_000;
    var max_x: u32 = 0;
    var max_y: u32 = 0;

    for (lines.items, 0..) |line, y| {
        for (line, 0..) |ch, x| {
            if (ch == '.') {
                min_x = @min(min_x, @as(u32, @intCast(x)));
                min_y = @min(min_y, @as(u32, @intCast(y)));
                max_x = @max(max_x, @as(u32, @intCast(x)));
                max_y = @max(max_y, @as(u32, @intCast(y)));

                const maybe_label = find_label(lines, x, y);

                try tiles.put(.{@as(i32, @intCast(x)), @as(i32, @intCast(y))}, maybe_label);

                if (maybe_label) |label| {
                    if (labels.get(label)) |link| {
                        if (link[1] != null) unreachable;

                        try labels.put(label, .{link[0], .{@as(i32, @intCast(x)), @as(i32, @intCast(y))}});
                    }
                    else {
                        try labels.put(label, .{.{@as(i32, @intCast(x)), @as(i32, @intCast(y))}, null});
                    }
                }
            }
        }
    }

    const start = labels.get("AA".*).?[0];
    if (labels.get("AA".*).?[1] != null) unreachable;

    var visited_states = std.AutoHashMap(State, void).init(alloc);
    defer visited_states.deinit();
    try visited_states.put(.{.tile = start, .level = 0}, {});

    var edge = std.ArrayList(State).init(alloc);
    defer edge.deinit();
    try edge.append(.{.tile = start, .level = 0});

    var next_edge = std.ArrayList(State).init(alloc);
    defer next_edge.deinit();

    var time: u32 = 0;
    outer: while (edge.items.len > 0) {
        for (edge.items) |state| {
            const tile = state.tile;

            const x = state.tile[0];
            const y = state.tile[1];
            const level = state.level;

            const is_outer = x == min_x or y == min_y or x == max_x or y == max_y;

            const maybe_label = tiles.get(tile).?;
            if (maybe_label) |label| {
                if (std.mem.eql(u8, &label, "ZZ") and level == 0) {
                    break :outer;
                }
            }

            for (directions) |dir| {
                const d_x = dir[0];
                const d_y = dir[1];

                const neighbor = Pair {x + d_x, y + d_y};
                if (!tiles.contains(neighbor)) continue;

                if (try visited_states.fetchPut(.{.tile = neighbor, .level = level}, {}) == null) {
                    try next_edge.append(.{.tile = neighbor, .level = level});
                }
            }

            if (maybe_label) |label| {
                if (is_outer and level == 0) continue;

                const next_level = if (is_outer) level - 1 else level + 1;

                if (std.mem.eql(u8, &label, "AA") or std.mem.eql(u8, &label, "ZZ")) continue;

                const link = labels.get(label).?;
                if (link[1] == null) unreachable;

                const neighbor = if (x == link[0][0] and y == link[0][1]) link[1].? else link[0];

                if (try visited_states.fetchPut(.{.tile = neighbor, .level = next_level}, {}) == null) {
                    try next_edge.append(.{.tile = neighbor, .level = next_level});
                }
            }
        }

        var tmp = edge;
        edge = next_edge;
        next_edge = tmp;
        next_edge.clearRetainingCapacity();

        time += 1;
    }
    else {
        try std_out.print("Failed to find ZZ", .{});
        return;
    }

    try std_out.print("{d}\n", .{time});
}


// Part 1: A little trickiness working with HashMaps. StringHashMap will not own 
// its keys, but AutoHashMap does, and it turns out we want AutoHashMap here.

// Part 2: Uh, that was surprisingly easy? Like I looked at the problem, and it
// felt like it would be hard and annoying, and then I realized that it would be
// tricky to code up but not conceptually that hard. And finally, I realized that
// it really wasn't really that hard to code up!
