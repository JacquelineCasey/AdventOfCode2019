
const std = @import("std");

const std_in = std.io.getStdIn();
const std_out = std.io.getStdOut().writer();


// Tagged union - the tag is inferred, due to enum keyword
const Instruction = union(enum) {
    deal_new: void,
    cut: i32,
    deal_inc: i32,
};


/// Represents a function to maps (x) -> (ax + b);
const Expression = struct {
    a: i128,
    b: i128
};


fn deal_new() Expression {
    return .{.a = -1, .b = -1};
}

fn cut(amount: i32) Expression {
    return .{.a = 1, .b = -amount};
}

fn deal_inc(amount: i32) Expression {
    return .{.a = amount, .b = 0};
}


/// computes f . g, the function that maps (x) -> f(g(x));
fn compose(f: Expression, g: Expression, N: i128) Expression {
    return .{
        .a = @mod(f.a * g.a, N),
        .b = @mod(f.a * g.b + f.b, N)
    };
}


/// returns array list such that list[i] == true means that 2^i is in the decomposition;
/// remember to deinit the array list.
fn get_binary(a: i128, alloc: std.mem.Allocator) !std.ArrayList(bool) {
    var temp = a;

    var list = std.ArrayList(bool).init(alloc);

    while (temp > 0) : (temp = @divTrunc(temp, 2)) {
        try list.append(@mod(temp, 2) == 1);
    }

    return list;
}


fn inverse(a: i128, N: i128, alloc: std.mem.Allocator) !i128 {
    // By fermat's little theorem, a^(N-2) is the inverse of a.

    const binary = try get_binary(N - 2, alloc);
    defer binary.deinit();

    var temp = a;

    var result: i128 = 1;
    for (binary.items) |bit| {
        if (bit) {
            result = @mod(result * temp, N);
        }

        temp = @mod(temp * temp, N);
    } 

    return result;
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

    var instructions = std.ArrayList(Instruction).init(alloc);
    defer instructions.deinit();

    var line_iter = std.mem.splitSequence(u8, input, "\n");
    while (line_iter.next()) |line| {
        if (std.mem.startsWith(u8, line, "cut")) {
            try instructions.append(.{ .cut = try std.fmt.parseInt(i32, line[4..], 10) });
        }
        else if (std.mem.startsWith(u8, line, "deal with increment")) {
            try instructions.append(.{ .deal_inc = try std.fmt.parseInt(i32, line[20..], 10) });
        }
        else if (std.mem.eql(u8, line, "deal into new stack")) {
            try instructions.append(.{ .deal_new = {} });
        }
        else unreachable;
    }

    const N: i128 = 119315717514047; // Number of cards; our modular base.
    const iterations: i128 = 101741582076661;

    var expr = Expression{ .a = 1, .b = 0 };

    for (instructions.items) |instruction| {
        switch (instruction) {
            .deal_new => {
                expr = compose(deal_new(), expr, N);
            },
            .cut => |amount| {
                expr = compose(cut(amount), expr, N);
            },
            .deal_inc => |amount| {
                expr = compose(deal_inc(amount), expr, N);
            }
        }
    }

    const iter_binary = try get_binary(iterations, alloc);
    defer iter_binary.deinit();
    
    var iter_expr: Expression = .{ .a = 1, .b = 0 };

    for (iter_binary.items) |bit| {
        if (bit) {
            iter_expr = compose(expr, iter_expr, N);
        }

        expr = compose(expr, expr, N);
    }

    const result = @mod((2020 - iter_expr.b) * try inverse(iter_expr.a, N, alloc), N);

    try std_out.print("{d}\n", .{result});
}

// I've rewritten the shuffles so that they look similar. We can think of each one
// as a function that maps the input index to an output index, then it performs
// out[f(i)] = in[i].
// If we can effiecntly compose (and eventually reverse) these functions, we can
// discover what ends up in out[2020] without ever building the arrays.
// One idea is the repeated squaring method. So if we can build f() for an entire
// shuffle, then instead of doing f . f . f . f (f composed with itself 4 times),
// we would do f2 := f . f, and f4 : f2 . f2, and so on. We can build f101741582076661
// by composing 'powers' of 2 of f.
// Note - both the number of shuffles and the input size are prime. All of our
// basic operations are relatively simple mod input_size.

// deal_new: (i) -> (-i - 1)
// cut: (i) -> (i - amount)
// deal_inc: (i) -> (i * amount)

// Strategy: Build a type that represents expressions like ax + b. Apply all the
// operations of the shuffle on 1x + 0 once. Then compose the expression with itself
// repeatedly. At all steps in the process, we can reduce the expression mod N.

// At the end, we will get a function like f(x) = ax + b. And we will want x such
// that 2020 = ax + b. We will need the inverse of a mod N. It helps that N is prime,
// because we can use Fermat's Little Theorem (thanks StackOverFlow: https://math.stackexchange.com/questions/25390/how-to-find-the-inverse-modulo-m).
// Again, we will use the repeated squaring method to make that survivable.

// Do everything mod N, and in i128 integers. Zig's arbitrary int size will help
// a lot.



// Ok, it worked.

// Very hard problem, but also a lot of fun. I had to brush off some discreet math
// skills. My worst mistake was mis-applying Fermat's little theorem so that every
// time I ran the inverse function, it returned 1.

// Zig was fairly pleasant. I utilized its arbitrary integer width feature, choosing
// to store everything in an i128. The main annoyance of part 1 was casting, they
// really need to combine @as and @intCast, the current way is disgusting. However,
// I thought I would be annoyed by @mod this time, but to be honest @mod is fairly
// natural. The % version often require you to put things in parentheses anyway,
// so surprisingly, @mod(a + b, c + d) is not much longer than (a + b) % (c + d),
// and even has fewer parentheses (you don't have to worry about parentheses). Of
// course, the reason the feature exists is so that you cannot possibly think you
// are using @rem rules - it forces you to think about @rem and @mod once, and then
// you never get into trouble later.

// I honestly don't know if % means mod or remainder in most the languages I use,
// it is surprisingly inconsistent.
