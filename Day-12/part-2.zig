
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();


const Moon = struct {
    x: i32,
    y: i32, 
    z: i32,
    v_x: i32 = 0,
    v_y: i32 = 0,
    v_z: i32 = 0,
};


// Function type! This is actually a function body type, and must be comptime known.
// A function pointer is prefixed with *const, and can be runtime known.
const Selector = fn (*Moon) *i32;

fn x_selector(moon: *Moon) *i32 { return &moon.x; }
fn y_selector(moon: *Moon) *i32 { return &moon.y; }
fn z_selector(moon: *Moon) *i32 { return &moon.z; }
fn v_x_selector(moon: *Moon) *i32 { return &moon.v_x; }
fn v_y_selector(moon: *Moon) *i32 { return &moon.v_y; }
fn v_z_selector(moon: *Moon) *i32 { return &moon.v_z; }

const Axis = struct {Selector, Selector};


fn lcm(a: usize, b: usize) usize {
    return a * b / std.math.gcd(a, b);
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

    var moon_starts: [4]Moon = undefined;

    var lines_iter = std.mem.splitSequence(u8, input, "\n");
    var idx: usize = 0;
    while (lines_iter.next()) |line| : (idx += 1) {
        var parts_iter = std.mem.splitSequence(u8, line, ",");

        const x_part = parts_iter.next().?;
        var index = std.mem.indexOf(u8, x_part, "=").?;
        const x = try std.fmt.parseInt(i32, x_part[index + 1..], 10);

        const y_part = parts_iter.next().?;
        index = std.mem.indexOf(u8, y_part, "=").?;
        const y = try std.fmt.parseInt(i32, y_part[index + 1..], 10);

        const z_part = parts_iter.next().?;
        index = std.mem.indexOf(u8, z_part, "=").?;
        const z = try std.fmt.parseInt(i32, z_part[index + 1 .. z_part.len - 1], 10);

        moon_starts[idx] = Moon {.x = x, .y = y, .z = z};
    }

    // The trick: We consider each coordinate (x, y, z) seperately, since they have
    // no impact on each other. They will have shorted cycles, which we can combine
    // into a longer cycle.

    const axes: [3]Axis = .{
        Axis {x_selector, v_x_selector},
        Axis {y_selector, v_y_selector},
        Axis {z_selector, v_z_selector},
    };

    var times: [3]usize = undefined;

    inline for (axes, 0..) |axis, axis_num| {
        var moons = moon_starts;  // true copy. Arrays are value types.
        
        var past = std.AutoHashMap([4] Moon, usize).init(alloc);
        defer past.deinit();

        try past.put(moons, 0);

        var time: usize = 1;
        while (true) : (time += 1) {
            for (0..4) |i| {
                for (0..4) |j| {
                    if (i == j) continue;

                    // Caculate effect of moon j on planet i.
                    const pos = axis[0];
                    const vel = axis[1];

                    if (pos(&moons[j]).* > pos(&moons[i]).*) {
                        vel(&moons[i]).* += 1;
                    }
                    else if (pos(&moons[j]).* < pos(&moons[i]).*) {
                        vel(&moons[i]).* -= 1;
                    }
                }
            }

            for (&moons) |*moon| {
                const pos = axis[0];
                const vel = axis[1];

                pos(moon).* += vel(moon).*;
            }

            if (past.get(moons)) |prev_time| {
                if (prev_time != 0) unreachable;

                times[axis_num] = time;
                
                break;
            }

            try past.put(moons, time);
        }
    }

    // Number theory time...
    // No lcm function, but you can build it out of gcd.

    // I think you have to do it piece by piece though?
    
    const cycle_time = lcm(lcm(times[0], times[1]), times[2]);

    try std_out.print("{d}\n", .{cycle_time});
}


// Coding wise not too hard. We had to use function pointers, or what looked like
// function pointers at the time. Actually, it turned out we were using function
// bodies, which must be comptime known (0 cost abstraction, I guess). This almost
// posed a problem since I was accessing them in an array at runtime, but I remembered
// that you can use an inline for loop, which unrolls the loop at comptime. Then,
// all the ints inside the loop become comptime ints, and the array is comptime known,
// the the functions inside the array become comptime known!

// In retrospect, I probably would have just used the pointers though.

// I was pleased by Zig's ability to hash an array of Moon objects without any
// fuss at all. C++ would throw a fit and ask you to write a Hasher struct. I just
// checked, and vectors of hashables are hashable in Rust, so you just need to 
// derive Hash and Eq on your inner type (Moon). That is easy, but its also harder
// than what Zig does!

// The problem itself was quite a bit harder conceptually than the previous ones.
// The first part was trivial, but the second part required figuring out the trick.
// I knew detecting smaller cycles and combining them was a good idea, but for a
// while I couldn't figure out what to split on. Maybe 1 planet has a cycle? That's
// doubtful. Then you realize that the coordinates don't affect each other in the
// slightest, so can be simulated seperately.

// Luckily, all three coordinates cycled back to the start state, so I didn't have
// to bust out (or reinvent) the Chinese Remainer Theorem.
