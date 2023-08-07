
const std = @import("std");
const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();

var gpa = std.heap.GeneralPurposeAllocator(.{}) {};  // I think real code would put this in main and pass it around.
const alloc = gpa.allocator();

pub fn main() !void {
    const input = try std_in.readToEndAlloc(alloc, 2_000_000);
    defer alloc.free(input);

    var sum: i32 = 0;

    var it = std.mem.splitSequence(u8, input, "\n");
    while (it.next()) |substring| {
        const num = try std.fmt.parseInt(i32, substring, 10);
        sum += @divFloor(num, 3) - 2; // <- weird, but I dig it I guess?
    }

    try std_out.print("{d}\n", .{sum});

    // Lots of try and defer even here. But they make sense coming from Rust.
    // Also I could use debug print which is infallible (errors fail silently).
}
