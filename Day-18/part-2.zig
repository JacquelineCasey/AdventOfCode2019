
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();


// I'm not sure if there is a neat way to store this in the Graph struct where it
// can be easily accessible, particularly without rewriting the Graph type...
fn Edge(comptime Key: type) type {
    return struct { neighbor: Key, weight: u32 };  // neighbor is key.
}

/// An undirected, positive integer weight graph that uses the adjacency list representation.
/// Can also associate data with each key, like a hashtable. The key type must be
/// hashable, and the lookup semantics are those provided by AutoHashMap.
/// 
/// If no associated data is desired, pass void for the Value type.
fn Graph(comptime Key: type, comptime Value: type) type {
    const InternalEdge = struct { neighbor: usize, weight: u32 };  // neighbor is an index.

    return struct {
        const Self = @This();

        alloc: std.mem.Allocator,
        key_to_index: std.AutoHashMap(Key, usize),
        index_to_key: std.AutoHashMap(usize, Key),
        out_edges: std.AutoHashMap(usize, std.ArrayList(InternalEdge)),
        data: std.AutoHashMap(usize, Value),
        next_index: usize,

        // PS: If you are interested in optimizing this, you could easily combine
        // the 3 usize -> X hashtables.

        fn init(alloc: std.mem.Allocator) Self {
            return .{
                .alloc = alloc,
                .key_to_index = std.AutoHashMap(Key, usize).init(alloc),
                .index_to_key = std.AutoHashMap(usize, Key).init(alloc),
                .out_edges = std.AutoHashMap(usize, std.ArrayList(InternalEdge)).init(alloc),
                .data = std.AutoHashMap(usize, Value).init(alloc),
                .next_index = 0,
            };
        }

        fn deinit(self: *Self) void {
            self.key_to_index.deinit();
            self.index_to_key.deinit();

            var iter = self.out_edges.valueIterator();
            while (iter.next()) |edge_list| {
                edge_list.deinit();
            }
            self.out_edges.deinit();
            
            self.data.deinit();
        }


        // -- Summary Operations -- //

        fn count_nodes(self: *Self) usize {
            const a = self.index_to_key.count();
            const b = self.key_to_index.count();
            const c = self.out_edges.count();
            const d = self.data.count();

            if (a != b or b != c or c != d) unreachable;

            return a;
        }

        /// Runs in O(V)
        fn count_edges(self: *Self) usize {
            var sum: usize = 0;

            var iter = self.out_edges.valueIterator();
            while (iter.next()) |edge_list| {
                sum += edge_list.items.len;
            }

            return @divExact(sum, 2);  // Each edge is stored in 2 places.
        }


        // -- Basic Node Operations -- //

        /// Clobbers existing value if it exists. Edges are unchanged. If the key
        /// is new, it will have no edges.
        fn put(self: *Self, key: Key, value: Value) !void {
            if (self.key_to_index.get(key)) |index| {
                try self.data.put(index, value);
                return;
            }

            const index = self.next_index;
            self.next_index += 1;

            try self.key_to_index.put(key, index);
            try self.index_to_key.put(index, key);

            try self.data.put(index, value);

            try self.out_edges.put(index, std.ArrayList(InternalEdge).init(self.alloc));
        }

        fn get(self: Self, key: Key) ?Value {
            const index = self.key_to_index.get(key) orelse return null;
            return self.data.get(index).?;
        }

        /// It is permitted to remove a nonexistent key
        fn remove(self: *Self, key: Key) void {
            const index = self.key_to_index.get(key) orelse return;

            var edges = self.out_edges.getPtr(index).?;

            while (edges.items.len > 0) {
                const neighbor = edges.getLast().neighbor;
                self._remove_edge_indices(index, neighbor);
            }

            edges.deinit();

            if (!self.key_to_index.remove(key)) unreachable;
            if (!self.index_to_key.remove(index)) unreachable;
            if (!self.data.remove(index)) unreachable;
            if (!self.out_edges.remove(index)) unreachable;
        }

        /// It is an error if the key does not exist
        fn degree(self: Self, key: Key) !usize {
            const index = self.key_to_index.get(key) orelse return error.KeyNotFound;

            return self.out_edges.get(index).?.items.len;
        }


        // -- Basic Edge Operations -- //

        /// Errors if neither key exists. If the edge already exists, its weight is overridden.
        fn add_edge(self: *Self, key_1: Key, key_2: Key, weight: u32) !void {
            const index_1 = self.key_to_index.get(key_1) orelse return error.KeyNotFound;
            const index_2 = self.key_to_index.get(key_2) orelse return error.KeyNotFound;

            return self._add_edges_indices(index_1, index_2, weight);
        }

        fn _add_edges_indices(self: *Self, index_1: usize, index_2: usize, weight: u32) !void {
            var edge_list_1 = self.out_edges.getPtr(index_1).?;

            var found_1 = false;
            for (edge_list_1.items) |*edge| {
                if (edge.neighbor == index_2) {
                    edge.weight = weight;
                    found_1 = true;
                }
            }

            var edge_list_2 = self.out_edges.getPtr(index_2).?;

            var found_2 = false;
            for (edge_list_2.items) |*edge| {
                if (edge.neighbor == index_1) {
                    edge.weight = weight;
                    found_2 = true;
                }
            }

            if (found_1 and found_2) {
                return;  // Edges updated above
            }
            else if (!found_1 and !found_2) {
                try edge_list_1.append(.{ .neighbor = index_2, .weight = weight });
                try edge_list_2.append(.{ .neighbor = index_1, .weight = weight });
            }
            else unreachable;  // Panic, the edge_lists disagree
        }

        /// Errors if the keys don't exist. Otherwise, returns the edge weight if it exists or null otherwise.
        fn get_edge_weight(self: Self, key_1: Key, key_2: Key) !?u32 {
            const index_1 = self.key_to_index.get(key_1) orelse return error.KeyNotFound;
            const index_2 = self.key_to_index.get(key_2) orelse return error.KeyNotFound;
            
            return self._get_edge_weight_indices(index_1, index_2);
        }

        fn _get_edge_weight_indices(self: Self, index_1: usize, index_2: usize) ?u32 {
            const edges = self.out_edges.get(index_1).?;
            for (edges.items) |internal_edge| {
                if (internal_edge.neighbor == index_2) {
                    return internal_edge.weight;
                }
            }

            return null;
        }

        /// Errors if keys can't be found. If keys exist but edge does not, does nothing.
        fn remove_edge(self: *Self, key_1: Key, key_2: Key) !void {
            const index_1 = self.key_to_index.get(key_1) orelse return error.KeyNotFound;
            const index_2 = self.key_to_index.get(key_2) orelse return error.KeyNotFound;

            self._remove_edge_indices(index_1, index_2);
        }

        fn _remove_edge_indices(self: *Self, index_1: usize, index_2: usize) void {
            var edge_list_1 = self.out_edges.getPtr(index_1).?;
            var edge_list_2 = self.out_edges.getPtr(index_2).?;

            for (edge_list_1.items, 0..) |edge, i| {
                if (edge.neighbor == index_2) {
                    _ = edge_list_1.swapRemove(i);
                    break;
                }
            }

            for (edge_list_2.items, 0..) |edge, i| {
                if (edge.neighbor == index_1) {
                    _ = edge_list_2.swapRemove(i);
                    break;
                }
            }
        }

        /// Errors if the key does not exist.
        /// Edge order is not gauranteed. At time of writing, will return edges
        /// in insertion order provided that no edges were removed.
        fn edge_iterator(self: *const Self, key: Key) !EdgeIterator {
            // Finally found a use for pass by *const. We want a pointer because
            // we are afraid of copying the graph into the iterator, but we also
            // want to show that the graph will not change.
            
            const index = self.key_to_index.get(key) orelse return error.KeyNotFound;

            return EdgeIterator {
                .graph = self,
                .index = index,
                .i = 0,
            };
        }

        const EdgeIterator = struct {
            graph: *const Self,
            index: usize,
            i: usize,

            fn next(self: *EdgeIterator) ?Edge(Key) {
                const edges = self.graph.out_edges.get(self.index).?;

                if (self.i >= edges.items.len) 
                    return null;
                
                const internal_edge = edges.items[self.i];
                self.i += 1;

                return .{
                    .neighbor = self.graph.index_to_key.get(internal_edge.neighbor).?,
                    .weight = internal_edge.weight,
                };
            }
        };

        // -- Special Operations -- //

        /// Removes a node, adding edges between its neighbors representing paths
        /// through the node. If an edge already exists, it is updated if a new
        /// path is shorter.
        /// It is an error for the key to not exist in the graph.
        fn contract(self: *Self, key: Key) !void {
            const index = self.key_to_index.get(key) orelse return error.KeyNotFound;

            var edges = self.out_edges.get(index).?;

            for (edges.items) |edge_1| {
                for (edges.items) |edge_2| {
                    if (edge_1.neighbor == edge_2.neighbor) 
                        continue;

                    const new_weight = edge_1.weight + edge_2.weight;

                    if (self._get_edge_weight_indices(edge_1.neighbor, edge_2.neighbor)) |cross_weight| {
                        if (cross_weight > new_weight) {
                            try self._add_edges_indices(edge_1.neighbor, edge_2.neighbor, new_weight);
                        }
                    }
                    else {
                        try self._add_edges_indices(edge_1.neighbor, edge_2.neighbor, new_weight);
                    }
                }
            }

            self.remove(key);
        }
    };
}


