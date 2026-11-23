defmodule DopaTeam.MixProject do
  use Mix.Project

  def project do
    [
      app: :dopa_team,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      dialyzer: [plt_add_apps: [:mix]]
    ]
  end

  # test/support holds helpers only the tests use
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # tests call the consumer directly, so they don't start the app; a
  # started nostrum would log in to discord as the dev bot
  defp aliases do
    [test: "test --no-start"]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      # nostrum's message cache keeps its table in mnesia
      extra_applications: [:logger, :mnesia],
      mod: {DopaTeam.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nostrum, "~> 0.10.4"},
      {:dialyxir, "~> 1.3", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.2", only: :test}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
