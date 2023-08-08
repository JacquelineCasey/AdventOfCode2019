
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

const Pair = struct {i64, i64};

const Tile = enum(u3) {
    Empty = 0,
    Wall = 1,
    Block = 2,
    Paddle = 3,
    Ball = 4,

    fn char(self: Tile) u8 {
        return switch (self) {
            .Empty => ' ',
            .Wall => '#',
            .Block => 'O',
            .Paddle => '=',
            .Ball => '*',
        };
    }
};


fn print_tiles(tiles: std.AutoHashMap(Pair, Tile), score: i32) !void {
    var min_x: i64 = 1000;
    var max_x: i64 = -1000;
    var min_y: i64 = 1000;
    var max_y: i64 = -1000;

    var pair_iter = tiles.keyIterator();
    while (pair_iter.next()) |pair| {
        min_x = @min(min_x, pair[0]);
        max_x = @max(max_x, pair[0]);
        min_y = @min(min_y, pair[1]);
        max_y = @max(max_y, pair[1]);
    }

    try std_out.print("\nscore: {d}\n", .{score});
        
    var y: i64 = min_y;
    while (y <= max_y) : (y += 1) {
        var x: i64 = min_x;

        while (x <= max_x) : (x += 1) {
            const char = (tiles.get(.{x, y}) orelse Tile.Empty).char(); 
            try std_out.print("{c}", .{char});
        }

        try std_out.print("\n", .{});
    }

    try std_out.print("\n", .{});
}


fn pick_move(tiles: std.AutoHashMap(Pair, Tile)) i64 {
    var ball_x: ?i64 = null;
    var paddle_x: ?i64 = null;

    var iter = tiles.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.* == .Ball) {
            ball_x = entry.key_ptr[0];
        }
        if (entry.value_ptr.* == .Paddle) {
            paddle_x = entry.key_ptr[0];
        }
    }

    if (ball_x.? < paddle_x.?) {
        return -1;
    }
    else if (ball_x.? > paddle_x.?) {
        return 1;
    }
    return 0;
}


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    const alloc = gpa.allocator();
    defer {
        const code = gpa.deinit();
        if (code == .leak) @panic("Memory leaked");
    }

    const file = try std.fs.cwd().openFile("input.txt", .{});

    const input = try file.readToEndAlloc(alloc, 1_000_000_000);
    defer alloc.free(input);

    var base_memory = std.AutoHashMap(usize, i64).init(alloc);
    // computer takes ownership

    var it = std.mem.splitSequence(u8, input, ",");
    var index: usize = 0;
    while (it.next()) |substring| {
        try base_memory.put(index, try std.fmt.parseInt(i64, substring, 10));

        index += 1;
    }

    try base_memory.put(0, 2);  // Quarters 

    var computer = IntCodeComputer.init(base_memory, alloc);
    defer computer.deinit();  

    var screen = std.AutoHashMap(Pair, Tile).init(alloc);
    defer screen.deinit();

    // Uncomment for user input.

    // var input_reader = std_in.reader();
    // var in_array = std.ArrayList(u8).init(alloc);
    // defer in_array.deinit();

    var score: i32 = 0;
    while (computer.state != .Terminated) {
        if (computer.state == .AwaitingInput) {
            // in_array.clearRetainingCapacity();

            // try std_out.print("input: ", .{});
            // try input_reader.streamUntilDelimiter(in_array.writer(), '\n', null);


            // if (std.mem.eql(u8, in_array.items, "")) {
            //     try computer.push_input(0);
            // }
            // else if (std.mem.eql(u8, in_array.items, "a")) {
            //     try computer.push_input(-1);
            // }
            // else if (std.mem.eql(u8, in_array.items, "d")) {
            //     try computer.push_input(1);
            // }


            // Instead we will choose the move automatically
            try computer.push_input(pick_move(screen));
        }

        try computer.run();

        while (computer.pop_output()) |x| {
            const y = computer.pop_output().?;
            const tile = computer.pop_output().?;

            if (x == -1 and y == 0) {
                score = @intCast(tile);
            }
            else {
                try screen.put(.{x, y}, @enumFromInt(tile));
            }
        }

        // show output

        // try print_tiles(screen, score);
        // std.time.sleep(10_000_000);
    }

    try std_out.print("{d}\n", .{score});
}

// Run without input this time.


// Yeah, that was pretty cool. I like how you spent time making the game, then 
// realize that it is hard to beat, then you spend time automating the game.

// Zig-wise - I ended up poking around with files and reading input in other ways.
// It was a little annoying at first, I wish there was better documentation. Not
// terrible though. We also saw the conversion of int to enum, which was nice. I
// like how every cast in Zig has an explicit builtin function - we would use the
// same two things in C++, but this makes the code more readable IMO.
