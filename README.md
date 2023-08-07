
# Advent of Code 2019

Except its actually 2023, and in the Summer.

I'm using this to learn Zig! My current impression is that Zig is to C as Rust is
to C++, and by this I mean that Zig wants to take the niche that C fills, and it
wants to fill it while being safer and more ergonomic. It does not deviate as far
from C as Rust does with C++; there is no borrow checker to contend with (or to
protect you), and the code style you end up with feels very procedural, whereas
Rust mixes some functional patterns and some object oriented patterns. Zig does
deviate in its syntax, mixing up the rules for even for if statements and while
loops. It also adds first class keywords that manipulate control flow, such as
`try` and `catch` (its not what you think... far more monadic) for error types, 
`orelse` and `.?` for optional types, and `defer` for actions that clean up a
resource.

Do be warned - at time of writing, Zig is more immature than Rust, and Zig has
not even hit 1.0; also, while Rust's documention, compiler errors, language server,
and package manager are all stellar, Zig's are like... ok? But the language itself
has been a joy to write in - I feel I am learning it far faster than with Rust, 
where I still can barely predict what the borrow checker will actually ask of me
before it asks.

