defmodule Mix.Tasks.Check do
  @moduledoc """
  Runs every check the project requires before code is merged: the
  format check, a compile that fails on warnings, dialyzer, the tests and
  `credo --strict`.

  Each check runs as its own `mix` command, in order, and the task stops
  at the first one that fails.
  """
  @shortdoc "Runs format, compile, dialyzer, tests and credo"

  use Mix.Task

  @typedoc "the arguments to `mix` and the `MIX_ENV` to run them in"
  @type step() :: {args :: [String.t()], mix_env :: String.t()}

  @steps [
    {["format", "--check-formatted"], "dev"},
    {["compile", "--warnings-as-errors"], "dev"},
    {["dialyzer"], "dev"},
    {["test"], "test"},
    {["credo", "--strict"], "dev"}
  ]

  @impl Mix.Task
  def run(_args) do
    Enum.each(@steps, &run_step/1)
  end

  @spec run_step(step()) :: :ok
  defp run_step({args, mix_env}) do
    command = Enum.join(["mix" | args], " ")
    Mix.shell().info("==> #{command}")

    {_output, status} =
      System.cmd("mix", args,
        env: [{"MIX_ENV", mix_env}],
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    if status != 0 do
      Mix.raise("#{command} failed")
    end

    :ok
  end
end
