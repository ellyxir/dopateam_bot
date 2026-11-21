defmodule DopaTeam.MemberReport do
  @moduledoc """
  Reads a server's member list and reports who has not done an intro.

  It only reads: it sends no messages and changes no roles.
  """

  alias Nostrum.Struct.Guild
  alias Nostrum.Struct.Guild.{Member, Role}

  @no_intro_role_name "No Intro"
  @intro_role_name "Intro"

  @enforce_keys [:no_intro, :without_intro_roles]
  defstruct [:no_intro, :without_intro_roles]

  @typedoc """
  * `no_intro` - members with the No Intro role
  * `without_intro_roles` - members with neither Intro nor No Intro
  """
  @type t() :: %__MODULE__{no_intro: [Member.t()], without_intro_roles: [Member.t()]}

  # discord's largest page of members
  @max_page_size 1000

  @doc """
  fetches the server's members and sorts out who has not done an intro

  Options:
  * `page_size:` - members to fetch per api call, at most #{@max_page_size}
  """
  @spec build(Guild.id(), page_size: pos_integer()) ::
          {:ok, t()} | {:error, {:missing_role, String.t()}} | DopaTeam.Discord.error()
  def build(guild_id, options \\ []) do
    page_size = Keyword.get(options, :page_size, @max_page_size)

    with {:ok, roles} <- discord().get_guild_roles(guild_id),
         {:ok, no_intro_role_id} <- role_id(roles, @no_intro_role_name),
         {:ok, intro_role_id} <- role_id(roles, @intro_role_name),
         {:ok, members} <- fetch_members(guild_id, page_size, 0, []) do
      {:ok,
       %__MODULE__{
         no_intro: Enum.filter(members, &(no_intro_role_id in &1.roles)),
         without_intro_roles:
           Enum.reject(members, &(no_intro_role_id in &1.roles or intro_role_id in &1.roles))
       }}
    end
  end

  # discord pages members by user id: each page holds the members whose ids
  # come after the last id of the page before; a short page is the last one
  @spec fetch_members(Guild.id(), pos_integer(), non_neg_integer(), [[Member.t()]]) ::
          {:ok, [Member.t()]} | DopaTeam.Discord.error()
  defp fetch_members(guild_id, page_size, after_id, pages) do
    case discord().list_guild_members(guild_id, limit: page_size, after: after_id) do
      {:ok, page} when length(page) < page_size ->
        {:ok, Enum.concat(Enum.reverse([page | pages]))}

      {:ok, page} ->
        fetch_members(guild_id, page_size, List.last(page).user_id, [page | pages])

      error ->
        error
    end
  end

  @spec role_id([Role.t()], String.t()) ::
          {:ok, Role.id()} | {:error, {:missing_role, String.t()}}
  defp role_id(roles, name) do
    case Enum.find(roles, &(&1.name == name)) do
      %Role{id: id} -> {:ok, id}
      nil -> {:error, {:missing_role, name}}
    end
  end

  defp discord, do: Application.fetch_env!(:dopa_team, :discord)
end
