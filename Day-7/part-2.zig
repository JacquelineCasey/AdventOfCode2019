
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();

var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
const gpa_alloc = gpa.allocator();


/// Wrap TailQueue in a friendlier interface. I'm surprised I need pointers and allocation for TailQueue
/// Gives me an excuse to play with generics
pub fn Queue(comptime T: type) type {
    return struct {
        const Self = @This();
        const Node = std.TailQueue(T).Node;

        tail_queue: std.TailQueue(i32),
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


const State = enum(u2) {  // I love that we have access to these itty bitty integer types.
    Runnable,             // Like, other languages are afraid of overflow, so they put big
    AwaitingInput,        // gaps between their integer types so you don't get temptyed to
    Terminated,           // overoptimize. But Zig knows that you won't overflow at least 
    Error,                // in safe mode, so it doesn't care. I bet u2 is actually a byte
};                        // most of the time though, so the gains are probably litterall zero.


// Let's wrap our logic in an IntCodeComputer type
// Now we need to include input and ouput in the struct. They will be queues.

const IntCodeComputer = struct {
    input: Queue(i32),
    output: Queue(i32),
    memory: std.ArrayList(i32),
    ip: usize,  // Instruction Pointer
    state: State,

    /// Takes ownership of memory. Make a copy if necessary.
    fn init(memory: std.ArrayList(i32), alloc: std.mem.Allocator) IntCodeComputer  {
        return .{
            .input = Queue(i32).init(alloc),
            .output = Queue(i32).init(alloc),
            .memory = memory,
            .ip = 0,
            .state = .Runnable,
        };
    }

    fn deinit(self: *IntCodeComputer) void {
        self.memory.deinit();
        self.input.deinit();
        self.output.deinit();
    }

    fn push_input(self: *IntCodeComputer, item: i32) !void {
        return try self.input.push(item);
    }

    fn pop_output(self: *IntCodeComputer) ?i32 {
        return self.output.pop();
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

    /// Runs computer until termination or uses all input (in which case it suspends).
    fn run(self: *IntCodeComputer) !void {
        if (self.state == .Terminated) {
            return error.ProgramTerminated;
        }

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
                    const val = self.read_param(1);

                    try self.output.push(val);
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


// Let's write an iterator!

const Permutations = struct {
    base_array: []i32,
    scratch_array: []i32,
    permutation_num: usize,
    alloc: std.mem.Allocator,
    max: usize,

    fn init(base_array: []i32, alloc: std.mem.Allocator) !Permutations {
        var val = Permutations {
            .base_array = try alloc.alloc(i32, base_array.len),
            .scratch_array = try alloc.alloc(i32, base_array.len),
            .permutation_num = 0,
            .alloc = alloc,
            .max = blk: {
                var product: usize = 1;
                for (1..base_array.len + 1) |num| {
                    product *= num;
                }

                break :blk product;
            },
        };

        @memcpy(val.base_array, base_array);
        return val;
    }

    fn deinit(self: Permutations) void {
        self.alloc.free(self.base_array);
        self.alloc.free(self.scratch_array);
    }

    fn next(self: *Permutations) ?[]i32 {
        if (self.permutation_num >= self.max) {
            return null;
        }

        var temp = self.permutation_num;

        @memcpy(self.scratch_array, self.base_array);

        for (0..self.base_array.len) |i| {
            std.mem.swap(i32, &self.scratch_array[i], &self.scratch_array[i + (temp % (self.base_array.len - i))]);
            temp /= self.base_array.len - i;
        }

        self.permutation_num += 1;

        return self.scratch_array;
    }
};


fn run_permutation(phases: []i32, base_memory: std.ArrayList(i32), alloc: std.mem.Allocator) !i32 {
    var computers = std.ArrayList(IntCodeComputer).init(alloc);
    defer computers.deinit();

    defer {
        for (computers.items) |*comp| {
            comp.deinit();
        }
    }

    for (phases) |phase| {
        var curr = IntCodeComputer.init(try base_memory.clone(), alloc);
        try curr.push_input(phase);

        try computers.append(curr);
    }

    try computers.items[0].push_input(0);

    while (computers.getLast().state != .Terminated) {
        for (0..5) |i| {
            // Move output from previous computer
            while (computers.items[(i + 4) % 5].pop_output()) |item| {
                try computers.items[i].push_input(item);
            }

            try computers.items[i].run();
        }
    }

    var final: ?i32 = null;
    while (computers.items[4].pop_output()) |num| {
        final = num;
    }

    return final orelse return error.NoFinalOutput;
}


pub fn main() !void {
    // Check for memory leaks
    defer {
        const code = gpa.deinit();
        if (code == .leak) @panic("Memory leaked");
    }

    const input = try std_in.readToEndAlloc(gpa_alloc, 1_000_000_000);
    defer gpa_alloc.free(input);

    var base_memory = std.ArrayList(i32).init(gpa_alloc);
    defer base_memory.deinit();

    var it = std.mem.splitSequence(u8, input, ",");
    while (it.next()) |substring| 
        try base_memory.append(try std.fmt.parseInt(i32, substring, 10));


    var nums = [_]i32 {5, 6, 7, 8, 9}; 
    var perm_it = try Permutations.init(&nums, gpa_alloc);
    defer perm_it.deinit();

    var maximum: i32 = std.math.minInt(i32);
    while (perm_it.next()) |perm| {
        const result = try run_permutation(perm, base_memory, gpa_alloc);
        maximum = @max(maximum, result);
    }

    try std_out.print("{d}\n", .{maximum});
}


// Took more of an OO approach this time. It was surprisingly pleasant, actually.
// The only thing thats a bit of a pain is passing the allocator everywhere and
// defering the cleanup, but that system definitely has upsides for scaling.

// I Was dissapointed to find that there wasn't really a queue that I liked in 
// the standard library. The closest match is a linked list but it exposes it's
// listyness - you have to allocate and deallocate nodes. I chose to encapsulate
// the allocation stuff in a new generic class, and Zigs generics are pretty neat.
// At first, my Haskell brain freaked out when I saw the intermixing of types and
// values, but it works surprisingly well. I'll have to use it more before I can
// reach a verdict though.

// I also wrote an iterator. Now, I wish a permutations iterator already existed,
// but thats a pretty unusual feature all told. I think python is the only thing
// that comes to mind.

// The IntCode computer also became a struct, and I think that made the code there
// a lot prettier. Its in a good place, and I'm excited to develop it more.
