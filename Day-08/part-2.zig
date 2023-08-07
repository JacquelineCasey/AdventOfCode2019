
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    const gpa_alloc = gpa.allocator();
    defer {
        const code = gpa.deinit();
        if (code == .leak) @panic("Memory leaked");
    }

    const input = try std_in.readToEndAlloc(gpa_alloc, 1_000_000_000);
    defer gpa_alloc.free(input);

    if (input.len % (25 * 6) != 0) return error.BadInputSize;

    const num_layers: usize = input.len / (25 * 6);

    var layers = std.ArrayList([]u8).init(gpa_alloc);
    defer layers.deinit();

    for (0..num_layers) |i| {
        try layers.append(input[i * 25 * 6 .. (i+1) * 25 * 6]);
    }

    var image = ("2" ** (25 * 6)).*;

    for (0..num_layers) |i| {
        for (0..25*6) |j| {
            if (image[j] == '2') {
                image[j] = layers.items[i][j];
            }
        }
    }

    for (0..6) |i| {
        for (0..25) |j| {
            const char: u8 = if (image[i * 25 + j] == '1') '#' else ' ';
            try std_out.print("{c}", .{char});
        }

        try std_out.print("\n", .{});
    }
}

// The relative difficulty between this one and the last one is... surprising.
// Although I have to remember that the 300 lines of IntCode were built up over
// several puzzles, I still wrote like 180 or so lines for it last time.
