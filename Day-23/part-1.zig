
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();


//---- Defines the IntCode Computer ----//

// Wraps TailQueue in a more friendly interface (takes care of allocation).
pub fn Queue(comptime T: type) type {
    return struct {
        const Self = @This();
        const Node = std.TailQueue(T).Node;

        tail_queue: std.TailQueue(T),
        alloc: std.mem.Allocator,

        fn init(alloc: std.mem.Allocator) Self {
            return .{
                .tail_queue = .{},
                .alloc = alloc,
            };
        }

        fn deinit(self: *Self) void {
            while (self.tail_queue.len > 0) {
                _ = self.pop();
            }
        }

        /// Add element to back of queue
        fn push(self: *Self, item: T) !void {
            const node = try self.alloc.create(Node);
            node.data = item;
            self.tail_queue.append(node);
        }

        /// Remove element from front of queue
        fn pop(self: *Self) ?T {
            const node = self.tail_queue.popFirst() orelse return null;
            const val = node.data;
            self.alloc.destroy(node);
            return val;
        }

        fn len(self: *Self) usize {
            return self.tail_queue.len;
        }
    };
}

const State = enum(u2) {
    Runnable,
    AwaitingInput,
    Terminated,
    Error,
};

const IntCodeComputer = struct {
    input: Queue(i64),
    output: Queue(i64),
    memory: std.AutoHashMap(usize, i64),
    ip: usize,  // Instruction Pointer
    relative_base: i64,
    state: State,

    /// Takes ownership of memory. Caller should make a copy if necessary.
    fn init(memory: std.AutoHashMap(usize, i64), alloc: std.mem.Allocator) IntCodeComputer  {
        return .{
            .input = Queue(i64).init(alloc),
            .output = Queue(i64).init(alloc),
            .memory = memory,
            .ip = 0,
            .relative_base = 0,
            .state = .Runnable,
        };
    }

    fn deinit(self: *IntCodeComputer) void {
        self.memory.deinit();
        self.input.deinit();
        self.output.deinit();
    }

    fn push_input(self: *IntCodeComputer, item: i64) !void {
        return try self.input.push(item);
    }

    fn pop_output(self: *IntCodeComputer) ?i64 {
        return self.output.pop();
    } 

    /// Does not modify input in any way. Be careful with newlines.
    fn push_ascii_input(self: *IntCodeComputer, ascii: []const u8) !void {
        for (ascii) |ch| {
            try self.push_input(ch);
        }
    }

    /// 2 = realtive mode, 1 = immediate mode, 0 = position mode
    /// param numbers start at 1
    fn get_param_mode(instruction: i64, param_num: usize) i64 {
        const divisor = std.math.pow(i64, 10, @as(i64, @intCast(1 + param_num))); 
        return @mod(@divTrunc(instruction, divisor), 10);
    }

    fn get_opcode(self: *IntCodeComputer) !i64 {
        const instruction = try self.read_memory(self.ip);
        self.ip += 1;

        return @mod(instruction, 100);
    }

    fn read_memory(self: *IntCodeComputer, position: usize) !i64 {
        return self.memory.get(position) orelse {
            try self.memory.put(position, 0);
            return 0;
        };
    }

    fn write_memory(self: *IntCodeComputer, position: usize, val: i64) !void {
        try self.memory.put(position, val);
    }

    /// Given a parameter and which position it is, determines the value
    /// param_num = 1 for first parameter
    /// increments instruction pointer
    fn read_param(self: *IntCodeComputer, param_num: usize) !i64 {
        const instruction = try self.read_memory(self.ip - param_num);
        const param_mode = get_param_mode(instruction, param_num);

        defer self.ip += 1;

        switch (param_mode) {
            0 => {  // Position
                const pos = try self.read_memory(self.ip);
                return self.read_memory(@intCast(pos));
            },
            1 => {  // Immediate
                return self.read_memory(self.ip);
            },
            2 => {  // Relative
                const pos = self.relative_base + try self.read_memory(self.ip);
                return self.read_memory(@intCast(pos));
            },
            else => {
                std.debug.print("Error: Unrecognized parameter access mode: {d}\n", .{param_mode});
                return error.UnknownAccessMode;
            }
        }
    }

    /// Param 1 for first parameter. Increments instruction pointer.
    fn write_param(self: *IntCodeComputer, param_num: usize, val: i64) !void {
        const instruction = try self.read_memory(self.ip - param_num);
        const param_mode = get_param_mode(instruction, param_num);

        defer self.ip += 1;

        switch (param_mode) {
            0 => {  // Position
                const pos = try self.read_memory(self.ip);
                try self.write_memory(@intCast(pos), val);
            },
            1 => {  // Immediate
                std.debug.print("Error: Output position parameter has immediate mode\n", .{});
                return error.BadParameterMode;
            },
            2 => {  // Relative
                const pos = self.relative_base + try self.read_memory(self.ip);
                try self.write_memory(@intCast(pos), val);
            },
            else => {
                std.debug.print("Error: Unrecognized parameter access mode: {d}\n", .{param_mode});
                return error.UnknownAccessMode;
            }
        }
    }

    /// Runs computer until termination or uses all input (in which case it suspends).
    fn run(self: *IntCodeComputer) !void {
        while (self.state == .Runnable) {
            try self.run_one_instruction();
        }
    }

    fn run_one_instruction(self: *IntCodeComputer) !void {
        if (self.state == .Terminated) {
            return error.ProgramTerminated;
        }

        const opcode = try self.get_opcode();

        switch (opcode) {
            1 => {  // add
                const first = try self.read_param(1);
                const second = try self.read_param(2);
                try self.write_param(3, first + second);
            },
            2 => {  // multiply
                const first = try self.read_param(1);
                const second = try self.read_param(2);
                try self.write_param(3, first * second);
            },
            3 => {  // input
                if (self.input.pop()) |val| {
                    self.state = .Runnable;
                    try self.write_param(1, val);
                }
                else {
                    self.state = .AwaitingInput;
                    self.ip -= 1;  // Return to input instruction
                    return;
                }
            },
            4 => {  // output
                const val = try self.read_param(1);

                try self.output.push(val);
            },
            5 => {  // jump-if-true
                const scrutinee = try self.read_param(1);
                const jump = try self.read_param(2);

                if (scrutinee != 0) {
                    self.ip = @intCast(jump);
                }
            },
            6 => {  // jump-if-false
                const scrutinee = try self.read_param(1);
                const jump = try self.read_param(2);

                if (scrutinee == 0) {
                    self.ip = @intCast(jump);
                }
            },
            7 => {  // less than
                const first = try self.read_param(1);
                const second = try self.read_param(2);
                try self.write_param(3, if (first < second) 1 else 0);
            },
            8 => {  // equals
                const first = try self.read_param(1);
                const second = try self.read_param(2);
                try self.write_param(3, if (first == second) 1 else 0);
            },
            9 => {  // relative base offset
                const change = try self.read_param(1);
                self.relative_base += change;
            },
            99 => {  // halt
                self.state = .Terminated;
                return;
            },
            else => {
                self.state = .Error;
                std.debug.print("Error: unrecognized opcode {d} at position {d}\n", .{opcode, self.ip});
                return error.UnknownOpcode;
            }
        }       
    }
};


