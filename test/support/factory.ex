defmodule DopaTeam.Factory do
  @moduledoc "builds the structs tests feed to the bot"

  alias DopaTeam.Discord.GuildMember

  @doc """
  a listed server member who is not a bot, has no roles and no join date,
  unless `fields` say otherwise
  """
  @spec guild_member(non_neg_integer(), keyword()) :: GuildMember.t()
  def guild_member(user_id, fields \\ []) do
    struct!(
      %GuildMember{
        user_id: user_id,
        username: "user#{user_id}",
        roles: [],
        joined_at: nil,
        bot?: false
      },
      fields
    )
  end
end
