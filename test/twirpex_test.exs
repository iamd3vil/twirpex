defmodule TwirpexTest do
  use ExUnit.Case
  doctest Twirpex

  test "greets the world" do
    assert Twirpex.hello() == :world
  end
end
