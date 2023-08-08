
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();


const Reaction = struct {
    result: []const u8,
    result_amount: u64,
    ingredients: std.StringHashMap(u64),
    alloc: std.mem.Allocator,

    fn from_string(str: []const u8, alloc: std.mem.Allocator) !Reaction {
        var sides = std.mem.splitSequence(u8, str, " => ");
        const left = sides.next().?;
        const right = sides.next().?;

        var self: Reaction = undefined;
        self.alloc = alloc;

        self.result = right[std.mem.indexOf(u8, right, " ").? + 1 ..];
        self.result_amount = try std.fmt.parseInt(u32, right[0 .. std.mem.indexOf(u8, right, " ").?], 10);

        self.ingredients = std.StringHashMap(u64).init(alloc);

        var ingredient_iter = std.mem.splitSequence(u8, left, ", ");
        while (ingredient_iter.next()) |ingredient| {
            const name = ingredient[std.mem.indexOf(u8, ingredient, " ").? + 1 ..];
            const amount = try std.fmt.parseInt(u32, ingredient[0 .. std.mem.indexOf(u8, ingredient, " ").?], 10);

            try self.ingredients.put(name, amount);
        }

        return self;
    }

    fn deinit(self: *Reaction) void {
        self.ingredients.deinit();
    }
};

// debug
fn print_reactions(reactions: std.StringHashMap(Reaction)) !void {
    var iter = reactions.valueIterator();
    while (iter.next()) |reaction| {
        var ingred_iter = reaction.ingredients.iterator();
        while (ingred_iter.next()) |entry| {
            try std_out.print("{d} {s}, ", .{entry.value_ptr.*, entry.key_ptr.*,});
        }

        try std_out.print(" => {d} {s} \n", .{reaction.result_amount, reaction.result});
    }
}

// Returns some resource in the negative, but never "ORE".
fn select_resource(supply: std.StringHashMap(i64)) ?[]const u8 {
    var iter = supply.iterator();
    
    while (iter.next()) |entry| {
        if (!std.mem.eql(u8, entry.key_ptr.*, "ORE") and entry.value_ptr.* < 0) {
            return entry.key_ptr.*;
        }
    }

    return null;
}


pub fn ore_cost(desired_fuel: u64, reactions: std.StringHashMap(Reaction), alloc: std.mem.Allocator) !u64 {
    // Build a hashtable representing the supply (+) and demand (-) of each resource.
    var supply = std.StringHashMap(i64).init(alloc);
    defer supply.deinit();

    var resource_iter = reactions.keyIterator();
    while (resource_iter.next()) |resource| {
        try supply.put(resource.*, 0);
    }

    try supply.put("ORE", 0); // No reaction produces ORE, so we set supply manually.
    try supply.put("FUEL", -1 * @as(i64, @intCast(desired_fuel)));


    while (select_resource(supply)) |resource| {
        const reaction = reactions.get(resource).?;
        const deficit = std.math.absCast(supply.get(resource).?);

        var multiplier = deficit / reaction.result_amount;

        if (deficit != multiplier * reaction.result_amount)
            multiplier += 1;

        try supply.put(resource, @as(i64, @intCast(reaction.result_amount * multiplier)) - @as(i64, @intCast(deficit)));

        var ingredient_iter = reaction.ingredients.iterator();
        while (ingredient_iter.next()) |entry| {
            const ingredient = entry.key_ptr.*;
            const base_amount = entry.value_ptr.*;

            try supply.put(ingredient, supply.get(ingredient).? - @as(i64, @intCast(base_amount * multiplier)));
        }
    }

    return std.math.absCast(supply.get("ORE").?);
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

    var reactions = std.StringHashMap(Reaction).init(alloc);
    defer {
        var iter = reactions.valueIterator();
        while (iter.next()) |reaction| {
            reaction.deinit();
        }

        reactions.deinit();
    }

    var lines_iter = std.mem.splitSequence(u8, input, "\n");
    while (lines_iter.next()) |line| {
        const reaction = try Reaction.from_string(line, alloc);

        if (try reactions.fetchPut(reaction.result, reaction) != null) 
            return error.MultipleReactionsProduceIngredient;
    }

    // Essentially binary search on previous algorithm. We could be smarter, but
    // binary search is sufficient.
    
    // 443537 is last times answer
    var max: u64 = 1000000000000 / 443537  * 3;
    var min: u64 = 1;

    while (max - min > 1) {
        const mid = (max + min) / 2;

        const cost = try ore_cost(mid, reactions, alloc);

        if (cost > 1000000000000) {
            max = mid - 1;
        }
        else {
            min = mid;
        }
    }

    if (try ore_cost(min, reactions, alloc) <= 1000000000000) {
        try std_out.print("{d}\n", .{min});
    }
    else {
        try std_out.print("{d}\n", .{max});
    }
}


// Kinda fun problem, though I suspect it could have been harder. 

// The only annoying thing coding it up was having to switch over to u64 and i64.
// Casting between the two is certainly a bit annoying - most languages let you
// do it for free, but Zig requsts @as() if the types fit, or @intCast otherwise.
// And @intCast is not smart enough to deduce the type in the middle of an expression,
// so in those cases you end up doing @as(i32, @intCast(x));

// However, Zig errors on overflow in safe mode - you don't have to figure out that
// something is amiss as in C++ (this is identical to Rust - checked in safe unchecked
// in release). Whats good about Zig though is that if you change one of the types,
// you will get complaints anywhere you don't intCast, so you end up changing things
// once and not many times.

// I like how Zig handles string slices, though probably it is a little less safe
// than Rust. If the strings changed underneath our watch, then stuff would break.
// However, if you know that the string won't change, life is good. No lifetime
// stuff required!
