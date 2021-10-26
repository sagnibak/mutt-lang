module fizz_buzz where

  use std::{alloc, println}

  fn fizz_buzz(i) where
    if ((i % 3 == 0) and (i % 5 == 0)) then
      println("FizzBuzz")
    elif i % 5 == 0 then
      println("Buzz")
    elif i % 3 == 0 then
      println("Fizz")
    else
      println(i)
    end
  end

  move alloc(sizeof i32) into x

  loop
    if x == 100 then break
    fizz_buzz(ref x)
  end

end