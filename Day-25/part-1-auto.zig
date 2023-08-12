
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
        if (self.state == .AwaitingInput) {
            self.state = .Runnable;
        }

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

const Room = struct {
    name: []u8,
    directions: std.ArrayList([]const u8),
    items: std.ArrayList([]const u8),
};


fn parse_room(data: []u8, alloc: std.mem.Allocator) !Room {
    const name_start = std.mem.lastIndexOf(u8, data, "== ").? + 3;
    const name_end = std.mem.lastIndexOf(u8, data, " ==").?;

    const name = try alloc.alloc(u8, name_end - name_start);
    @memcpy(name, data[name_start..name_end]);

    var items = std.ArrayList([]const u8).init(alloc);

    const maybe_item_list_start = std.mem.indexOf(u8, data, "Items here:\n");
    if (maybe_item_list_start) |item_list_start| {
        const item_list_end = std.mem.indexOf(u8, data, "\n\nCommand?").?;

        var iter = std.mem.splitSequence(u8, data[item_list_start+12..item_list_end], "\n");

        while (iter.next()) |line| {
            const item = try alloc.alloc(u8, line.len - 2);
            @memcpy(item, line[2..]);

            try items.append(item);
        }
    }

    var directions = std.ArrayList([]const u8).init(alloc);

    if (std.mem.indexOf(u8, data, "- north\n") != null) {
        try directions.append("north");
    }
    if (std.mem.indexOf(u8, data, "- south\n") != null) {
        try directions.append("south");
    }
    if (std.mem.indexOf(u8, data, "- east\n") != null) {
        try directions.append("east");
    }
    if (std.mem.indexOf(u8, data, "- west\n") != null) {
        try directions.append("west");
    }

    return .{
        .name = name,
        .directions = directions,
        .items = items
    };
}  

fn reverse_direction(dir: []const u8) ![]const u8 {
    if (std.mem.eql(u8, dir, "south")) {
        return "north";
    }
    if (std.mem.eql(u8, dir, "north")) {
        return "south";
    }
    if (std.mem.eql(u8, dir, "east")) {
        return "west";
    }
    if (std.mem.eql(u8, dir, "west")) {
        return "east";
    }

    return error.BadDirection;
}


/// Returns the room arrived at.
fn move(computer: *IntCodeComputer, dir: []const u8, arena_alloc: std.mem.Allocator) !Room {
    try std_out.print("{s}\n", .{dir});

    try computer.push_ascii_input(dir);
    try computer.push_input(@intCast('\n'));

    try computer.run();

    var out_array = std.ArrayList(u8).init(arena_alloc);
    defer out_array.deinit();

    while (computer.pop_output()) |ch| {
        try out_array.append(@intCast(ch));
    }

    try std_out.print("{s}", .{out_array.items});

    return try parse_room(out_array.items, arena_alloc);
}

fn safe(item: []const u8) bool {
    const bad_items: [5][]const u8 = .{"photons", "molten lava", "infinite loop", "escape pod", "giant electromagnet"};

    for (bad_items) |bad_item| {
        if (std.mem.eql(u8, item, bad_item)) {
            return false;
        }
    }

    return true;
}

fn take(computer: *IntCodeComputer, item: []const u8) !void {
    try std_out.print("take {s}\n", .{item});

    try computer.push_ascii_input("take ");
    try computer.push_ascii_input(item);
    try computer.push_ascii_input("\n");

    try computer.run();

    while (computer.pop_output()) |ch| {
        try std_out.print("{c}", .{@as(u8, @intCast(ch))});
    }
}

fn drop(computer: *IntCodeComputer, item: []const u8) !void {
    try std_out.print("drop {s}\n", .{item});

    try computer.push_ascii_input("drop ");
    try computer.push_ascii_input(item);
    try computer.push_ascii_input("\n");

    try computer.run();

    while (computer.pop_output()) |ch| {
        try std_out.print("{c}", .{@as(u8, @intCast(ch))});
    }
}

fn traverse(computer: *IntCodeComputer, from: []const u8, arena_alloc: std.mem.Allocator) !void {
    const room = try move(computer, from, arena_alloc);
    
    for (room.items.items) |item| {
        if (safe(item)) {
            try take(computer, item);
        }
    }

    if (!std.mem.eql(u8, room.name, "Security Checkpoint")) {
        for (room.directions.items) |dir| {
            if (!std.mem.eql(u8, dir, try reverse_direction(from))) {
                try traverse(computer, dir, arena_alloc);
            }
        }
    }

    _ = try move(computer, try reverse_direction(from), arena_alloc);
}


/// returns the checkpoint room, if it is reached
fn to_checkpoint(computer: *IntCodeComputer, from: []const u8, arena_alloc: std.mem.Allocator) !?Room {
    const room = try move(computer, from, arena_alloc);
    
    if (std.mem.eql(u8, room.name, "Security Checkpoint")) {
        return room;
    }

    for (room.directions.items) |dir| {
        if (!std.mem.eql(u8, dir, try reverse_direction(from))) {
            if (try to_checkpoint(computer, dir, arena_alloc)) |checkpoint| {
                return checkpoint;
            }
        }
    }

    // note that this is skipped if we return true;    
    _ = try move(computer, try reverse_direction(from), arena_alloc);

    return null;
}


