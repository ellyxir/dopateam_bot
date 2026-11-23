defmodule DopaTeam.Discord.GuildMember do
  @moduledoc """
  A member of a server, as discord's member list gives it.

  Unlike `Nostrum.Struct.Guild.Member`, which drops the member's user, it
  keeps the user's name and whether they are a bot.
  """

  alias Nostrum.Struct.Guild.Role
  alias Nostrum.Struct.User

  @enforce_keys [:user_id, :username, :roles, :joined_at, :bot?]
  defstruct [:user_id, :username, :roles, :joined_at, :bot?]

  @typedoc "when the member joined the server, in unix seconds"
  @type joined_at() :: integer() | nil

  @typedoc """
  * `user_id` - the member's user id
  * `username` - the user's unique name, as in `@name`
  * `roles` - the ids of the member's roles
  * `joined_at` - when they joined, if discord says
  * `bot?` - whether the user is a bot
  """
  @type t() :: %__MODULE__{
          user_id: User.id(),
          username: String.t(),
          roles: [Role.id()],
          joined_at: joined_at(),
          bot?: boolean()
        }

  @doc "reads a member from discord's json, decoded with string keys"
  @spec from_json(map()) :: t()
  def from_json(%{"user" => user, "roles" => roles} = json) do
    %__MODULE__{
      user_id: String.to_integer(user["id"]),
      username: user["username"],
      roles: Enum.map(roles, &String.to_integer/1),
      joined_at: joined_at(json["joined_at"]),
      bot?: Map.get(user, "bot", false)
    }
  end

  @spec joined_at(String.t() | nil) :: joined_at()
  defp joined_at(nil), do: nil

  defp joined_at(timestamp) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(timestamp)
    DateTime.to_unix(datetime)
  end
end
