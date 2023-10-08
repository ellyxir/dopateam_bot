defmodule DopaTeam.Consumer do
  use Nostrum.Consumer

  alias Nostrum.Api
  require Logger

  @bot_message_delete_time_ms 30000

  # the discord server ids
  @live_guild_id 1_160_011_667_204_231_300
  @bot_test_guild_id 964_397_371_213_615_124

  # the channel is where we want audit logging to go to
  @logging_channel %{
    @live_guild_id => 1_160_606_680_741_056_652,
    @bot_test_guild_id => 964_397_371_666_604_076
  }

  # channels for dm asking
  @live_dm_asking_channel 1_160_011_669_003_587_584
  @bot_test_dm_asking_channel 964_397_371_666_604_079

  # channels for intro
  @live_intro_channel 1_160_011_668_500_250_734
  @bot_test_intro_channel 964_397_371_314_274_342

  # channels we are listening to
  @dm_channels [@live_dm_asking_channel, @bot_test_dm_asking_channel]
  @intro_channels [@live_intro_channel, @bot_test_intro_channel]

  # roles we care about, this needs to match the role name exactly in the server
  @adult_role_name "18+"
  @minor_role_name "<18"
  @closed_dm_role_name "Closed DM"
  @no_intro_role_name "No Intro"
  @intro_role_name "Intro"

  @doc """
  handles an incoming message in one of the channels we are listening to
  """
  def handle_event(
        {:MESSAGE_CREATE,
         %Nostrum.Struct.Message{
           id: msg_id,
           author: %{id: author_id, bot: is_bot},
           guild_id: guild_id,
           channel_id: channel_id,
           member: %{roles: author_role_ids},
           content: content
         } = _original_message, _ws_state}
      )
      when channel_id in @intro_channels and is_nil(is_bot) do
    handle_intro_message(guild_id, channel_id, msg_id, author_id, author_role_ids, content)
  end

  def handle_event(
        {:MESSAGE_CREATE,
         %Nostrum.Struct.Message{
           id: msg_id,
           author: %{id: author_id, bot: is_bot},
           guild_id: guild_id,
           channel_id: channel_id,
           member: %{roles: author_roles},
           content: content
         } = original_message, _ws_state}
      )
      when channel_id in @dm_channels and is_nil(is_bot) do
    if has_mentions?(content) do
      mentioned_users = get_mentions(content)

      if not is_dm_request_allowed?(guild_id, author_roles, mentioned_users) do
        msg =
          "<@#{author_id}> please note that the user(s) you have mentioned is a minor and/or has the Closed DM role. Your request is not allowed according to server rules. See https://discord.com/channels/821855117539541003/928601274352541718/1086113286438789120 for more information.\n"

        {:ok, %Nostrum.Struct.Message{id: bot_msg_id}} =
          Api.create_message(
            channel_id,
            content: msg,
            message_reference: %{message_id: msg_id}
          )

        # delete original message
        case Nostrum.Api.delete_message(original_message) do
          {:error, reason} ->
            Logger.error(
              "could not delete message id #{msg_id} in channel #{channel_id}, reason=#{inspect(reason)}"
            )

          {:ok} ->
            {:ok}
        end

        log_illegal_dm_request(guild_id, author_id, mentioned_users)

        pid =
          spawn(fn ->
            receive do
              {:delete, channel_id, bot_msg_id} ->
                Nostrum.Api.delete_message(channel_id, bot_msg_id)
            end
          end)

        Process.send_after(pid, {:delete, channel_id, bot_msg_id}, @bot_message_delete_time_ms)
      end
    end
  end

  defp handle_intro_message(
         guild_id,
         channel_id,
         _msg_id,
         author_id,
         author_role_ids,
         msg_content
       )
       when channel_id in @intro_channels do
    # logic: does msg_content have at least a space
    # and is the user "No Intro",
    # if so, we remove "No Intro", and add "Intro"
    server_roles = get_server_roles(guild_id)
    {:ok, no_intro_role_id} = get_role_id_by_name(server_roles, @no_intro_role_name)
    {:ok, intro_role_id} = get_role_id_by_name(server_roles, @intro_role_name)
    is_user_no_intro = Enum.member?(author_role_ids, no_intro_role_id)
    msg_has_space = String.contains?(msg_content, " ")

    if is_user_no_intro && msg_has_space do
      {:ok, _updated_member} =
        modify_roles(guild_id, author_id, author_role_ids, [intro_role_id], [no_intro_role_id])

      # Api.create_message(
      #   channel_id,
      #   content:
      #     "adding intro role and removing no intro role for <@#{author_id}>, updated roles=#{inspect updated_member.roles}",
      #   message_reference: %{message_id: msg_id}
      # )
    end
  end

  @doc """
  adds roles and removes roles in one pass. will do adds first then removes
  """
  def modify_roles(guild_id, user_id, current_role_ids, role_ids_to_add, role_ids_to_remove)
      when is_integer(guild_id) and is_integer(user_id) and is_list(current_role_ids) and
             is_list(role_ids_to_add) and is_list(role_ids_to_remove) do
    # Logger.warning("modify roles: current roles: #{inspect current_role_ids}, to_add: #{inspect role_ids_to_add}, to_remove: #{inspect role_ids_to_remove}")
    updated_roles =
      (current_role_ids ++ role_ids_to_add)
      |> Enum.uniq()
      |> Enum.reduce([], fn elem, acc ->
        if Enum.member?(role_ids_to_remove, elem) do
          acc
        else
          [elem | acc]
        end
      end)

    Nostrum.Api.modify_guild_member(guild_id, user_id, roles: updated_roles)
  end

  @spec log_illegal_dm_request(Nostrum.Struct.Guild.id(), Nostrum.Struct.User.id(), [
          Nostrum.Struct.User.id()
        ]) :: any()
  def log_illegal_dm_request(guild_id, author_id, mentioned_users) do
    mention_refs =
      Enum.reduce(mentioned_users, "", fn id, acc ->
        "#{acc}<@#{id}> (user id: #{id}), "
      end)

    log_event(
      guild_id,
      "Logging - <@#{author_id}> (user id #{author_id}) requested DM to minor/closed DM, users=#{mention_refs}"
    )
  end

  @spec log_event(Nostrum.Struct.Guild.id(), String.t()) :: any()
  def log_event(guild_id, log_message) when is_integer(guild_id) and is_binary(log_message) do
    case Map.fetch(@logging_channel, guild_id) do
      {:ok, channel_id} ->
        Api.create_message(
          channel_id,
          log_message
        )

      :error ->
        Logger.warning("no channel for logging configured for guild id #{guild_id}")
    end
  end

  @spec is_dm_request_allowed?(
          Nostrum.Struct.Guild.id(),
          [Nostrum.Struct.Guild.Role.id()],
          [Nostrum.Struct.User.id()] | Nostrum.Struct.User.id()
        ) :: boolean()
  def is_dm_request_allowed?(guild_id, author_roles, mentioned_user_ids)
      when is_integer(guild_id) and is_list(author_roles) and is_list(mentioned_user_ids) do
    Enum.reduce(mentioned_user_ids, true, fn mentioned_user_id, acc ->
      acc && is_dm_request_allowed?(guild_id, author_roles, mentioned_user_id)
    end)
  end

  def is_dm_request_allowed?(guild_id, author_roles, mentioned_user_id)
      when is_integer(guild_id) and is_list(author_roles) and is_integer(mentioned_user_id) do
    server_roles = get_server_roles(guild_id)
    {:ok, adult_role_id} = get_role_id_by_name(server_roles, @adult_role_name)
    {:ok, minor_role_id} = get_role_id_by_name(server_roles, @minor_role_name)
    {:ok, closed_dm_role_id} = get_role_id_by_name(server_roles, @closed_dm_role_name)

    is_author_adult = Enum.member?(author_roles, adult_role_id)
    # is_author_minor = Enum.member?(author_roles, minor_role_id)

    # is_mentioned_adult = user_has_role?(guild_id, mentioned_user_id, adult_role_id)
    is_mentioned_minor = user_has_role?(guild_id, mentioned_user_id, minor_role_id)
    is_mentioned_closed_dm = user_has_role?(guild_id, mentioned_user_id, closed_dm_role_id)
    is_mentioned_bot = is_user_bot?(mentioned_user_id)

    cond do
      is_mentioned_closed_dm -> false
      # if we are mentioning a bot, who cares
      is_mentioned_bot -> true
      # if author is adult and mentioned user is minor
      is_author_adult && is_mentioned_minor -> false
      # otherwise its all good
      true -> true
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
