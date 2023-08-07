
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();

const gpa_alloc = blk: {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    break :blk gpa.allocator();
}; 




/// 1 = immediate mode. 0 = position mode
/// param numbers start at 1
fn get_param_mode(instruction: i32, param_num: usize) i32 {
    const divisor = std.math.pow(i32, 10, @as(i32, @intCast(1 + param_num)));
    return @mod(@divTrunc(instruction, divisor), 10);
}


fn get_opcode(ip: *usize, memory: std.ArrayList(i32)) i32 {
    const instruction = memory.items[ip.*];
    ip.* += 1;

    return @mod(instruction, 100);
}

/// Given a parameter and which position it is, determines the value
/// param_num = 1 for first parameter
/// increments instruction pointer
fn read_param(ip: *usize, param_num: usize, memory: std.ArrayList(i32)) i32 {
    const instruction = memory.items[ip.* - param_num];
    const param_mode = get_param_mode(instruction, param_num);

    const result = 
        if (param_mode == 1) memory.items[ip.*]
        else memory.items[@intCast(memory.items[ip.*])];

    ip.* += 1;
    return result;
}

fn write_param(ip: *usize, param_num: usize, memory: std.ArrayList(i32), val: i32) !void {
    const instruction = memory.items[ip.* - param_num];
    const param_mode = get_param_mode(instruction, param_num);

    if (param_mode == 1) {
        std.debug.print("Error: Output position parameter has immediate mode", .{});
        ip.* += 1;
        return error.BadParameterMode;
    }

    memory.items[@intCast(memory.items[ip.*])] = val;
    ip.* += 1;
}


// Arrays are a little odd. I can modify input, but I can't call append.
// To make append work, I want a pointer.
// Like, append could swing the underlying pointer, right? So that "modifies" the ArrayList
// But hopping through the pointer to the data and changing that is not considered modification.

/// input will not be modified. output will be modified (extended). memory will be modified in place.
fn run_intcode(memory: std.ArrayList(i32), input: std.ArrayList(i32), output: *std.ArrayList(i32)) !void {
    var ip: usize = 0; // instruction_pointer
    var input_index: usize = 0;

    while (true) {
        const opcode = get_opcode(&ip, memory);

        switch (opcode) {
            1 => {  // add
                const first = read_param(&ip, 1, memory);
                const second = read_param(&ip, 2, memory);
                try write_param(&ip, 3, memory, first + second);
            },
            2 => {  // multiply
                const first = read_param(&ip, 1, memory);
                const second = read_param(&ip, 2, memory);
                try write_param(&ip, 3, memory, first * second);
            },
            3 => {  // input
                if (input_index >= input.items.len) {
                    std.debug.print("Error: Ran out of input", .{});
                    return error.OutOfInput;
                }

                const val = input.items[input_index];
                input_index += 1;
                try write_param(&ip, 1, memory, val);
            },
            4 => {  // output
                const val = read_param(&ip, 1, memory);

                try output.append(val);
            },
            99 => {  // halt
                return; // I think we return nothing now.
            },
            else => {
                std.debug.print("Error: unrecognized opcode at position {d}\n", .{ip});
                return error.UnknownOpcode;
            }
        }       
    }
}


pub fn main() !void {
    const input = try std_in.readToEndAlloc(gpa_alloc, 1_000_000_000);
    defer gpa_alloc.free(input);

    var memory = std.ArrayList(i32).init(gpa_alloc);
    defer memory.deinit();

    var it = std.mem.splitSequence(u8, input, ",");
    while (it.next()) |substring| 
        try memory.append(try std.fmt.parseInt(i32, substring, 10));


    var input_buffer = std.ArrayList(i32).init(gpa_alloc);
    defer input_buffer.deinit();
    try input_buffer.append(1);
    
    var output_buffer = std.ArrayList(i32).init(gpa_alloc);
    defer output_buffer.deinit();

    try run_intcode(memory, input_buffer, &output_buffer);
    
    try std_out.print("{any}\n", .{output_buffer.items});

    // Verfiy the early outputs are 0s, and then the answer is the last output.
}
