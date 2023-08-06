defmodule DopaTeam.Consumer do
  use Nostrum.Consumer

  alias Nostrum.Api
  require Logger

  @sdr_channel 849_267_950_988_820_482
  @bot_test_dm_asking 964_397_371_666_604_079
  @channels [@sdr_channel, @bot_test_dm_asking]
  @adult_role_name "18+"
  @minor_role_name "<18"

  def handle_event(
        {:MESSAGE_CREATE,
         %Nostrum.Struct.Message{
           author: %{id: author_id, bot: is_bot},
           guild_id: guild_id,
           channel_id: channel_id,
           member: %{roles: author_roles},
           content: content
         }, _ws_state}
      )
      when channel_id in @channels and is_nil(is_bot) do
    if has_mentions?(content) do
      server_roles = get_server_roles(guild_id)
      {:ok, adult_role_id} = get_role_id_by_name(server_roles, @adult_role_name)
      {:ok, minor_role_id} = get_role_id_by_name(server_roles, @minor_role_name)

      mentioned_users = get_mentions(content)

      mentioned_string =
        Enum.reduce(mentioned_users, "", fn mentioned_user_id, acc ->
          is_adult = user_has_role?(guild_id, mentioned_user_id, adult_role_id)
          is_minor = user_has_role?(guild_id, mentioned_user_id, minor_role_id)
          is_bot = is_user_bot?(mentioned_user_id)
          
          "#{acc}roles for mentioned user <@#{mentioned_user_id}>, is_adult?=#{is_adult}, is_minor?=#{is_minor}, is_bot?=#{is_bot}\n"
        end)

      is_author_adult = Enum.member?(author_roles, adult_role_id)
      is_author_minor = Enum.member?(author_roles, minor_role_id)

      Api.create_message(
        channel_id,
        "message has mentions, author (<@#{author_id}>) is_adult?=#{is_author_adult}, is_minor?=#{is_author_minor}\n" <>
          mentioned_string
      )
    end
  end

  @spec is_user_bot?(Nostrum.Struct.User.id()) :: boolean
  def is_user_bot?(user_id) do
    {:ok, %Nostrum.Struct.User{bot: is_bot}} = Nostrum.Api.get_user(user_id)

    case is_bot do
      nil -> false
      val when is_boolean(val) -> val
    end
  end

  @spec user_has_role?(
          Nostrum.Struct.Guild.id(),
          Nostrum.Struct.User.id(),
          Nostrum.Struct.Guild.Role.id()
        ) :: boolean()
  def user_has_role?(guild_id, user_id, role_id) do
    user_roles = get_user_roles(guild_id, user_id)
    Enum.member?(user_roles, role_id)
  end

  # get their roles
  @spec get_user_roles(Nostrum.Struct.Guild.id(), Nostrum.Struct.User.id()) :: [
          Nostrum.Struct.Guild.Role.id()
        ]
  def get_user_roles(guild_id, user_id) when is_integer(guild_id) and is_integer(user_id) do
    {:ok, %Nostrum.Struct.Guild.Member{roles: roles}} =
      Nostrum.Api.get_guild_member(guild_id, user_id)

    roles
  end

  @spec get_role_id_by_name([Nostrum.Struct.Guild.Role.t()], String.t()) ::
          {:ok, Nostrum.Struct.Guild.Role.id()} | {:error, String.t()}
  def get_role_id_by_name(server_roles, role_name)
      when is_list(server_roles) and is_binary(role_name) do
    role_id =
      Enum.find_value(server_roles, fn elem ->
        if elem.name == role_name do
          elem.id
        else
          false
        end
      end)

    case role_id do
      nil -> {:error, "role id not found"}
      id when is_number(id) -> {:ok, id}
    end
  end

  @spec get_server_roles(Nostrum.Struct.Guild.id()) :: [Nostrum.Struct.Guild.Role.t()]
  def get_server_roles(guild_id) when is_integer(guild_id) do
    {:ok, roles} = Nostrum.Api.get_guild_roles(guild_id)
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
