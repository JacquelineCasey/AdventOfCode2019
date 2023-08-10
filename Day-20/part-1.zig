
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();


const Pair = struct {i32, i32};

const Link = struct {Pair, ?Pair};

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


    for (lines.items, 0..) |line, y| {
        for (line, 0..) |ch, x| {
            if (ch == '.') {
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

    var visited_tiles = std.AutoHashMap(Pair, void).init(alloc);
    defer visited_tiles.deinit();
    try visited_tiles.put(start, {});

    var edge = std.ArrayList(Pair).init(alloc);
    defer edge.deinit();
    try edge.append(start);

    var next_edge = std.ArrayList(Pair).init(alloc);
    defer next_edge.deinit();

    var time: u32 = 0;
    outer: while (edge.items.len > 0) {
        for (edge.items) |tile| {
            const x = tile[0];
            const y = tile[1];
            const maybe_label = tiles.get(tile).?;
            if (maybe_label) |label| {
                if (std.mem.eql(u8, &label, "ZZ")) {
                    break :outer;
                }
            }

            for (directions) |dir| {
                const d_x = dir[0];
                const d_y = dir[1];

                const neighbor = Pair {x + d_x, y + d_y};
                if (!tiles.contains(neighbor)) continue;

                if (try visited_tiles.fetchPut(neighbor, {}) == null) {
                    try next_edge.append(neighbor);
                }
            }

            if (maybe_label) |label| {
                if (std.mem.eql(u8, &label, "AA")) continue;

                const link = labels.get(label).?;
                if (link[1] == null) unreachable;

                const neighbor = if (x == link[0][0] and y == link[0][1]) link[1].? else link[0];

                if (try visited_tiles.fetchPut(neighbor, {}) == null) {
                    try next_edge.append(neighbor);
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


// A little trickiness working with HashMaps. StringHashMap will not own its keys, 
// but AutoHashMap does, and it turns out we want AutoHashMap here.
