
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

This is seriously my first time with Zig. You can even find my Hello World in day 1. It
says a lot about Zig that I was able to learn it fast enough to keep up with the
puzzles.

## And that's a wrap.

Github says it took me 7 days, but I wasn't pushing to github early on so add
maybe 2 to get 9 days total.

The puzzles were overall quite good. In the past AoC's (i.e., the ones released after
2019), I felt like there were a lot more problems that I solved with some form
of dynamic programming, or some similar search algorithm. There was very little
explicit DP, though there was a lot of searching, which I mainly achieved through
Breadth First Search. The hardest puzzle, Day 18, involved Dijkstra. I wonder if
there was an actual shift, or if I am now more inclined to tackle heavy search type
problems iteratively (with BFS or Dijkstra) instead of recursively (memoized recursion,
which was my bread and butter).

Of course, half of the puzzles this year were centered around the IntCode computer
that you begin building on Day 2. I quite liked these puzzles, and I was surprised
at how useful Zig was for them too. They were ususally a bit easier than the other
puzzles, but the ability for the puzzle to send you a program and determine an
input that solves it opened up some very unique puzzle designs. In particular, I
liked boolean programming and spring bot programming, those were very cool.

## Zig Review

Ok, so Zig. I was very excited about this language when I first learned about it,
It more or less worked very well for advent of code, which again I consider a bit
surprising because I thought of it as a systems language. There's a lot to like,
but there are also some annoying corners.

The languages I know that I consider closest to Zig are C, C++, and Rust. I consider
these Zig's main competitors (I bet Go is in there too but I don't know Go. Maybe
Go's next?). All 4 of these languages are Systems languages, but they are all capable
of being general purpose (though C is pretty much dominated by C++ in that sphere).

Zig sees itself as a successor of C, just as Rust sometimes sees itself as a successor
of C++, though Zig is a much stronger claim than Rust does. In many ways, Zig feels
like you took the philosophy of C (simplicity!, speed!) but designed a languages given
the context of all the things we learned about programming languages in the last 4 years.
Zig adopts some complexity over C, but much of it is stuff that programmers are used
to from litterally every other language: for instance, method syntax (which makes
Zig feel object oriented even though it really is not), and combining of -> and .
operators. In some ways, Zig *reduces* complexity versus C: macros are gone, and
this means C's language within a language is gone. Yes, Zig has generics, (which
is awesome, but usually ratchets complexity up a lot), but it simplifies metaprogramming
a lot by using identical syntax (a generic type is actually a function on types),
while Rust and C++ achieve provide a much more complicated syntax (especially C++,
try explaining the use decltype() to someone the first time...).