const Pair = struct {i32, i32};

const directions = [_]Pair {.{0, 1}, .{0, -1}, .{1, 0}, .{-1, 0}};


/// Takes in an empty graph, runs DFS on tiles from
fn build_graph(graph: *Graph(Pair, u8), tiles: std.AutoHashMap(Pair, u8), start: Pair) !void {
    const x = start[0];
    const y = start[1];

    if (tiles.get(.{x, y})) |ch| {
        if (graph.get(.{x, y}) == null) {
            try graph.put(.{x, y}, ch);

            for (directions) |dir| {
                const d_x = dir[0];
                const d_y = dir[1];

                if (graph.get(.{x + d_x, y + d_y})) |_| {
                    try graph.add_edge(start, .{x + d_x, y + d_y}, 1);
                }
                else {
                    try build_graph(graph, tiles, .{x + d_x, y + d_y});
                }
            }
        }
    }
}

/// Looks at the graphs and deduces dependencies between keys.
/// Assumes graph is tree.
fn analyze(graph: Graph(Pair, u8), start: Pair, from: ?Pair, 
    requirements: *std.AutoHashMap(u8, std.bit_set.IntegerBitSet(26)), curr_list: std.bit_set.IntegerBitSet(26)) !void {

    const ch = graph.get(start).?;

    if ('a' <= ch and ch <= 'z') {
        try requirements.put(ch, curr_list);
    }

    var next_list = curr_list;

    if ('a' <= ch and ch <= 'z') {
        next_list.set(ch - 'a');
    }
    if ('A' <= ch and ch <= 'Z') {
        next_list.set(ch - 'A');
    }

    var iter = try graph.edge_iterator(start);
    while (iter.next()) |edge| {
        const next = edge.neighbor;
        
        if (from != null and next[0] == from.?[0] and next[1] == from.?[1])
            continue;

        try analyze(graph, next, start, requirements, next_list);
    }
}

