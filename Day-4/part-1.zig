
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();

const gpa_alloc = blk: {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    break :blk gpa.allocator();
}; 


fn test_password(password: usize) bool {
    var remaining_password = password;  // Note parameters are always constant.

    // iterate right to left on digits

    var double_found = false;
    var prev_digit: i32 = 11;  // silly trick
    for (0..6) |_| {
        const digit: i32 = @intCast(remaining_password % 10);
        remaining_password /= 10;

        if (digit > prev_digit) {
            return false;
        }
        if (digit == prev_digit) {
            double_found = true;
        }

        prev_digit = digit;
    }

    return double_found;    
}
// That was remarkably annoying to write. Particularly since I had to use usize,
// because thats what comes out of the for loop down there? Maybe an explicit loop makes
// more since.
// Zig forces you to think about integer size and signedness a lot...


pub fn main() !void {
    const input = try std_in.readToEndAlloc(gpa_alloc, 1_000_000_000);
    defer gpa_alloc.free(input);

    var parts = std.mem.splitSequence(u8, input, "-");
    const lower_bound = try std.fmt.parseInt(usize, parts.next().?, 10);
    const upper_bound = try std.fmt.parseInt(usize, parts.next().?, 10);

    var sum: u32 = 0;
    for (lower_bound..upper_bound+1) |password| {
        if (test_password(password)) sum += 1;
    }

    try std_out.print("{d}\n", .{sum});
}
