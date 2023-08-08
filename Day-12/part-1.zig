
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


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    const alloc = gpa.allocator();
    defer {
        const code = gpa.deinit();
        if (code == .leak) @panic("Memory leaked");
    }

    const input = try std_in.readToEndAlloc(alloc, 1_000_000_000);
    defer alloc.free(input);

    var moons: [4]Moon = undefined;

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

        moons[idx] = Moon {.x = x, .y = y, .z = z};
    }

    for (0..1000) |_| {
        for (0..4) |i| {
            for (0..4) |j| {
                if (i == j) continue;

                // Caculate effect of moon j on planet i.
                if (moons[j].x > moons[i].x) {
                    moons[i].v_x += 1;
                }
                else if (moons[j].x < moons[i].x) {
                    moons[i].v_x -= 1;
                }

                if (moons[j].y > moons[i].y) {
                    moons[i].v_y += 1;
                }
                else if (moons[j].y < moons[i].y) {
                    moons[i].v_y -= 1;
                }

                if (moons[j].z > moons[i].z) {
                    moons[i].v_z += 1;
                }
                else if (moons[j].z < moons[i].z) {
                    moons[i].v_z -= 1;
                }
            }
        }

        for (&moons) |*moon| {
            moon.x += moon.v_x;
            moon.y += moon.v_y;
            moon.z += moon.v_z;
        }
    }

    var energy_sum: i32 = 0;
    for (moons) |moon| {
        const abs = std.math.absInt;
        energy_sum += (try abs(moon.x) + try abs(moon.y) + try abs(moon.z)) 
            * (try abs(moon.v_x) + try abs(moon.v_y) + try abs(moon.v_z));
    }

    try std_out.print("{d}\n", .{energy_sum});
}