fn transform(in_graph: *Graph(Pair, u8), alloc: std.mem.Allocator) !Graph(u8, void) {
    var out_graph = Graph(u8, void).init(alloc);

    var node_iter = in_graph.key_to_index.keyIterator();
    while (node_iter.next()) |key| {
        const ch = in_graph.get(key.*).?;

        try out_graph.put(ch, {});
    }

    node_iter = in_graph.key_to_index.keyIterator();
    while (node_iter.next()) |key| {
        const ch_1 = in_graph.get(key.*).?;

        var edge_iter = try in_graph.edge_iterator(key.*);
        while (edge_iter.next()) |edge| {
            const ch_2 = in_graph.get(edge.neighbor).?;

            try out_graph.add_edge(ch_1, ch_2, edge.weight);
        }
    }

    return out_graph;
}

const State = struct { positions: [4]u8, held_keys: std.bit_set.IntegerBitSet(26) };

const QueueItem = struct { state: State, priority: u32 };

fn least_priority(_ :void, first: QueueItem, second: QueueItem) std.math.Order {
    if (first.priority < second.priority) return std.math.Order.lt;
    if (first.priority > second.priority) return std.math.Order.gt;
    return std.math.Order.eq;
}

fn multi_dijkstra(graphs: [4] Graph(u8, void), requirements: std.AutoHashMap(u8, std.bit_set.IntegerBitSet(26)), 
    key_count: u32, alloc: std.mem.Allocator) !u32 {

    var seen_states = std.AutoArrayHashMap(State, void).init(alloc);
    defer seen_states.deinit();
    
    var queue = std.PriorityQueue(QueueItem, void, least_priority).init(alloc, {});
    defer queue.deinit();

    const start_state = State {
        .positions = "@@@@".*, 
        .held_keys = std.bit_set.IntegerBitSet(26).initEmpty() 
    };

    try queue.add(.{ 
        .state = start_state,
        .priority = 0 
    });

    while (queue.len > 0) {
        const queue_item = queue.remove();
        const state = queue_item.state;
        const dist = queue_item.priority;

        if (try seen_states.fetchPut(state, {})) |_| {
            continue;
        }

        if (state.held_keys.count() == key_count) {
            return dist;
        }

        for (graphs, 0..) |graph, i| {
            var edge_iter = try graph.edge_iterator(state.positions[i]);

            while (edge_iter.next()) |edge| {
                const ch = edge.neighbor;
                const next_dist = dist + edge.weight;

                if (!state.held_keys.supersetOf(requirements.get(ch).?))
                    continue;

                var next_keys = state.held_keys;
                var next_positions: [4] u8 = state.positions; 

                if (ch != '@') {
                    next_keys.set(ch - 'a');
                }

                next_positions[i] = ch;

                const next_state = State { .positions = next_positions, .held_keys = next_keys };

                try queue.add(.{ .state = next_state, .priority = next_dist });
            }
        }
    }

    return error.CouldNotCollectAllKeys;
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

    // All tiles, except walls
    var tiles = std.AutoHashMap(Pair, u8).init(alloc);
    defer tiles.deinit();

    var maybe_start_pair: ?Pair = null;
    var start_pairs: u32 = 0;

    var key_count: u32 = 0;

    var ch_x: i32 = 0;
    var ch_y: i32 = 0;

    for (input) |ch| {
        if (ch == '\n') {
            ch_x = 0;
            ch_y += 1;
        }
        else {
            if (ch != '#') {
                try tiles.put(.{ch_x, ch_y}, ch);
            }
            
            if (ch == '@') {
                maybe_start_pair = Pair {ch_x, ch_y};
                start_pairs += 1;
            }

            if (ch >= 'a' and ch <= 'z') {
                key_count += 1;
            }

            ch_x += 1;
        }
    }

    var start_tiles = std.ArrayList(Pair).init(alloc);
    defer start_tiles.deinit();

    if (start_pairs == 1) {
        const start_x = maybe_start_pair.?[0];
        const start_y = maybe_start_pair.?[1];

        _ = tiles.remove(.{start_x, start_y});
        _ = tiles.remove(.{start_x + 1, start_y});
        _ = tiles.remove(.{start_x - 1, start_y});
        _ = tiles.remove(.{start_x, start_y + 1});
        _ = tiles.remove(.{start_x, start_y - 1});

        try tiles.put(.{start_x + 1, start_y + 1}, '@');
        try tiles.put(.{start_x + 1, start_y - 1}, '@');
        try tiles.put(.{start_x - 1, start_y + 1}, '@');
        try tiles.put(.{start_x - 1, start_y - 1}, '@');

        try start_tiles.append(.{start_x + 1, start_y + 1});
        try start_tiles.append(.{start_x + 1, start_y - 1});
        try start_tiles.append(.{start_x - 1, start_y + 1});
        try start_tiles.append(.{start_x - 1, start_y - 1});
    }
    else {
        return error.MapHasMultipleStarts;  // Could be supported for some test cases.
    }

    var graphs: [4]Graph(u8, void) = undefined;
    defer for (0..4) |i| graphs[i].deinit();

    var requirements = std.AutoHashMap(u8, std.bit_set.IntegerBitSet(26)).init(alloc);
    defer requirements.deinit();

    try requirements.put('@', std.bit_set.IntegerBitSet(26).initEmpty());

    for (0..4) |i| {
        var graph = Graph(Pair, u8).init(alloc);
        defer graph.deinit();

        try build_graph(&graph, tiles, start_tiles.items[i]);

        try analyze(graph, start_tiles.items[i], null, &requirements, std.bit_set.IntegerBitSet(26).initEmpty());

        var pairs_to_contract = std.ArrayList(Pair).init(alloc);
        defer pairs_to_contract.deinit();

        var iter = graph.key_to_index.keyIterator();
        while (iter.next()) |key| {
            const ch = tiles.get(key.*).?;

            if (ch == '.' or ('A' <= ch and ch <= 'Z')) {
                try pairs_to_contract.append(key.*);
            }
        }

        for (pairs_to_contract.items) |pair| {
            try graph.contract(pair);
        }

        graphs[i] = try transform(&graph, alloc);
    }

    try std_out.print("{d}\n", .{try multi_dijkstra(graphs, requirements, key_count, alloc)});
}


