
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();


// Tagged union - the tag is inferred, due to enum keyword
const Instruction = union(enum) {
    deal_new: void,
    cut: i32,
    deal_inc: i32,
};


fn deal_new(in: std.ArrayList(i32), out: std.ArrayList(i32)) void {
    for (0..in.items.len) |i| {
        out.items[out.items.len - i - 1] = in.items[i]; 
    }
}

fn cut(in: std.ArrayList(i32), out: std.ArrayList(i32), amount: i32) void {
    for (0..in.items.len) |i| {
        out.items[@intCast(@mod(@as(i32, @intCast(i)) - amount, @as(i32, @intCast(in.items.len))))] = in.items[i];
    }
}

fn deal_inc(in: std.ArrayList(i32), out: std.ArrayList(i32), amount: i32) void {
    for (0..in.items.len) |i| {
        out.items[(i * @as(usize, @intCast(amount))) % out.items.len] = in.items[i];
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

    var instructions = std.ArrayList(Instruction).init(alloc);
    defer instructions.deinit();

    var line_iter = std.mem.splitSequence(u8, input, "\n");
    while (line_iter.next()) |line| {
        if (std.mem.startsWith(u8, line, "cut")) {
            try instructions.append(.{ .cut = try std.fmt.parseInt(i32, line[4..], 10) });
        }
        else if (std.mem.startsWith(u8, line, "deal with increment")) {
            try instructions.append(.{ .deal_inc = try std.fmt.parseInt(i32, line[20..], 10) });
        }
        else if (std.mem.eql(u8, line, "deal into new stack")) {
            try instructions.append(.{ .deal_new = {} });
        }
        else unreachable;
    }

    var deck = std.ArrayList(i32).init(alloc);
    defer deck.deinit();

    var next_deck = std.ArrayList(i32).init(alloc);
    defer next_deck.deinit();

    for (0..10007) |i| {
        try deck.append(@intCast(i));
        try next_deck.append(0);
    }

    for (instructions.items) |instruction| {
        switch (instruction) {
            .deal_new => {
                deal_new(deck, next_deck);
            },
            .cut => |amount| {
                cut(deck, next_deck, amount);
            },
            .deal_inc => |amount| {
                deal_inc(deck, next_deck, amount);
            }
        }

        const tmp = deck;
        deck = next_deck;
        next_deck = tmp;
    }

    try std_out.print("{d}\n", .{std.mem.indexOfScalar(i32, deck.items, 2019).?});
}
