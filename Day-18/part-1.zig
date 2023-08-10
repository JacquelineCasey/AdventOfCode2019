
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();


const Pair = struct {i32, i32};

const State = struct {
    position: Pair,
    keys: std.bit_set.IntegerBitSet(26),
};


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

    const directions = [_]Pair {.{0, 1}, .{0, -1}, .{1, 0}, .{-1, 0}};


    var time: u32 = 0;
    var result = outer: while (edge_states.items.len > 0) {
        for (edge_states.items) |state| {
            const x = state.position[0];
            const y = state.position[1];

            if (state.keys.count() == key_count) {
                break :outer time;
            }

            for (directions) |dir| {
                const d_x = dir[0];
                const d_y = dir[1];

                const neighbor = tiles.get(.{x + d_x, y + d_y}) orelse continue;

                const next_state = switch (neighbor) {
                    '.' => .{ .position = .{x + d_x, y + d_y}, .keys = state.keys },
                    'a'...'z' => blk: {
                        var next_keys = state.keys;
                        next_keys.set(neighbor - 'a');

                        break :blk .{ .position = .{x + d_x, y + d_y}, .keys = next_keys };
                    },
                    'A'...'Z' => blk: {
                        if (!state.keys.isSet(neighbor - 'A')) continue;

                        break :blk .{ .position = .{x + d_x, y + d_y}, .keys = state.keys };
                    },
                    else => unreachable,
                };

                if (!visited_states.contains(next_state)) {
                    try visited_states.put(next_state, time + 1);
                    try next_edge_states.append(next_state);
                }
            }
        }        

        const tmp = edge_states;
        edge_states = next_edge_states;
        next_edge_states = tmp;
        next_edge_states.clearRetainingCapacity();
        
        time += 1;
    }
    else 0;

    try std_out.print("{d}\n", .{result});
}
