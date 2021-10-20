# RFC 1

The purpose of this request for comments is to outline the semantics
of the language and define its core features, concepts, and its memory
model.

## Memory

Memory is a contiguous array of bits. We have a standardized way of
addressing it, which is typically provided by the operating system or
the hardware. Many operating systems semantically divide this into a
statically managed part called the stack, and a dynamically managed
part called the heap. The former is usually used when the size of an
allocation is known at compile time, since the compiler must produce
instructions to decrement the stack pointer by an appropriate offset,
whereas the latter is most often used either when the size of the
allocation is not known at compile time, when the size might change,
and when the size might be so big as to overflow the stack. There are,
of course, numerous other reasons why one might choose one over the
other, but the point is to provide the programmer control over it when
they want (using `std::stack_alloc` and `std::heap_alloc`), and
abstracting it away otherwise (using `std::alloc`).

### Views, not Variables

The only way to access a block of memory is through a `View`. A `View`
can be thought of as a window that lets you look at a specific
contiguous chunk of memory. It will probably be implemented in the
interpreter as a tuple of two unsigned pointer-length integers,
one representing the starting address and the other representing the
length of the `View`. Variables are a semantic nicety afforded by most
languages, but they often conflate the memory representing an object
and the pointer/reference referring to said object. In Mutt, we want
to distinguish between these two. A `void*` is not enough since it
does not contain any information about the length of the chunk.
Combining a `void*` with a `size_t` would be enough to represent a
`View`. Note that `View`s can be optimized away by the compiler in
many cases.

### Memory Actions, not Assignment

Look at the following lines of C++ code:
```cpp
int foo = 8;                           // variable assignment
vector<int> vec = old_vec;             // memory copy
vector<int> vec = std::move(old_vec);  // move
```

The `=` operator is doing very different things in the three cases. In
the first line, the memory representing `foo` is set to the bit
pattern corresponding to the signed integer `8` in two's complement.
In the second line, the contents of `old_vec` are being copied into
`vec`. In the third line, `old_vec` is being moved into `vec`, to
avoid copying all the contents of the vector (semantically, it is
moving whatever was in `old_vec` into `vec` and leaving `old_vec` in a
state that allows cleanup but not usage). We want to make these three
cases explicitly different. In order to do that, we want to get rid of
assignment altogether, opting for more explicit actions.

The three lines of C++ are replaced by the following three lines in
Mutt:
```mutt
write 8 to foo
move old_vec.copy() into vec
move old_vec into vec
```
where `old_vec.copy()` returns a `View` to a copy of `old_vec`. What's
the difference between `write to` and `move into`, you may ask. The
former changes the memory pointed to by the `View` `foo`, whereas the
latter changes the `View` `foo` itself.

Mutt follows a rather simple memory model. There are several possible
states of memory and several ways of transitioning between them. I
will produce a diagram when I get the time.
1. **Free memory** is not referred to by any `View`. One can call
   `std::alloc` to convert free memory into uninitialized allocated
   memory. Allocated memory can turn back into free memory by calling
   `forget` on a corresponding `View`.
2. **Allocated memory** is memory that has been
   allocated to the current process, but is not guaranteed to be in a
   valid state. The output of `std::alloc` is uninitialized, so
   ideally these calls should be wrapped inside functions that
   initialize the memory to have semantic meaning to enforce RAII.
   Allocated memory is accessed by the process using a `View`, which
   stores the address and size of the allocation, and allows a safe
   way to access memory. All memory access are checked unless the
   compiler can prove safety, or the programmer explicitly turns off
   bounds checks. A few operations are possible on allocated memory.
    1. **Reading** is the process of accessing the value pointed at by
       a `View` with the intent of writing it to some other part of
       memory.
    2. **Writing** is the process of setting the bits pointed to by a
       `View` in a specified pattern. For example, in order to write
       the two's complement 32-bit signed integer `8` to the memory
       pointed at by the `View` `x`, one would write `write 8 to x`.
    3. **Moving** from one `View` `x` into another `View` `y` is the
       process of freeing the memory pointed to by `y`, invalidating
       the `View` `x`, and making the view `y` refer to the memory
       that `x` was referring to earlier. If `y` was not a `View`
       prior to this, then `y` is defined to be a new `View` after
       being moved into. The syntax for this is `move x into y`.

### Referential Views and Restrictions on Memory Actions

Sometimes it is useful to refer to the same chunk of memory from
multiple parts of code, e.g., in data structures shared across
threads. The only way to obtain a `View` is to call an allocation
function like `std::alloc` or to move from a `View` (note that copying
necessitates calling `std::alloc`, since free memory must be obtained
to create the copy). Thus a single chunk of memory can only have a
single `View` corresponding to it. This necessitates references to
`View`s. Two kinds of references may be obtained from a `View`:
1. **Immutable references** are references that only allow reading
   from the memory pointed to by the `View`. Writing and moving are
   not permitted. Multiple immutable references from the same `View`
   can be live at the same time. In order to get an immutable
   reference `r` from a `View` `x`, we write `ref x as r`.
2. **Mutable references** are references that allow both reading and
   writing, but do not allow moving. A mutable reference can only be
   obtained from a `View` if there are no live immutable or mutable
   references. The syntax to obtain a mutable reference `r` from a
   `View` `x` is `mut ref x as r`.

Note that a reference is live from its creation to its last use. If it
is never used, then it is never live. References always die at the end
of the scope, since they cannot be moved out.

## Raison d'être

There are languages like Python which are excellent for beginners
since they abstract away the _implementation_ of the language from the
_semantics_ of the language. One does not need to know how a Python
list is laid out in memory to be able to use it effectively.

There are others that provide control over memory, like C, which give
the programmer enough rope to hang themselves with. I am no stranger
to GDB Hell, which one often finds oneself in as a result of not
getting memory management right. This is why generally these are
regarded as difficult languages to learn. It is not so much that the
language itself is unintuitive, but rather that you can do many
unintuitive things with the language, and use things in ways they were
not intended to be used. For example, it is possible to define the
following struct in C to represent an allocation with a pointer to
itself:
```c
typedef struct cycle {
    uint64_t val;
    struct cycle* ptr;
};
```
It is only valid when `ptr` points to the beginning of the struct that
contains it, and it is possible to write functions that rely on this:
```c
void pls_dont_segfault(struct cycle* cycle) {
    if (cycle->ptr != cycle) {
        cycle = *((void*)0);
    }
}
```
But it is absolutely possible to have `struct cycle`s in your code
that are inconsistent. It is also possible to inadvertently violate
this invariant and be left wondering as to why your code is not
working:
```c
struct cycle make_cycle(uint64_t val) {
    struct cycle cycle;
    cycle.val = val;
    cycle.ptr = &cycle;
    return cycle;
}
```
When `cycle` is returned, it is copied into its caller's `struct cycle`.
However, now the caller's `cycle.ptr` is in an invalid state, since it
is pointing at garbage in the (dead) stack frame of `make_cycle`. Thus
the caller must be aware of the internals of `struct cycle` in order
to use it effectively.

The goal of this language is to make it hard to write such leaky
abstractions, and to introduce new programmers to the wonders and joys
of _controlled mutation_, which Rust has mastered through its system
of ownership and borrowing. At the same time, we remove a lot of the
performance and low-level control constraints of Rust to make it much
more intuitive to learn. We would also like to have dynamic typing
since type systems often scare new programmers, and besides it's not
like C has a type system either.
