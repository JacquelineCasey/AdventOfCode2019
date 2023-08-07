
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();

var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
const gpa_alloc = gpa.allocator();


// We have to add a parent pointer now.
// We also add a name for use as a later key. I chose to store the 3 letters
const Node = struct {
    children: std.ArrayList(*Node),
    parent: ?*Node,
    name: [3]u8,  // strings of unknown size are []u8, and likely live on the heap.

    fn init(alloc: std.mem.Allocator, name: [3]u8) Node {
        return .{
            .children = std.ArrayList(*Node).init(alloc),
            .parent = null,
            .name = name,
        };
    }

    pub fn deinit(self: Node) void {
        self.children.deinit();
    }
};


// pub fn count_orbits(node: *Node, level: i32, out: *i32) void { 
//     for (node.children.items) |child| {
//         out.* += level;
//         count_orbits(child, level + 1, out);
//     }
// }


pub fn main() !void {
    defer {
        // Test for memory leak
        const status = gpa.deinit();
        if (status == .leak) @panic("MEMORY LEAK");
    }

    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    defer arena.deinit();  // This does all the freeing!
    const alloc = arena.allocator();


    const input = try std_in.readToEndAlloc(alloc, 1_000_000_000);
    // defer alloc.free(input);  // optional. With arena allocator, this is a no op.

    var nodes = std.StringHashMap(*Node).init(alloc);
    // defer {
    //     var it = nodes.iterator();
    //     while (it.next()) |entry| {
    //         entry.value_ptr.*.deinit();  // entry has a pointer to Node pointer, so we have to dereference at least once
    //         alloc.destroy(entry.value_ptr.*);
    //     }

    //     nodes.deinit();
    // } 
    // Also a no op

    var it = std.mem.splitSequence(u8, input, "\n");
    while (it.next()) |substring| {
        const parent = substring[0..3];
        const child = substring[4..7];

        if (!nodes.contains(child)) {
            try nodes.put(child, try alloc.create(Node));
            nodes.get(child).?.* = Node.init(alloc, child.*);  // this was weird at first. Create the node, then initialize it. Both require cleanup (since Node manages memory).
        }

        if (!nodes.contains(parent)) {
            try nodes.put(parent, try alloc.create(Node));
            nodes.get(parent).?.* = Node.init(alloc, parent.*);
        }

        try nodes.get(parent).?.children.append(nodes.get(child).?);
        nodes.get(child).?.parent = nodes.get(parent).?;
    }

    const node_a = nodes.get("YOU").?.parent.?;
    const node_b = nodes.get("SAN").?.parent.?;

    // This is a matter of finding nearest common ancestor. We find all ancestors of
    // node_a and label them with distances. Then we iterate ancestors of node_b
    // until we find a match.

    var jumps: i32 = 0;
    var ancestors = std.StringHashMap(i32).init(alloc);
    // I actually forgot the free the first time...
    // defer ancestors.deinit();

    var curr_node: ?*Node = node_a;
    while (curr_node) |curr| {
        try ancestors.put(&curr.name, jumps);

        curr_node = curr.parent;
        jumps += 1;
    }

    jumps = 0;
    curr_node = node_b;
    while (curr_node) |curr| {
        if (ancestors.get(&curr.name)) |other_jumps| {  // Now I'm getting the idiom...
            try std_out.print("{d}\n", .{jumps + other_jumps});
            return;
        }

        curr_node = curr.parent;
        jumps += 1;
    }

    try std_out.print("Something went wrong...", .{});
}

// So I know I could probably just not free stuff for advent of code, but I want
// to learn that system too.

// This is the first time where freeing a data structure was not as simple as a
// one line defer next to the initialization. Defer cares about block scope, so
// you can't just defer Node free when the node is created.

// Pointer stuff is a little annoying, one gripe is that some functions like free
// have anytype parameters, which means type checking will be less helpful.
// Like an error is emitted eventually, but it feels like C++ template failure
// and not like - "you passed in the wrong type, you were off by a pointer".

// UPDATE: Let's try out an arena allocator!
// These seem like they could be very useful. But of course memory can be dead inside
// the arena for a long time.

// I wonder if there could be an allocator that uses the gpa free system, but 
// also provides a free all at the end in case of leak.

// One particular concern is array lists - they do a lot of reallocation in the
// background. The memory cost could increase quite a lot if you keep using them,
// and if they shrink and unshrink several times (shrink is bad anyway to be fair).