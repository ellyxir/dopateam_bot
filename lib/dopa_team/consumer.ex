defmodule DopaTeam.Consumer do
  use Nostrum.Consumer

  alias Nostrum.Api
#  require Logger

  @sdr_channel 849_267_950_988_820_482
  @bot_test_dm_asking 964_397_371_666_604_079
  @channels [@sdr_channel, @bot_test_dm_asking]

  def handle_event(
        {:MESSAGE_CREATE,
         %Nostrum.Struct.Message{
           author: %{bot: is_bot},
           guild_id: guild_id,
           channel_id: channel_id,
           member: %{roles: author_roles},
           content: content
         }, _ws_state}
      )
      when channel_id in @channels and is_nil(is_bot) do
    if has_mentions?(content) do
      mentioned_users = get_mentions(content)

      mentioned_string =
        Enum.reduce(mentioned_users, "", fn mentioned_user_id, acc ->
          mentioned_user_roles = get_roles(guild_id, mentioned_user_id)

          acc <>
            "roles for mentioned user #{mentioned_user_id}, roles=#{inspect(mentioned_user_roles)}\n"
        end)

      Api.create_message(
        channel_id,
        "message has mentions, list of user ids mentioned=#{inspect(mentioned_users)}\n" <>
          "author roles=#{inspect(author_roles)}\n" <>
          mentioned_string
      )
    end
  end

  # get their roles
  def get_roles(guild_id, user_id) when is_integer(guild_id) and is_integer(user_id) do
    {:ok, %Nostrum.Struct.Guild.Member{roles: roles}} =
      Nostrum.Api.get_guild_member(guild_id, user_id)

    roles
  end

  @doc """
  does the passed in string have a discord mention which looks like <@id> where id is a big integer
  """
  @spec has_mentions?(String.t()) :: boolean()
  def has_mentions?(message_content) when is_binary(message_content) do
    length(get_mentions(message_content)) > 0
  end

  @doc """
  returns a list of integer mention ids for users mentioned in the message
  """
  @spec get_mentions(String.t()) :: [integer()]
  def get_mentions(message_content) when is_binary(message_content) do
    regex = ~r/<@(\d+)>/

    Regex.scan(regex, message_content)
    |> Enum.map(fn [_ | [id]] -> id end)
    |> Enum.map(fn id_string ->
      {id, ""} = Integer.parse(id_string)
      id
    end)
  end
end