// Way harder... My current approach would allow the robots to wander way too much.
// I think I might build a graph that connects keys to each other.
// Also ban moves from keys to already collected keys. The graph structure has
// to tell you which keys you need to collect first, which includes both doors and
// intermediary keys that you "have to" grab first just because they are in between.

// Algorithm Description
//
// Build graphs from the 4 quadrants of the maze, with a node per tile.
// DFS each graph to populate a prerequisites field on all of the keys. A key has
// a prerequisite if it is behind a door, or behind another key (soft prerequisite: 
// it is always beneficial to pick up that key first).
// 
// Contract all `.` nodes and all door nodes. We now have a graph that is only keys and `@`.
//
// Find the transitive closure of the graph. We now have a complete graph. 
// (SKIPPING THIS FOR NOW, the graphs are rather small. Indeed it turned out to be
// uneccessary).
//
// Perform a sort of Quadruple Dijkstra. Its basically normal dijkstra, except the
// states describe the locations of the 4 robots (so [4]u8) and a list of gathered
// keys (we can do the bitarray thing again). We'll need a priority queue, which
// Zig has, but it doesn't have decrease key (typical...) so we'll do the reinsert
// trick and use a supplementary hashtable.
//
// Each state's neighbors are basically all the states where exactly one of the
// robots moves to a node (no '@') for which all the prerequisites are gathered.