fn inv(computer: *IntCodeComputer, arena_alloc: std.mem.Allocator) !std.ArrayList([]const u8) {
    try std_out.print("inv\n", .{});

    try computer.push_ascii_input("inv\n");

    try computer.run();

    var out_array = std.ArrayList(u8).init(arena_alloc);
    defer out_array.deinit();

    while (computer.pop_output()) |ch| {
        try out_array.append(@intCast(ch));
    }

    try std_out.print("{s}", .{out_array.items});

    var list = std.ArrayList([]const u8).init(arena_alloc);

    const item_list_start = std.mem.lastIndexOf(u8, out_array.items, "inventory:\n").? + 11;
    const item_list_end = std.mem.lastIndexOf(u8, out_array.items, "\n\nCommand?").?;

    var iter = std.mem.splitSequence(u8, out_array.items[item_list_start..item_list_end], "\n");
    while (iter.next()) |line| {
        const item = try arena_alloc.alloc(u8, line.len - 2);
        @memcpy(item, line[2..]);

        try list.append(item);
    }

    return list;
}



fn brute_force(computer: *IntCodeComputer, dir: []const u8, arena_alloc: std.mem.Allocator) !void {
    const inventory = try inv(computer, arena_alloc);
    
    var a: u32 = 0;  // binary number representing which items to drop (1 = drop);
    while (std.mem.eql(u8, (try move(computer, dir, arena_alloc)).name, "Security Checkpoint")) : (a += 1) {
        if (a == 255) {
            return;
        }
       
        for (inventory.items) |item| {
            try take(computer, item);  // Likely won't do anything.
        }
        
        var temp = a;

        for (0..inventory.items.len) |i| {
            if (temp % 2 == 1) {
                try drop(computer, inventory.items[i]);
            }

            temp /= 2;
        }
    }
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
    // Ownership taken by computer

    var it = std.mem.splitSequence(u8, input, ",");
    var index: usize = 0;
    while (it.next()) |substring| {
        try base_memory.put(index, try std.fmt.parseInt(i64, substring, 10));
        index += 1;
    }

    var computer = IntCodeComputer.init(base_memory, alloc);
    defer computer.deinit();

    var input_reader = std_in.reader();

    var in_array = std.ArrayList(u8).init(alloc);
    defer in_array.deinit();

    var out_array = std.ArrayList(u8).init(alloc);
    defer out_array.deinit();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();


    try computer.run();
    out_array.clearRetainingCapacity();
    while (computer.pop_output()) |ch| {
        try out_array.append(@intCast(ch));
    }

    try std_out.print("{s}", .{out_array.items});

    const start_room = try parse_room(out_array.items, arena_alloc);
    try std_out.print("{any}\n", .{start_room.directions.items});


    for (start_room.directions.items) |dir| {
        try traverse(&computer, dir, arena_alloc);
    }

    const checkpoint_room = for (start_room.directions.items) |dir| {
        if (try to_checkpoint(&computer, dir, arena_alloc)) |checkpoint| {
            break checkpoint;
        }
    }
    else {
        return error.CheckpointNotFound;
    };

    const check_point_dir = for (checkpoint_room.directions.items) |dir| {
        const neighbor = try move(&computer, dir, arena_alloc);
        if (std.mem.eql(u8, neighbor.name, "Security Checkpoint")) {
            break dir;
        }

        _ = try move(&computer, try reverse_direction(dir), arena_alloc);
    }
    else {
        return error.CheckpointDirectionNotFound;
    };

    try brute_force(&computer, check_point_dir, arena_alloc);


    while (computer.state != .Terminated) {
        if (computer.state == .AwaitingInput) {
            in_array.clearRetainingCapacity();

            try input_reader.streamUntilDelimiter(in_array.writer(), '\n', null);

            try computer.push_ascii_input(in_array.items);
            try computer.push_input(@intCast('\n'));  // '\n' eaten by streamUntilDelimiter, we add it here.
        }

        try computer.run();

        out_array.clearRetainingCapacity();
        while (computer.pop_output()) |ch| {
            try out_array.append(@intCast(ch));
        }

        try std_out.print("{s}", .{out_array.items});
    }
}


// Run without a file. Stole some code from Day 13 for this.

// Ouch. That was quite hard. Manipulating strings in Zig is better than in C
// certaintly, and probably slightly more ergonomic than in Rust, but that was still
// quite a pain. I had an embarassing error that caused the first character of one
// of the items to be missing, causing quite a lot of confusion.

// I think I tweaked my int code computer one last time as well, it hadn't quite
// been right before (due to Day 23 changes I think).

// Anyways, there is one more puzzle to go. Day 25 part 2 doesn't exist, as is
// traditional. All I have to do now is go back and complete Day 18 part 2, which
// I have been putting off.
