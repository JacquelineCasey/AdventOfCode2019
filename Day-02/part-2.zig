
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();

var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
const alloc = gpa.allocator();


fn run_intcode(list: std.ArrayList(usize), noun: usize, verb: usize) ?usize {
    list.items[1] = noun;
    list.items[2] = verb;

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
            std.debug.print("Error: unrecognized opcode at position {d}\n", .{index});
            return null;
        }

        index += 4;
    }

    return list.items[0];
}


pub fn main() !void {
    const input = try std_in.readToEndAlloc(alloc, 2_000_000);
    defer alloc.free(input);

    var list = std.ArrayList(usize).init(alloc);

    var it = std.mem.splitSequence(u8, input, ",");
    while (it.next()) |substring| 
        try list.append(try std.fmt.parseInt(usize, substring, 10));

    for (0..100) |noun| {  // Half inclusive range... (python style... its infectious!)
        for (0..100) |verb| { 
            if (run_intcode(try list.clone(), noun, verb) == 19690720) {
                try std_out.print("{d}\n", .{100 * noun + verb});
                return;
            }
        }
    }

    try std_out.print("No pair found, something went wrong...\n", .{});
}
