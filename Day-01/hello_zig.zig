
const std = @import("std");

const stdout = std.io.getStdOut().writer();
// const debug = std.debug.print;

pub fn main() !void {
    try stdout.print("Hello, World!\n", .{});
    // debug("Hello, World!\n", .{});
}
