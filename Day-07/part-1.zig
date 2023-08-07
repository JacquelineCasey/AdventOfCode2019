
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();

const gpa_alloc = blk: {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    break :blk gpa.allocator();
}; 


// Let's wrap our logic in an IntCodeComputer type

const IntCodeComputer = struct {
    memory: std.ArrayList(i32),
    ip: usize,  // Instruction Pointer

    /// Assumes ownership of memory. Make a copy if necessary.
    fn init(memory: std.ArrayList(i32)) IntCodeComputer  {
        return .{
            .memory = memory,
            .ip = 0,
        };
    }

    fn deinit(self: IntCodeComputer) void {
        self.memory.deinit();
    }

    /// 1 = immediate mode. 0 = position mode
    /// param numbers start at 1
    fn get_param_mode(instruction: i32, param_num: usize) i32 {
        const divisor = std.math.pow(i32, 10, @as(i32, @intCast(1 + param_num))); 
        return @mod(@divTrunc(instruction, divisor), 10);
    }

    fn get_opcode(self: *IntCodeComputer) i32 {
        const instruction = self.memory.items[self.ip];
        self.ip += 1;

        return @mod(instruction, 100);
    }

    /// Given a parameter and which position it is, determines the value
    /// param_num = 1 for first parameter
    /// increments instruction pointer
    fn read_param(self: *IntCodeComputer, param_num: usize) i32 {
        const instruction = self.memory.items[self.ip - param_num];
        const param_mode = get_param_mode(instruction, param_num);

        const result = 
            if (param_mode == 1) self.memory.items[self.ip]
            else self.memory.items[@intCast(self.memory.items[self.ip])];

        self.ip += 1;
        return result;
    }

    fn write_param(self: *IntCodeComputer, param_num: usize, val: i32) !void {
        const instruction = self.memory.items[self.ip - param_num];
        const param_mode = get_param_mode(instruction, param_num);

        if (param_mode == 1) {
            std.debug.print("Error: Output position parameter has immediate mode", .{});
            self.ip += 1;
            return error.BadParameterMode;
        }

        self.memory.items[@intCast(self.memory.items[self.ip])] = val;
        self.ip += 1;
    }

    /// input will not be modified. output will be modified (extended).
    fn run(self: *IntCodeComputer, input: std.ArrayList(i32), output: *std.ArrayList(i32)) !void {
        var input_index: usize = 0;

        while (true) {
            const opcode = self.get_opcode();

            switch (opcode) {
                1 => {  // add
                    const first = self.read_param(1);
                    const second = self.read_param(2);
                    try self.write_param(3, first + second);
                },
                2 => {  // multiply
                    const first = self.read_param(1);
                    const second = self.read_param(2);
                    try self.write_param(3, first * second);
                },
                3 => {  // input
                    if (input_index >= input.items.len) {
                        std.debug.print("Error: Ran out of input", .{});
                        return error.OutOfInput;
                    }

                    const val = input.items[input_index];
                    input_index += 1;
                    try self.write_param(1, val);
                },
                4 => {  // output
                    const val = self.read_param(1);

                    try output.append(val);
                },
                5 => {  // jump-if-true
                    const scrutinee = self.read_param(1);
                    const jump = self.read_param(2);

                    if (scrutinee != 0) {
                        self.ip = @intCast(jump);
                    }
                },
                6 => {  // jump-if-false
                    const scrutinee = self.read_param(1);
                    const jump = self.read_param(2);

                    if (scrutinee == 0) {
                        self.ip = @intCast(jump);
                    }
                },
                7 => {  // less than
                    const first = self.read_param(1);
                    const second = self.read_param(2);
                    try self.write_param(3, if (first < second) 1 else 0);
                },
                8 => {  // equals
                    const first = self.read_param(1);
                    const second = self.read_param(2);
                    try self.write_param(3, if (first == second) 1 else 0);
                },
                99 => {  // halt
                    return;
                },
                else => {
                    std.debug.print("Error: unrecognized opcode at position {d}\n", .{self.ip});
                    return error.UnknownOpcode;
                }
            }       
        }
    }
};


pub fn get_max_signal(used_phases: []bool, base_memory: std.ArrayList(i32), input: i32) !i32 {
    if (std.mem.allEqual(bool, used_phases, true)) {
        return input;
    }
    
    var max_signal: i32 = std.math.minInt(i32);
    for (0..5) |phase_num| {
        if (!used_phases[phase_num]) {
            used_phases[phase_num] = true;

            var input_buffer = std.ArrayList(i32).init(gpa_alloc);
            defer input_buffer.deinit();
            try input_buffer.append(@intCast(phase_num));
            try input_buffer.append(input);

            var output_buffer = std.ArrayList(i32).init(gpa_alloc);
            defer output_buffer.deinit();

            var computer = IntCodeComputer.init(try base_memory.clone());
            defer computer.deinit();

            try computer.run(input_buffer, &output_buffer);

            max_signal = @max(
                max_signal, 
                try get_max_signal(used_phases, base_memory, output_buffer.items[0])
            );

            used_phases[phase_num] = false;
        }
    }

    return max_signal;
}


pub fn main() !void {
    const input = try std_in.readToEndAlloc(gpa_alloc, 1_000_000_000);
    defer gpa_alloc.free(input);

    var base_memory = std.ArrayList(i32).init(gpa_alloc);
    defer base_memory.deinit();

    var it = std.mem.splitSequence(u8, input, ",");
    while (it.next()) |substring| 
        try base_memory.append(try std.fmt.parseInt(i32, substring, 10));
    

    var used_phases: [5]bool = .{false, false, false, false, false};
    const result = try get_max_signal(used_phases[0..], base_memory, 0);

    try std_out.print("{d}\n", .{result});
}
