
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

        alloc: std.mem.Allocator,
        key_to_index: std.AutoHashMap(Key, usize),
        index_to_key: std.AutoHashMap(usize, Key),
        out_edges: std.AutoHashMap(usize, std.ArrayList(InternalEdge)),
        data: std.AutoHashMap(usize, Value),
        next_index: usize,

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
    };
}


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
            if (ch != '#' and ch != '@') {
                try tiles.put(.{ch_x, ch_y}, ch);
            }
            else if (ch == '@') {  // We treat @ as . going forward
                try tiles.put(.{ch_x, ch_y}, '.');
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

        try start_tiles.append(.{start_x + 1, start_y + 1});
        try start_tiles.append(.{start_x + 1, start_y - 1});
        try start_tiles.append(.{start_x - 1, start_y + 1});
        try start_tiles.append(.{start_x - 1, start_y - 1});
    }
    else {
        return error.MapHasMultipleStarts;  // Could be supported for some test cases.
    }

    var graph = Graph(Pair, u8).init(alloc);
    defer graph.deinit();
}


// Way harder... My current approach would allow the robots to wander way too much.
// I think I might build a graph that connects keys to each other.
// Also ban moves from keys to already collected keys. The graph structure has
// to tell you which keys you need to collect first, which includes both doors and
// intermediary keys that you "have to" grab first just because they are in between.


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
}