//---- Application ----//

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    const alloc = gpa.allocator();
    defer {
        const code = gpa.deinit();
        if (code == .leak) @panic("Memory leaked");
    }

    const input = try std_in.readToEndAlloc(alloc, 1_000_000_000);  
    defer alloc.free(input);

    var base_memory = std.AutoHashMap(usize, i64).init(alloc);
    defer base_memory.deinit();

    var it = std.mem.splitSequence(u8, input, ",");
    var index: usize = 0;
    while (it.next()) |substring| {
        try base_memory.put(index, try std.fmt.parseInt(i64, substring, 10));
        index += 1;
    }

    var computers: [50]IntCodeComputer = undefined;
    defer {
        for (&computers) |*computer| computer.deinit();
    }

    for (0..50) |i| {
        computers[i] = IntCodeComputer.init(try base_memory.clone(), alloc);

        try computers[i].push_input(@intCast(i));
    }

    while (true) {
        for (&computers) |*computer| {
            if (computer.state == .Runnable) {
                try computer.run_one_instruction();
            }
            else if (computer.state == .AwaitingInput) {
                try computer.push_input(-1);
                try computer.run_one_instruction();
            }

            while (computer.output.len() >= 3) {
                const addr = computer.pop_output().?;
                const X = computer.pop_output().?;
                const Y = computer.pop_output().?;

                if (addr == 255) {
                    try std_out.print("{d}\n", .{Y});

                    return;
                }
                else {
                    try computers[@intCast(addr)].push_input(X);
                    try computers[@intCast(addr)].push_input(Y);
                }
            }
        }
    }


}
