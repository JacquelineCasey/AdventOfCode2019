
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();



const directions: [4]struct {i32, i32} = .{.{1, 0}, .{-1, 0}, .{0, 1}, .{0, -1}};

fn biodiversity(tiles: [5][5]bool) u32 {
    var tile_score: u32 = 1;
    var sum: u32 = 0;
    for (tiles) |row| {
        for (row) |tile| {
            if (tile) {
                sum += tile_score;
            }

            tile_score *= 2;
        }
    }

    return sum;
}

fn next(tiles: [5][5]bool) [5][5]bool {
    var next_tiles: [5][5]bool = undefined;
    var neighbors: [5][5]u32 = .{.{0} ** 5} ** 5;

    for (0..5) |r| {
        for (0..5) |c| {
            if (tiles[r][c]) {
                for (directions) |direction| {
                    const d_r = direction[0];
                    const d_c = direction[1];
                    if (@as(i32, @intCast(r)) + d_r < 0 
                        or @as(i32, @intCast(r)) + d_r >= 5 
                        or @as(i32, @intCast(c)) + d_c < 0 
                        or @as(i32, @intCast(c)) + d_c >= 5) continue;

                    neighbors[@intCast(@as(i32, @intCast(r)) + d_r)][@intCast(@as(i32, @intCast(c))  + d_c)] += 1;
                }
            }
        }
    }

    for (0..5) |r| {
        for (0..5) |c| {
            next_tiles[r][c] = 
                (tiles[r][c] and neighbors[r][c] == 1)
                or (!tiles[r][c] and (neighbors[r][c] == 1 or neighbors[r][c] == 2));
        }
    }

    return next_tiles;
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

    var tiles: [5][5]bool = undefined;

    var line_iter = std.mem.splitSequence(u8, input, "\n");
    var r: u32 = 0;
    while (line_iter.next()) |line| {
        for (line, 0..) |ch, c| {
            tiles[r][c] = ch == '#';
        }

        r += 1;
    }

    var states = std.AutoHashMap(u32, void).init(alloc);
    defer states.deinit();

    while (true) {
        const diversity = biodiversity(tiles);
        if (states.contains(diversity)) {
            try std_out.print("{d}\n", .{diversity});

            return;
        }

        try states.put(diversity, {});

        tiles = next(tiles);
    }
}
