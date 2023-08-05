defmodule DopaTeamTest do
  use ExUnit.Case
  doctest DopaTeam

  test "greets the world" do
    assert DopaTeam.hello() == :world
  end
end
