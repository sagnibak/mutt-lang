use std::Vec;

/// Takes a mutable reference to `v` and appends 1 to it.
fn append_one(mutref v) where
    Vec::append(mutref v, 1)
end

/// Takes a mutable refence to `v` and pops its lats value.
/// Then it creates a new vector `w` and moves the popped value
/// into the append function. Finally it moves `w` out of the function
/// scope into the caller's scope. Note that the caller must also move
/// out of the function scope into a View in its own scope.
fn displace(mutref v) where
    move Vec::new() into w
    Vec::append(mutref w, move Vec::pop(mutref v))
    move w
end

move Vec::new() into vec

append_one(mutref vec)
move displace(mutref vec) into w

forget(v)
