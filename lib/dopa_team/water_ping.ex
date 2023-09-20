defmodule DopaTeam.WaterPing do
  @moduledoc """
  the command `@water_command_name` will check if there has been a recent water 
  reminder and if not, send a ping to a role
  """

  @water_role_name "some name"
  @cooldown_minutes 270
  @water_command_name "water"
  @water_command %{
    name: @water_command_name,
    description: "Send a reminder to drink water to the Water role"
  }
  defstruct [
    :lastping
  ]

  @doc """
  returns the water slash command info
  """
  def register_command(), do: @water_command

  @doc """
  user requested water ping
  """
  @type handle_water() :: any() 
  def handle_water() do
  end
end
