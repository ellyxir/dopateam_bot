defmodule DopaTeam.MemberReport do
  @moduledoc """
  Reads a server's member list and reports who has not done an intro.

  It only reads: it sends no messages and changes no roles.
  """

  alias Nostrum.Struct.Guild
  alias Nostrum.Struct.Guild.{Member, Role}

  @no_intro_role_name "No Intro"

  @enforce_keys [:no_intro]
  defstruct [:no_intro]

  @type t() :: %__MODULE__{no_intro: [Member.t()]}

  @doc "fetches the server's members and sorts out who has not done an intro"
  @spec build(Guild.id()) :: {:ok, t()} | DopaTeam.Discord.error()
  def build(guild_id) do
    with {:ok, roles} <- discord().get_guild_roles(guild_id),
         {:ok, members} <- discord().list_guild_members(guild_id, limit: 1000) do
      no_intro_role_id = role_id!(roles, @no_intro_role_name)

      {:ok, %__MODULE__{no_intro: Enum.filter(members, &(no_intro_role_id in &1.roles))}}
    end
  end

  @spec role_id!([Role.t()], String.t()) :: Role.id()
  defp role_id!(roles, name) do
    %Role{id: id} = Enum.find(roles, &(&1.name == name))
    id
  end

  defp discord, do: Application.fetch_env!(:dopa_team, :discord)
end
