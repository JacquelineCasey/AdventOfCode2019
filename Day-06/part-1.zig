
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();

const gpa_alloc = blk: {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    break :blk gpa.allocator();
}; 


const Node = struct {
    children: std.ArrayList(*Node),

    fn init(alloc: std.mem.Allocator) Node {
        return .{
            .children = std.ArrayList(*Node).init(alloc)
        };
    }

    pub fn deinit(self: Node) void {
        self.children.deinit();
    }
};


pub fn count_orbits(node: *Node, level: i32, out: *i32) void { 
    for (node.children.items) |child| {
        out.* += level;
        count_orbits(child, level + 1, out);
    }
}


pub fn main() !void {
    const input = try std_in.readToEndAlloc(gpa_alloc, 1_000_000_000);
    defer gpa_alloc.free(input);

    var nodes = std.StringHashMap(*Node).init(gpa_alloc);
    defer {
        var it = nodes.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();  // entry has a pointer to Node pointer, so we have to dereference at least once
            gpa_alloc.destroy(entry.value_ptr.*);
        }

        nodes.deinit();
    }

    var it = std.mem.splitSequence(u8, input, "\n");
    while (it.next()) |substring| {
        const parent = substring[0..3];
        const child = substring[4..7];

        if (!nodes.contains(child)) {
            try nodes.put(child, try gpa_alloc.create(Node));
            nodes.get(child).?.* = Node.init(gpa_alloc);  // this was weird at first. Create the node, then initialize it. Both require cleanup (since Node manages memory).
        }

        if (!nodes.contains(parent)) {
            try nodes.put(parent, try gpa_alloc.create(Node));
            nodes.get(parent).?.* = Node.init(gpa_alloc);
        }

        try nodes.get(parent).?.children.append(nodes.get(child).?);
    }

    var orbits: i32 = 0;
    count_orbits(nodes.get("COM").?, 1, &orbits);

    try std_out.print("{d}\n", .{orbits});
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