// Final Report: It works! And better yet, its rather fast, taking only a second
// on ReleaseSafe, which is actually faster than part1. I think to some extent I
// had overestimated the size of the search space (branching factor).
//
// I probably went overboard, but I used this last puzzle as an opportunity to play
// with Zig's unique comptime programming / generics system. I'll be honest, I still
// don't have as much intuition for this yet, but it helps that the system itself
// is fairly friendly. Somehow, Zig has taken the parts of the language that define
// types and the parts of the language that define behavior and unified them under
// one syntax. Structs are stored in (const) variables, and can be built out of
// other variable structs. They are manipulated like arguments passed to functions
// in generics.
//
// Building the graph data structure was tricky, but I followed a test driven
// strategy (see the giant test below). Could I have installed a graph library?
// Probably, but I am sticking to my as of yet library-less Advent of Code, so I
// wrote my own. Its an interesting task, and I like the result, I could see myself
// using it again (with some further extensions and optimizations) in the future,
// if I ever find myself in the admittedly unfortunate sitaution of doing graph
// theory in Zig.
//
// Zig's priority queue is like everyone else's in that it doesn't have decrease_key.
// You get around this the standard way, though I still hope for more.
//
// I did experience some memory leaks while developing the graph, and it makes me
// think that Zig isn't as predictable as I thought, but to be fair this is 1 of
// around 2 incidents in the entirety of 49 puzzles, and I am of course a Zig noob.
// The issue is that I grabbed a ArrayList by value and modified it. I was under
// the assumption that the underlying data would come with it, and it kinda did?
// Modifying the ArrayList does impact the underlying data that it is holding as
// a slice (fat pointer). However, it didn't impact the metadata, like the size of
// the list. Also, it might have made a copy when the slice go too large? Regardless,
// things go desynced, and the memory was leaked. You need to grab the array list
// by pointer.
//
// C++ would do value semantics. You get a copy of the metadata AND (expensively)
// the underlying array. However, you can easily capture by reference and manipulate
// the original instead. In rust, if you capture a vector "by value", you move it,
// and the old variable is invalid unless you did an explicit copy. Otherwise, you
// borrow it and get full reference semantics. In Python, everything is reference
// semantics by default, so you always get the full list and its metadata by reference.
// This is a surprisingly nasty little corner of Zig. Its not unique I suppose, C
// would do this too (hence why C++ uses RAII in the standard library). Still, kinda
// a headache - I have to think about what is going on inside of std.ArrayList more
// than in the others.
//
// Cool puzzle. Definitely the most time consuming of the bunch, though this above
// all the others suffers from my choice to use a systems programming language.
// I don't mind a hard puzzle, but I'm glad there was really only this one.
//
// Anyways, that was the last one. I'll probably write a bit more on Zig, and then
// I'll move on.



