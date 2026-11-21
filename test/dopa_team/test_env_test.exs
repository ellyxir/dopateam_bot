defmodule DopaTeam.TestEnvTest do
  use ExUnit.Case, async: true

  # with the token in the environment (~/.bashrc exports production's),
  # a started nostrum logs in to discord as that bot and acts on live events
  test "the test run does not start nostrum" do
    refute List.keymember?(Application.started_applications(), :nostrum, 0)
  end
end