Zig is quite safe, though it lacks Rust's memory safety. Zig wants you to see
every point where something can go wrong, so practically every operation that
can fail will have `try` or `catch` near it (in retrospect, I basically never used
`catch`, but I also basically never interface with the error system when coding something
that isn't bumping into errors). If you are trying to cram a big number into a small
once, Zig forces you to explicitly cast, and the cast will be checked in safe builds.
Relatedly, Zig has no hidden control flow - all control flow is either a method call,
or mediated by a keyword. There are no surprises, no operator overloading or property
syntax or destructors or anything. This is admirable, but its also a pain in the butt
sometimes.

More on error handling - here's a summary. C does not have an explicit system for
error handling. Since pointers are ubiquitous, most people will signal an error
by returning null. Otherwise, an int can be returned, and you are supposed to inspect
it to see if anything went wrong. In still other cases, you are supposed to look
at `errno`. Obviously, this is a pain in the but. `C++` switched over to the error
throwing model, where errors are defined, thrown, and caught. I think this is better
than nothing, but the throwable error model can certainly be problematic. This is
because you are pretty much never sure what functions (or operators?!) can throw,
so its possible that it throws in a really inconvenient spot and leaks memory or 
leaves something else in a bad state. RAII helps, but there is additionally weirdness,
if you code C++ you will be instructed to never throw in a destuctor. Clearly this
is quite awkward. Rust is next, and Rust takes the opposite approach - errors as
values. If a function fails, it returns an error. Then, you are supposed to handle
the error case and the non error case seperately. This sounds like a pain, but Rust
has two things that make this bareable - methods on error types that let you do
common things to them, and the handy `?` operator that says "return the error if
this value is an error, otherwise unwrap it". Now, putting the `?` everywhere is
annoying, but then at least you can clearly see all the places a function can fail.
I believe this is far safer than the throwable error model, and far more pleasant
than C's completely ad hoc approach. However, there is one more frustration - you
have to constantly think about the error type. All of your fallible functions now
have return types like `Result<ThingIWantToReturn, UnfortunateErrorThatMightHappen>`,
and honestly typing that over and over again is just unpleasant. It gets worse
when you now have things like `Vec<Result<Rc<Thing>, Error>>>` - the added layer is
more to think about.

So how does Zig solve this? It basically takes rust's approach. However, it has
incredibly strong type inference on the error type. Zig spells `Result<ThingIWantToReturn, UnfortunateErrorThatMightHappen>`
as `UnfortunateErrorThatMightHappen!ThingIWantToReturn`, but it can intuit the 
error type basically everywhere (as far as I can tell, actually everywhere), so
you end up just typing `!ThingIWantToReturn`. You also don't waste time declaring
a type to represent you're error. If you want to add an error type that represents
a missing blorbo, you just say `return error.MissingBlorbo`, and Zig creates the
type and updates the inferred type of every function that can possibly fail due
to the abscence of a blorbo. If you need to inspect the specific error that is being
thrown, you can, but Zig optimizes life for the 95% of time where errors are to be
acknowledged as possible but otherwise not handled. Zig spells `?` as `try` (I like
? a bit better since it is easy to put between things), and it also provides `catch`
as a sort of unwrap or do something else operation. This ends up being less clunky
than pattern matching in Rust, but to be fair Rust can do most things with the monadic
functions instead.

The story is similar, though less extreme, for `null`. In C, you use pointers
almost non stop, but pointers can be `null` and your program explodes if you try
to follow a `null` pointer. C++ still has this bad idea, but it tries to manage
it with a better idea, which is references. References are usually better, but it
is still possible to hang a reference and pass someone something pointing to invalid
data. Rust actually solves the problems - pointers are super rare, if you want to
express a "possible X", you say `Option<X>`, where you actually need pointers you
use smart pointers, and borrows are safer than references for many reasons. In
fairness to C++, it actually has an Option generic, but Rust makes using it more
pleasant via `?` and pattern matching syntax. Finally, `Zig` follows rust, but instead
of using a wordy generic for a super duper common occurence, Zig gives you `?X` as
the spelling for "maybe there's an X here". Zig does not have `?`, but it does have
`orelse`, which is more powerful since it lets you do anything - Rust would force
you to type up a match statement. `x?` is spelled `x orelse return null`, and 
`x.unwrap()`, which means I swear I know that an `X` is in here, is spelled 
`x orelse unreachable`. Cleverly, Zig lets you put `unreachable` anywhere, which
lets the compiler know that you think this thing will never happen. In Safe mode,
it checks, and in Fast mode is trusts you.

One more, and its a big one - memory management. `C` forces you to use `malloc` and
`free`, and you'll do it a lot. In `C++` those are options (though it is rumored
that `new` and `delete` are healthier), but you generally let `std::vector` or another 
collection or smart pointer manage memory for you, and by RAII this works pretty
well. Rust looks a lot like C++ here with its abscence of `malloc`, but the difference
is that Rust doesn't trust you at all. It wants to prove that your code will never
leak and your code will never access bad memory, but it also wants to prove that
your code never borrows out the same piece of data in multiple places if that
data might mutate. This is sometimes a good idea, but sometimes we just want that data
to mutate.

Zig has a bit of a different approach to memory management. Rust and C++ will allocate
things behind the scene a lot - whever you allocate a vector that puts memory on the
heap. C and Zig, on the other hand, require you to call a function to create memory.
Now, technically, this is no different than C++ or (probably) Rust - its just that
the call is encapsulated in some other class. And this can be done in C too - just
hide the malloc call in the "constructor" and the free call in the "destructor", so
really, its not that different from C++ and Rust fundamentally, its just a matter 
of norms and how the standard libraries are written.

Zig is very different. Anything that puts memory on the heap in the standard library
will explicitely take an allocator argument. Now, you don't technically need to do
this in your own code (you could easily put an allocator in global scope and do that
everywhere), but Zig invites you also to pass allocators around like explicit objects.
Whats great about this approach is you can see each and every time memory is allocated.
You can also pull tricks like arena allocation, where the allocator's free function
becomes a no-op and the memory is freed when the arena is deinitialized - basically,
it allows you to turn off the need to explicitely free stuff for a time, which is good
if your data is moving around a lot for a time and then eventually goes out of scope.

