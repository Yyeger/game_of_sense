defmodule LifeSemanticTest do
  use ExUnit.Case
  doctest LifeSemantic

  test "greets the world" do
    assert LifeSemantic.hello() == :world
  end
end
