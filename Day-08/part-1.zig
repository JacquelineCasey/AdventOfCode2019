
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

    var fewest_layer_index: usize = 0;
    var fewest_layer_zeros: u32 = 25 * 6 + 1;

    for (0..num_layers) |i| {
        var zero_count: u32 = 0;

        for (layers.items[i]) |digit| {
            if (digit == '0') {
                zero_count += 1;
            }
        }

        if (zero_count < fewest_layer_zeros) {
            fewest_layer_zeros = zero_count;
            fewest_layer_index = i;
        }
    }

    var ones: u32 = 0;
    var twos: u32 = 0;
    for (layers.items[fewest_layer_index]) |digit| {
        if (digit == '1') {
            ones += 1;
        }
        if (digit == '2') {
            twos += 1;
        }
    }

    try std_out.print("{d}\n", .{ones * twos});
}
