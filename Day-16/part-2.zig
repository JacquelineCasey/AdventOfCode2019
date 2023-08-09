
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();


const PatternIterator = struct {
    n: u32,
    i: u32,

    fn next(self: *PatternIterator) ?i32 {
        self.i += 1;  // Therefore we really start at 1.

        const pos = (self.i % (4 * self.n)) / self.n;

        return switch (pos) {
            0 => 0,
            1 => 1,
            2 => 0,
            3 => -1,
            else => unreachable
        };
    }
};

// Expects n to be position in an array (i.e. >= 0)
fn pattern_iterator(n: u32) PatternIterator {
    return .{.n = n + 1, .i = 0};
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

    const output_pos = try std.fmt.parseInt(u32, input[0..7], 10);

    var initial_nums = std.ArrayList(i32).init(alloc);
    defer initial_nums.deinit();

    for (0..10000) |_| {
        for (input) |ch| {
            try initial_nums.append(ch - '0');
        }
    }

    if (output_pos < initial_nums.items.len / 2) {
        return error.BadOutputPosition;  // Algorithm only works to find digits in later half of input.
    }

    var nums = std.ArrayList(i32).init(alloc);
    defer nums.deinit();

    // Trick - we only care about suffix, it turns out the previous entries are irrelevant.
    for (initial_nums.items[output_pos..]) |num| {
        try nums.append(num);
    }

    for (0..100) |_| {
        var sum: i32 = 0;
        var i: i32 = @as(i32, @intCast(nums.items.len)) - 1;

        while (i >= 0) : (i -= 1) {
            sum += nums.items[@intCast(i)];
            nums.items[@intCast(i)] = try std.math.absInt(@rem(sum, 10));
        }
    }

    for (0..8) |i| {
        try std_out.print("{d}", .{nums.items[i]});
    }

    try std_out.print("\n", .{});
}

// More of a conceptual problem. Wrote fairly little code, and in fact the code
// for the second part is simpler than that for the first part.

// The only thing to note about Zig is that it is really picky when it comes to
// properly casting ints. This makes a backwards iteration more annoying as you
// dance around the fact that you eventually have to go negative. I also got a
// segfault, with a really incomplete error trace. It turns out that this happens
// if you deinit the same thing twice. This wasn't hard to spot.

// The first part can be solved honestly. I uses an iterator, which Zig makes
// pretty easy to define to be honest (I should try doing that in Rust. I know for
// a fact that defining C++ iterators is insufferable). The second part requires
// 3 realizations - first, each digit only depends on itself and the digits to
// the right; second - after the halfway point, the pattern degenerates into a
// set of 0s followed by a set of 1s that starts at the digit in question; third
// - the code we care about is located in the second half.

// As a result, we can replace a step of the FFT algorithm with a much faster
// cumulative sum operation.
