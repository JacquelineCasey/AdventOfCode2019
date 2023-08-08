
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();


const Reaction = struct {
    result: []const u8,
    result_amount: u32,
    ingredients: std.StringHashMap(u32),
    alloc: std.mem.Allocator,

    fn from_string(str: []const u8, alloc: std.mem.Allocator) !Reaction {
        var sides = std.mem.splitSequence(u8, str, " => ");
        const left = sides.next().?;
        const right = sides.next().?;

        var self: Reaction = undefined;
        self.alloc = alloc;

        self.result = right[std.mem.indexOf(u8, right, " ").? + 1 ..];
        self.result_amount = try std.fmt.parseInt(u32, right[0 .. std.mem.indexOf(u8, right, " ").?], 10);

        self.ingredients = std.StringHashMap(u32).init(alloc);

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
fn select_resource(supply: std.StringHashMap(i32)) ?[]const u8 {
    var iter = supply.iterator();
    
    while (iter.next()) |entry| {
        if (!std.mem.eql(u8, entry.key_ptr.*, "ORE") and entry.value_ptr.* < 0) {
            return entry.key_ptr.*;
        }
    }

    return null;
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

    // Build a hashtable representing the supply (+) and demand (-) of each resource.
    var supply = std.StringHashMap(i32).init(alloc);
    defer supply.deinit();

    var lines_iter = std.mem.splitSequence(u8, input, "\n");
    while (lines_iter.next()) |line| {
        const reaction = try Reaction.from_string(line, alloc);

        if (try reactions.fetchPut(reaction.result, reaction) != null) 
            return error.MultipleReactionsProduceIngredient;

        try supply.put(reaction.result, 0);
    }

    try supply.put("ORE", 0); // No reaction produces ORE, so we set supply manually.
    try supply.put("FUEL", -1); // We need 1 FUEL.alloc


    while (select_resource(supply)) |resource| {
        const reaction = reactions.get(resource).?;
        const deficit = std.math.absCast(supply.get(resource).?);

        var multiplier = deficit / reaction.result_amount;

        if (deficit != multiplier * reaction.result_amount)
            multiplier += 1;

        try supply.put(resource, @as(i32, @intCast(reaction.result_amount * multiplier)) - @as(i32, @intCast(deficit)));

        var ingredient_iter = reaction.ingredients.iterator();
        while (ingredient_iter.next()) |entry| {
            const ingredient = entry.key_ptr.*;
            const base_amount = entry.value_ptr.*;

            try supply.put(ingredient, supply.get(ingredient).? - @as(i32, @intCast(base_amount * multiplier)));
        }
    }

    try std_out.print("{d}\n", .{-1 * supply.get("ORE").?});
}
