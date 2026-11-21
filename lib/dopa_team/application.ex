defmodule DopaTeam.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # before the task supervisor, so on shutdown it outlives the tasks
      # storing reports in it
      DopaTeam.ReportStore,
      # runs slow jobs, such as building a DopaTeam.MemberReport, off the
      # consumer
      {Task.Supervisor, name: DopaTeam.TaskSupervisor},
      DopaTeam.Consumer,
      DopaTeam.WaterPing
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: DopaTeam.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
