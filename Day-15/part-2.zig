
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

const Pair = struct {i32, i32};

const Direction = enum(u3) {
    North = 1,
    South = 2,
    West = 3,
    East = 4,

    fn update_coords(self: Direction, x: *i32, y: *i32) void {
        switch (self) {
            .North => y.* -= 1,
            .South => y.* += 1,
            .West => x.* -= 1,
            .East => x.* += 1
        }
    }

    fn shift_coords(self: Direction, pair: Pair) Pair {
        var x = pair[0];
        var y = pair[1];

        self.update_coords(&x, &y);
        return .{x, y};
    }

    fn opposite(self: Direction) Direction {
        return switch (self) {
            .North => .South,
            .South => .North,
            .West => .East,
            .East => .West
        };
    }
};


fn explore(computer: *IntCodeComputer, x_pos: *i32, y_pos: *i32, 
    direction: Direction, seen_coordinates: *std.AutoHashMap(Pair, bool)) !void {

    try computer.push_input(@intFromEnum(direction));
    try computer.run();
    const status = computer.pop_output().?;

    if (status == 0) {  // Droid hit wall
        return;
    }

    direction.update_coords(x_pos, y_pos);

    const new_square = (try seen_coordinates.fetchPut(.{x_pos.*, y_pos.*}, status == 2)) == null;

    if (new_square) {
        for (1 .. 4 + 1) |i| {
            try explore(computer, x_pos, y_pos, @enumFromInt(i), seen_coordinates);
        }
    }


    try computer.push_input(@intFromEnum(direction.opposite()));
    try computer.run();
    const final_status = computer.pop_output().?;

    direction.opposite().update_coords(x_pos, y_pos);

    if (final_status == 0) {  // Droid hit wall
        return error.DroidGotConfused;
    }
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

    // True represents the oxygen system
    var seen_coordinates = std.AutoHashMap(Pair, bool).init(alloc);
    defer seen_coordinates.deinit();

    try seen_coordinates.put(.{0, 0}, false);

    var x_pos: i32 = 0;
    var y_pos: i32 = 0;

    for (1 .. 4 + 1) |i| {
        try explore(&computer, &x_pos, &y_pos, @enumFromInt(i), &seen_coordinates);
    }


    var maybe_start_pair: ?Pair = null;
    var iter = seen_coordinates.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.*) {
            maybe_start_pair = entry.key_ptr.*;
        }
    }

    const start_pair = maybe_start_pair.?;

    var edge = std.ArrayList(Pair).init(alloc);
    defer edge.deinit();
    try edge.append(start_pair);

    var next_edge = std.ArrayList(Pair).init(alloc);
    defer next_edge.deinit();

    var bfs_visited = std.AutoHashMap(Pair, void).init(alloc);
    defer bfs_visited.deinit();
    try bfs_visited.put(.{0, 0}, {});

    var steps: u32 = 0;
    while (edge.items.len > 0) {
        steps += 1;

        for (edge.items) |pair| {
            for (1 .. 4 + 1) |i| {
                const dir: Direction = @enumFromInt(i);
                const neighbor = dir.shift_coords(pair);

                if (seen_coordinates.get(neighbor)) |_| {
                    if (try bfs_visited.fetchPut(neighbor, {}) == null) {
                        try next_edge.append(neighbor);
                    }
                }
            }
        }

        const tmp = edge;
        edge = next_edge;
        next_edge = tmp;
        next_edge.clearRetainingCapacity();
    }

    try std_out.print("{d}\n", .{steps - 1});  // We overcount by 1
}


// Part 2 was super easy! That's a nice surprise, all you have to do is DFS from
// a different location. If you somehow didn't do DFS for part 1, then you definitely
// had to do it here.

// Zig was pleasant. I made a bunch of allocations that I of course had to take
// a second step to dealloc. Also, I had to adjust how I normally write DFS in
// order to do fewer allocations. I guess I didn't have to, but I ultimately
// wanted to, since Zig makes it super obvious where an allocation happens. Instead
// of building a new temp edge, I swapped two array lists back and forth. I bet
// Rust would be fussy there, but I'm not sure. Ok I checked rust is fine with
// it, I guess I was conflating the move rules with the borrow rules. Still, it
// says something about learning curve that I likely would have avoided the optimization
// out of suspicioun of the borrow checker.
