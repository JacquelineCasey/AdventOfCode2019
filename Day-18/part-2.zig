
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();


const Pair = struct {i32, i32};

const State = struct {
    position: Pair,
    keys: std.bit_set.IntegerBitSet(26),
};

const directions = [_]Pair {.{0, 1}, .{0, -1}, .{1, 0}, .{-1, 0}};


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    const alloc = gpa.allocator();
    defer {
        const code = gpa.deinit();
        if (code == .leak) @panic("Memory leaked");
    }

    const input = try std_in.readToEndAlloc(alloc, 1_000_000_000);  
    defer alloc.free(input);

    // All tiles, except walls
    var tiles = std.AutoArrayHashMap(Pair, u8).init(alloc);
    defer tiles.deinit();

    var maybe_start_pair: ?Pair = null;

    var key_count: u32 = 0;

    var ch_x: i32 = 0;
    var ch_y: i32 = 0;
    for (input) |ch| {
        if (ch == '\n') {
            ch_x = 0;
            ch_y += 1;
        }
        else {
            if (ch != '#' and ch != '@') {
                try tiles.put(.{ch_x, ch_y}, ch);
            }
            else if (ch == '@') {  // We treat @ as . going forward
                try tiles.put(.{ch_x, ch_y}, '.');
                maybe_start_pair = Pair {ch_x, ch_y};
            }

            if (ch >= 'a' and ch <= 'z') {
                key_count += 1;
            }

            ch_x += 1;
        }
    }

    var visited_states = std.AutoHashMap(State, u32).init(alloc);
    defer visited_states.deinit();

    const start_state = State { .position = maybe_start_pair.?, .keys = std.bit_set.IntegerBitSet(26).initEmpty() };
    try visited_states.put(start_state, 0);

    var edge_states = std.ArrayList(State).init(alloc);
    defer edge_states.deinit();
    try edge_states.append(start_state);

    var next_edge_states = std.ArrayList(State).init(alloc);
    defer next_edge_states.deinit();




}


// Way harder... My current approach would allow the robots to wander way too much.
// I think I might build a graph that connects keys to each other.
// Also ban moves from keys to already collected keys. The graph structure has
// to tell you which keys you need to collect first, which includes both doors and
// intermediary keys that you "have to" grab first just because they are in between.