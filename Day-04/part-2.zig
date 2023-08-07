
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

    var curr_run_size: u32 = 0;
    var prev_digit: i32 = 11;  // silly trick
    for (0..6) |_| {
        const digit: i32 = @intCast(remaining_password % 10); // explicit cast, but doesn't need actualy type (will be deduced!)
        // Bad cast is "protected undefined behavior", meaning it will be caught in development and some release modes,
        // but will be undefined behavior in optimized builds, allowing for better optimizations.

        remaining_password /= 10;

        if (digit > prev_digit) {
            return false;
        }
        else if (digit == prev_digit) {
            curr_run_size += 1;
        }
        else {
            if (curr_run_size == 2) {
                double_found = true;
            }
            curr_run_size = 1;
        }

        prev_digit = digit;
    }

    return double_found or curr_run_size == 2;  // Don't forget the last iteration!    
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


// I like this... it's convenient
// `zig test part-2.zig`
test "password check function works" {  // Can also just give an identifier instead of a string.
    try std.testing.expect(test_password(112233));
    try std.testing.expect(!test_password(123444));
    try std.testing.expect(test_password(111122));
    try std.testing.expect(test_password(111223));
    try std.testing.expect(test_password(122333));

    // Failure means the function returned an error type.
    // Maybe detectable illegal behavior also counts, but the error type thing is
    //   the intended signal.
}
