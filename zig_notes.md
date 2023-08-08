
https://stackoverflow.com/questions/74021886/how-do-i-mutate-a-zig-function-argument

Because parameters are passed immutably, Zig will choose whichever is faster between
pass by reference and pass by copy. This means, unlike in C, you don't have to worry
about it!

If you want mutation though, you need to pass a pointer. Or you can create an 
explicit copy within the function itself and use that.

Note that a "const pointer" (which you can get by referencing a constant)
acts like a pointer to a constant, even if the pointer itself is changeable. As
a result, capturing paramters with *const seems redundant, you can just do the normal
capture (no pointer).

======

Iterators are defined as anything that implements an optional returning next().
I don't think there is any for or while loop sugar for iterators. The apparent sugar
comes from while loop's support for optionals.

======

comptime types are complex: 

EX:

fn absCast(x: anytype) switch (@typeInfo(@TypeOf(x))) {
    .ComptimeInt => comptime_int,
    .Int => |int_info| std.meta.Int(.unsigned, int_info.bits),
    else => @compileError("absCast only accepts integers"),
}