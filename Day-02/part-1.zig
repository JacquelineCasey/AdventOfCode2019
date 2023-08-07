
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();

var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
const alloc = gpa.allocator();


pub fn main() !void {
    const input = try std_in.readToEndAlloc(alloc, 2_000_000);
    defer alloc.free(input);

    var list = std.ArrayList(usize).init(alloc);

    var it = std.mem.splitSequence(u8, input, ",");
    while (it.next()) |substring| 
        try list.append(try std.fmt.parseInt(usize, substring, 10));

    // comment these out before running test
    list.items[1] = 12;
    list.items[2] = 2;

    var index: usize = 0;
    while (true) {
        if (list.items[index] == 1) {
            list.items[list.items[index + 3]] = list.items[list.items[index + 1]] + list.items[list.items[index + 2]];
        }
        else if (list.items[index] == 2) {
            list.items[list.items[index + 3]] = list.items[list.items[index + 1]] * list.items[list.items[index + 2]];
        }
        else if (list.items[index] == 99) {
            break;
        }
        else {
            try std_out.print("Error: unrecognized opcode at position {d}\n", .{index});
        }

        index += 4;
    }

    try std_out.print("{d}\n", .{list.items[0]});
}
