
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

    /// 1 = immediate mode. 0 = position mode
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
        if (self.state == .Terminated) {
            return error.ProgramTerminated;
        }

        while (true) {
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
                    std.debug.print("Error: unrecognized opcode at position {d}\n", .{self.ip});
                    return error.UnknownOpcode;
                }
            }       
        }
    }
};


//---- Application ----//

const Direction = enum(u2) {
    Up,
    Right,
    Down,
    Left,

    fn turnLeft(self: Direction) Direction {
        return switch (self) {
            .Up => .Left,
            .Right => .Up,
            .Down => .Right,
            .Left => .Down
        };
    }

    fn turnRight(self: Direction) Direction {
        return switch (self) {
            .Up => .Right,
            .Right => .Down,
            .Down => .Left,
            .Left => .Up
        };
    }

    fn updatePosition(self: Direction, x: *i32, y: *i32) void {
        switch (self) {
            .Up => y.* -= 1,  // Remember, up is negative so we can print this normally
            .Right => x.* += 1,
            .Down => y.* += 1,
            .Left => x.* -= 1,
        }
    }
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

    var base_memory = std.AutoHashMap(usize, i64).init(alloc);
    // computer takes ownership

    var it = std.mem.splitSequence(u8, input, ",");
    var index: usize = 0;
    while (it.next()) |substring| {
        try base_memory.put(index, try std.fmt.parseInt(i64, substring, 10));

        index += 1;
    }

    var computer = IntCodeComputer.init(base_memory, alloc);
    defer computer.deinit();

    var tiles = std.AutoHashMap(struct {i32, i32}, bool).init(alloc);  // key type defined interestingly. I think this is a tuple?
    defer tiles.deinit();

    var robot_x: i32 = 0;
    var robot_y: i32 = 0;
    var robot_dir = Direction.Up;
    while (computer.state != .Terminated) {
        if (computer.state == .AwaitingInput) {
            if (tiles.get(.{robot_x, robot_y})) |tile| {
                try computer.push_input(@intFromBool(tile));
            }
            else {
                try computer.push_input(0);  // All tiles start black
            }
        }

        try computer.run();

        const maybe_output_1 = computer.pop_output();
        const maybe_output_2 = computer.pop_output();

        if (maybe_output_1) |color| {
            const turn = maybe_output_2.?;

            try tiles.put(.{robot_x, robot_y}, color == 1);

            if (turn == 0) {
                robot_dir = robot_dir.turnLeft();
            }
            else if (turn == 1) {
                robot_dir = robot_dir.turnRight();
            }
            else {
                return error.UnknownDirection;
            }

            robot_dir.updatePosition(&robot_x, &robot_y);
        }

        if (computer.pop_output() != null) return error.TooMuchOutput;
    }

    try std_out.print("{d}\n", .{tiles.count()});
}