// ---- Graph Tests ---- //

test "graph works as expected" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();  // In tests, memory leaks are detected automatically upon .deinit();

    var graph = Graph(i32, u8).init(alloc);
    defer graph.deinit();

    try graph.put(123, 'a');
    try graph.put(20, 'b');
    try graph.put(30, 'c');
    try graph.put(123, 'd');

    try testing.expectEqual(graph.get(123), 'd');
    try testing.expectEqual(graph.get(20), 'b');
    try testing.expectEqual(graph.get(30), 'c');
    try testing.expectEqual(graph.get(-42), null);    

    try graph.add_edge(123, 20, 5);
    try graph.add_edge(30, 123, 2);
    try graph.add_edge(20, 123, 3);

    // Note that this assumes the edge order, which cannot be done if any edges
    // are removed.
    var iter = try graph.edge_iterator(123);
    try testing.expectEqual(iter.next(), .{ .neighbor = 20, .weight = 3 });
    try testing.expectEqual(iter.next(), .{ .neighbor = 30, .weight = 2 });
    try testing.expectEqual(iter.next(), null);

    iter = try graph.edge_iterator(30);
    try testing.expectEqual(iter.next(), .{ .neighbor = 123, .weight = 2 });
    try testing.expectEqual(iter.next(), null);

    try graph.add_edge(123, 20, 300);

    iter = try graph.edge_iterator(20);
    try testing.expectEqual(iter.next(), .{ .neighbor = 123, .weight = 300 });
    try testing.expectEqual(iter.next(), null);

    try testing.expectError(error.KeyNotFound, graph.edge_iterator(-42));

    // This of course does not depend on order
    try testing.expectEqual(try graph.get_edge_weight(123, 20), 300);
    try testing.expectEqual(try graph.get_edge_weight(20, 123), 300);
    try testing.expectEqual(try graph.get_edge_weight(123, 30), 2);
    try testing.expectEqual(try graph.get_edge_weight(30, 123), 2);
    try testing.expectEqual(try graph.get_edge_weight(30, 20), null);
    try testing.expectError(error.KeyNotFound, graph.get_edge_weight(30, 29));

    try graph.remove_edge(123, 20);
    try graph.remove_edge(30, 20);  // it is permitted to remove nonexistent edges
    try testing.expectEqual(try graph.get_edge_weight(123, 20), null);
    try testing.expectEqual(try graph.get_edge_weight(20, 123), null);
    try testing.expectError(error.KeyNotFound, graph.remove_edge(123, -42));

    
    var graph_2 = Graph(u8, void).init(alloc);
    defer graph_2.deinit();

    try graph_2.put('A', {});
    try graph_2.put('B', {});
    try graph_2.put('C', {});
    try graph_2.put('D', {});
    try graph_2.put('E', {});

    try graph_2.add_edge('A', 'B', 1);
    try graph_2.add_edge('B', 'C', 1);
    try graph_2.add_edge('C', 'D', 1);
    try graph_2.add_edge('D', 'E', 1);
    try graph_2.add_edge('E', 'A', 1);

    try graph_2.put('X', {});

    try graph_2.add_edge('A', 'X', 1);
    try graph_2.add_edge('B', 'X', 1);
    try graph_2.add_edge('C', 'X', 1);
    try graph_2.add_edge('D', 'X', 1);
    try graph_2.add_edge('E', 'X', 1);

    try testing.expectEqual(try graph_2.degree('A'), 3);
    try testing.expectEqual(try graph_2.degree('B'), 3);
    try testing.expectEqual(try graph_2.degree('C'), 3);
    try testing.expectEqual(try graph_2.degree('D'), 3);
    try testing.expectEqual(try graph_2.degree('E'), 3);
    try testing.expectEqual(try graph_2.degree('X'), 5);
    try testing.expectError(error.KeyNotFound, graph_2.degree('K'));

    try testing.expectEqual(graph_2.count_nodes(), 6);
    try testing.expectEqual(graph_2.count_edges(), 10);

    graph_2.remove('X');

    try testing.expectEqual(try graph_2.degree('A'), 2);
    try testing.expectEqual(try graph_2.degree('B'), 2);
    try testing.expectEqual(try graph_2.degree('C'), 2);
    try testing.expectEqual(try graph_2.degree('D'), 2);
    try testing.expectEqual(try graph_2.degree('E'), 2);
    try testing.expectError(error.KeyNotFound, graph_2.degree('X'));

    try testing.expectEqual(graph_2.count_nodes(), 5);
    try testing.expectEqual(graph_2.count_edges(), 5);


    var graph_3 = Graph([4]u8, void).init(alloc);
    defer graph_3.deinit();

    try graph_3.put("AAAA".*, {});
    try graph_3.put("BBBB".*, {});
    try graph_3.put("CCCC".*, {});
    try graph_3.put("XXXX".*, {});

    try graph_3.add_edge("AAAA".*, "BBBB".*, 9);
    try graph_3.add_edge("BBBB".*, "CCCC".*, 7);

    try graph_3.add_edge("AAAA".*, "XXXX".*, 4);
    try graph_3.add_edge("BBBB".*, "XXXX".*, 4);
    try graph_3.add_edge("CCCC".*, "XXXX".*, 4);

    try graph_3.contract("XXXX".*);

    try testing.expectEqual(graph_3.count_nodes(), 3);
    try testing.expectEqual(graph_3.count_edges(), 3);

    try testing.expectEqual(graph_3.get_edge_weight("AAAA".*, "BBBB".*), 8);
    try testing.expectEqual(graph_3.get_edge_weight("BBBB".*, "CCCC".*), 7);  // original was shorter
    try testing.expectEqual(graph_3.get_edge_weight("AAAA".*, "CCCC".*), 8);
}