Zig improves the experience of manually managing memory by giving you the defer
keyword - do this operation (or block) right before the block returns. This is
almost always used with memory management - allocate an object, then right before
the object goes out of scope it will be freed. It's quite nice. Also, Zig mixes
this with errdefer, to allow an operation to happen only when the block is exited
by a returning error.

I consider Zig to completely dominate C - its really the modern version of C. There's
no shenanigans involving a borrow checker we have to bow down to (which can harm the
efficiency), or object orientation, or functional paradigms. It splashes in a bit of OO and
a bit of functional, but not much, only the parts that are convenient without sacrificing
the core design principles.

However, Zig is an extremely explicit langauge. If you scroll through some of my
solutions, you will see a `try` on almost every line. I also did a ton of explicit
casting, which somehow requires two builtin function calls??? blehck. It is more
explicit than C++ for sure, and C++ is typically quite verbose as opposed to something
like Python. In some ways, it is more explicit than Rust. What I will say though is
that Zig is nice in that there is usually one obviously correct way to do things.
Rust can stump you - you can think you are going in the right direction but then
the borrow checker will come by and force you to rethink your approach. When the Zig
compiler tells you something is wrong, its usually very quick to fix, and it won't
often cause you to change your basic approach - it is very easy to start off in the
right direction. C++ also won't ask you to change your basic approach, but it will
very often let you shoot yourself in the foot as a result. Zig shot me in the foot
a few times, but since the language has a safe mode (Debug mode is enabled by default,
and pretty much all dangerous undefined behavior is checked), it is usually very easy to
locate the source of an issue (ex: Integer overflow, or overrunning a buffer, or leaking
memory if you set things up right). I am convinced that Rust is likely more safe,
but its possible that Zig strikes a better balance between safety and usability
(learnability) for some applications.

While it completely dominates `C`, I don't think it dominates Rust or C++, both
have good uses. Rust if you are willing to go for safety in exchange for velocity,
and C++ perhaps for more general programming use cases when you don't get a lot
of utility out of perfect safety, and want to have all the tools in the world
available to you. But neither Rust nor C++ completely dominate pure C (the loss
of simplicity is significant for some), so Zig accomplishes something good by
being this good at what C is used for. 

There are of course some drawbacks - Zig has iterators, which can be nice, but
it lacks the amazing capabilities of Rust's iterators or even C++'s, since it is
deathly afraid of hidden allocations. I also wish that its range for loops could
do more, and pattern matching in Rust is great and C++'s destructuring is... well
its not pattern matching but its convenient, and Zig does a whole of forcing you
to explicitly unpack stuff. Zig's documentation is pretty lackluster, I'd put it
below Rust's (ofcourse) and C++'s (which is surpisingly good you just need to 
acclimate), but above C's. Zig's compiler errors could also use some work, but
I'm absolutely spoiled by Rust's, and C++'s can be decent or can be atrocious
(it depends on if you are using clang or g++, and how many layers deep you are in
template hell). In general things are good, but Zig sometimes has functions with
`anytype` parameters, which generate some harder to understand errors. Also, printing
text is alarmingly painful in Zig, and some of its other syntax quirks take getting
used too. `.{...}` for structures with deduced types is weird, and having to prefix
fields with a . is weird too but you get used to it. Its enums syntax is nice though,
it will deduce those pretty well, and I really like how generics are handled and 
how blocks can be expressions and so on and so forth.

So Zig still needs some time to mature, I think. Rust and even C++ somehow appear
to have more polish.

But overall, yeah, the langauge is very good, but its likely I will only reach for
it in the future if its something I want to run fast and don't need the higher order
features of a Rust or a C++. Also, I'm coming around to the idea that garbage collectors
are probably fine for most things, and you can't really beat the ergonomics of
garbage collecting languages - no memory leak footguns + no fussy borrow checker = 
happy programming. It totally beats C for me, and it has a lot of good ideas that
I hope filter into other langauges. I like the syntax for optionals and errors, I
love that errors are inferred, I like defer, I like the unified syntax for things
like generics, I love expressional langauges (as opposed to statements), and I love
comptime, and the list goes on. Hopefully these ideas find wider adoption in other
langauges as time goes on.
