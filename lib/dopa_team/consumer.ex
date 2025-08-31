defmodule DopaTeam.Consumer do
  use Nostrum.Consumer

  alias Nostrum.Api
  require Logger

  @bot_message_delete_time_ms 30000

  # the discord server ids
  @live_guild_id 1_160_011_667_204_231_300
  @bot_test_guild_id 1_176_811_717_213_306_880

  # the channel is where we want dm audit logging to go to
  @logging_channel %{
    @live_guild_id => 1_160_606_680_741_056_652,
    @bot_test_guild_id => 964_397_371_666_604_076
  }

  @vc_status_logging_channel %{
    @live_guild_id => 1_160_011_672_170_287_196,
    @bot_test_guild_id => 1_163_155_790_014_717_975
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

  # channel we want to delete messages from after a while
  @disappearing_messages_channel_id 1_166_451_556_607_078_430
  @disappearing_messages_timeout_sec 86400

  # roles we care about, this needs to match the role name exactly in the server
  @adult_role_18_name "18+"
  @adult_role_30_name "30+"
  @minor_role_13_name "13-15"
  @minor_role_16_name "16-17"
  @closed_dm_role_name "Closed DM"
  @no_intro_role_name "No Intro"
  @intro_role_name "Intro"
  @rules_role_name "Rules"
  @admin_role_name "Admins"
  @mod_role_name "MOD"
  @helper_role_name "Helpers"

  # command to list all bots in server
  @botlist_command "botlist"

  # water stuff
  @water_command "water"
  @water_elapsed_time_sec 3 * 60 * 60
  @water_role_id 1_160_011_667_606_863_892
  # dev @water_role_id 1_176_811_717_213_306_887
  @water_emoji "<:water_bottle:1160222447069560933>"
  # dev @water_emoji "<:water_bottle:1191095859350360074>"

  @command_list [
    # %{
    #   name: @botlist_command,
    #   description: "List all bots in the server"
    # },
    %{
      name: @water_command,
      description: "Send a water reminder ping",
      options: [
        %{
          # STRING, see "Application Command Option Type" in Discord API
          type: 3,
          name: "water_message",
          description: "Message to customize water ping",
          required: false
        }
      ]
    }
  ]

  def handle_event({:READY, %Nostrum.Struct.Event.Ready{} = ready_event, _ws_state}) do
    handle_ready_event(ready_event)
  end

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
           author: %{bot: nil},
           guild_id: guild_id,
           channel_id: @disappearing_messages_channel_id
         } = _original_message, _ws_state}
      ) do
    handle_disappearing_message(
      guild_id,
      @disappearing_messages_channel_id,
      msg_id,
      @disappearing_messages_timeout_sec
    )
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
          "<@#{author_id}> please note that the user(s) you have mentioned is a minor and/or has the Closed DM role. Your request is not allowed according to server rules. Please see rule 10 at https://discord.com/channels/1160011667204231300/1160011784766378054 for more information.\n"

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

  def handle_event(
        {:INTERACTION_CREATE,
         %Nostrum.Struct.Interaction{
           guild_id: _guild_id,
           data: %{name: @water_command, options: _options}
         } =
           interaction, _ws_state}
      ) do
    handle_water_command(interaction)
  end

  def handle_event(
        {:INTERACTION_CREATE,
         %Nostrum.Struct.Interaction{
           guild_id: _guild_id,
           data: %{name: @botlist_command, options: _options}
         } =
           interaction, _ws_state}
      ) do
    # defer message response
    {:ok} = Nostrum.Api.create_interaction_response(interaction, %{type: 5})

    # all_members = get_all_members(guild_id)
    # all_user_ids =
    #   Enum.map(all_members, fn %Nostrum.Struct.Guild.Member{user_id: user_id} ->
    #     user_id
    #   end)

    # all_users =
    #   Enum.reduce(all_user_ids, [], fn user_id, acc ->
    #     {:ok, user} = Nostrum.Api.get_user(user_id)
    #     Logger.warn("getting user #{inspect user_id}")
    #     [user | acc]
    #   end)

    # all_bots =
    #   Enum.filter(all_users, fn %Nostrum.Struct.User{bot: is_bot} ->
    #     is_bot
    #   end)

    # Logger.error("all bots=#{inspect all_bots}")
    # embed_msg =
    #   Enum.reduce(all_bots, "", fn %Nostrum.Struct.User{} = user, acc ->
    #     "ID:#{inspect(user.id)}, username:#{user.username}, is bot:#{inspect(user.bot)}\n" <> acc
    #   end)

    # embed =
    #   %Nostrum.Struct.Embed{}
    #   |> Nostrum.Struct.Embed.put_title("Bot List")
    #   |> Nostrum.Struct.Embed.put_description(embed_msg)

    # response = %{
    #   type: 4,
    #   data: %{
    #     embeds: [embed]
    #   }
    # }

    # Nostrum.Api.edit_interaction_response(interaction, response)
  end

  # def handle_event(
  #       {:VOICE_CHANNEL_STATUS_UPDATE,
  #       voice_status_update, _ws_state}
  #     ) do
  #   Logger.warning("Got Voice channel status update: #{inspect voice_status_update}")
  # end

  # def handle_event(
  #   {:CHANNEL_TOPIC_UPDATE,
  #   channel_topic_update, _ws_state}
  # ) do
  #   Logger.warning("Got channel topic update: #{inspect channel_topic_update}")
  # end

  def handle_event(
        {:GUILD_AUDIT_LOG_ENTRY_CREATE,
         %Nostrum.Struct.Guild.AuditLogEntry{
           action_type: 192,
           options: %{status: status_text},
           target_id: channel_id,
           user_id: user_id
         }, _ws_state}
      ) do
    {:ok, %Nostrum.Struct.Channel{guild_id: guild_id}} = Nostrum.Api.get_channel(channel_id)

    # Logger.warning(
    #   "got log event for channel topic update event, status=:#{inspect(status_text)}, channel_id=#{inspect(channel_id)}, user_id=#{inspect(user_id)}, guild_id=#{inspect(guild_id)}"
    # )

    log_vc_event(
      guild_id,
      "<@#{user_id}> (user id #{user_id}) changed status for channel <##{channel_id}>, new status=#{inspect(status_text)}"
    )
  end

  @doc """
  handler for messages we should delete after a timeout  
  """
  @spec handle_disappearing_message(
          Nostrum.Struct.Guild.id(),
          Nostrum.Struct.Channel.id(),
          Nostrum.Struct.Message.id(),
          integer()
        ) :: term()
  def handle_disappearing_message(guild_id, channel_id, msg_id, timeout_sec)
      when is_integer(guild_id) and is_integer(channel_id) and is_integer(msg_id) and
             is_integer(timeout_sec) do
    # TODO: fix this
    #    _ =
    #      spawn(fn ->
    #        :ok = Process.sleep(timeout_sec * 1000)
    #        {:ok} = Nostrum.Api.delete_message(channel_id, msg_id)
    #      end)
    :ok
  end

  @doc """
    checks elapsed time since last water ping, if ok then sends message
  """
  @spec handle_water_command(Nostrum.Struct.Interaction.t()) :: term()
  def handle_water_command(%Nostrum.Struct.Interaction{} = interaction) do
    last_ping_sec = DopaTeam.WaterPing.get_timer()
    now = DopaTeam.WaterPing.now()

    handle_water_command_helper(interaction, now - last_ping_sec)
  end

  defp handle_water_command_helper(
         %Nostrum.Struct.Interaction{
           data: %Nostrum.Struct.ApplicationCommandInteractionData{
             options: options
           }
         } = interaction,
         elapsed_time_sec
       )
       when is_integer(elapsed_time_sec) and elapsed_time_sec >= @water_elapsed_time_sec do
    # success, we can send ping
    # update the timer now to minimize race condition time
    DopaTeam.WaterPing.set_timer()

    user = %Nostrum.Struct.User{} = interaction.user

    # send ephemeral message back to the posting user
    msg = %{
      type: 4,
      data: %{
        content: "Thank you for the water ping!",
        flags: 64
      }
    }

    _ = Nostrum.Api.create_interaction_response(interaction, msg)

    # send message to everyone in water channel
    # get the users name since often the discord cache doesn't work
    username = get_name(interaction.guild_id, interaction.user)

    default_message = "<@#{user.id}> (#{username}) would like to remind you to drink some water!"

    custom_message =
      case get_option(options, "water_message") do
        s when is_binary(s) -> "#{default_message}\nCustom message: #{s}"
        nil -> default_message
        what -> "WHAT IS THIS??? #{inspect(what)}"
      end

    msg = %{
      content: "<@&#{@water_role_id}>",
      embeds: [
        %Nostrum.Struct.Embed{
          title: "Water Reminder! #{@water_emoji}#{@water_emoji}",
          description: custom_message
        }
      ]
    }

    _ = Nostrum.Api.create_message(interaction.channel_id, msg)
  end

  defp handle_water_command_helper(%Nostrum.Struct.Interaction{} = interaction, elapsed_time_sec)
       when is_integer(elapsed_time_sec) and elapsed_time_sec < @water_elapsed_time_sec do
    wait_min = div(@water_elapsed_time_sec - elapsed_time_sec, 60) + 1

    msg = %{
      # ChannelMessageWithSource
      type: 4,
      data: %{
        content: "Please wait #{wait_min} minutes before next water ping.",
        # ephemeral
        flags: 64
      }
    }

    _ = Nostrum.Api.create_interaction_response(interaction, msg)
  end

  @doc """
    returns the nickname of the user if avail or username or <@userid> mention format if all fails
  """
  @spec get_name(Nostrum.Struct.Guild.id(), Nostrum.Struct.User.t()) :: String.t()
  def get_name(guild_id, %Nostrum.Struct.User{id: user_id} = user) when is_integer(guild_id) do
    with {:ok, %Nostrum.Struct.Guild.Member{} = member} <-
           Nostrum.Api.get_guild_member(guild_id, user_id),
         nickname when is_binary(nickname) <- member.nick do
      nickname
    else
      _ ->
        if is_binary(user.username) do
          user.username
        else
          Nostrum.Struct.User.mention(user)
        end
    end
  end

  defp get_all_members(guild_id) when is_number(guild_id) do
    {:ok, member_list} = Nostrum.Api.list_guild_members(guild_id, limit: 1000, after: 0)
    member_list
  end

  defp handle_ready_event(%Nostrum.Struct.Event.Ready{} = ready_event) do
    Enum.each(ready_event.guilds, fn %Nostrum.Struct.Guild.UnavailableGuild{id: guild_id} ->
      Logger.warning("Ready event: registering commands for guild id: #{inspect(guild_id)}")
      Nostrum.Api.bulk_overwrite_guild_application_commands(guild_id, @command_list)
    end)
  end

  @spec has_role?(Nostrum.Struct.Guild.id(), Nostrum.Struct.User.id(), [non_neg_integer()]) :: Boolean
  defp has_role?(guild_id, user_id, role_name_list) when is_integer(user_id) and is_list(role_name_list) do
    server_roles = get_server_roles(guild_id)
    role_id_list = Enum.map(role_name_list, fn role_name -> 
      {:ok, role_id} = get_role_id_by_name(server_roles, role_name) 
      role_id
    end)
    Enum.member?(user_id, role_id_list)
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
    {:ok, rules_role_id} = get_role_id_by_name(server_roles, @rules_role_name)
    
    Logger.warning("Role IDs resolved - no_intro: #{inspect(no_intro_role_id)}, intro: #{inspect(intro_role_id)}, rules: #{inspect(rules_role_id)}")
    is_user_no_intro = Enum.member?(author_role_ids, no_intro_role_id)
    msg_has_space = String.contains?(msg_content, " ")

    Logger.warning(
      "intro message from userid: #{author_id}, is user no intro?:#{inspect(is_user_no_intro)}, msg space?:#{inspect(msg_has_space)}"
    )

    if is_user_no_intro && msg_has_space do
      {:ok, _updated_member} =
        modify_roles(guild_id, author_id, author_role_ids, [intro_role_id], [no_intro_role_id, rules_role_id])

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
    Logger.warning("modify roles: user_id: #{inspect user_id}, current roles: #{inspect current_role_ids}, to_add: #{inspect role_ids_to_add}, to_remove: #{inspect role_ids_to_remove}")
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
        Logger.warning("no channel for dm-asking logging configured for guild id #{guild_id}")
    end
  end

  @spec log_vc_event(Nostrum.Struct.Guild.id(), String.t()) :: any()
  def log_vc_event(guild_id, log_message) when is_integer(guild_id) and is_binary(log_message) do
    case Map.fetch(@vc_status_logging_channel, guild_id) do
      {:ok, channel_id} ->
        Api.create_message(
          channel_id,
          log_message
        )

      :error ->
        Logger.warning("no channel for VC logging configured for guild id #{guild_id}")
    end
  end

  @spec is_dm_request_allowed?(
          Nostrum.Struct.Guild.id(),
          [Nostrum.Struct.Guild.Role.id()],
          [Nostrum.Struct.User.id()] | Nostrum.Struct.User.id()
        ) :: boolean()
  def is_dm_request_allowed?(guild_id, author_roles, mentioned_user_ids)
      when is_integer(guild_id) and is_list(author_roles) and is_list(mentioned_user_ids) do
    if Enum.any?(author_roles, fn role_id -> role_id in [1160011667732709413, 1160011667732709412] end) do
      Logger.warning("is_dm_request_allowed?: is mod or helper")
      true
    else
      Logger.warning("is_dm_request_allowed?: is not mod or helper")
      Enum.reduce(mentioned_user_ids, true, fn mentioned_user_id, acc ->
        acc && is_dm_request_allowed?(guild_id, author_roles, mentioned_user_id)
      end)
    end
  end

  def is_dm_request_allowed?(guild_id, author_roles, mentioned_user_id)
      when is_integer(guild_id) and is_list(author_roles) and is_integer(mentioned_user_id) do
    server_roles = get_server_roles(guild_id)
    {:ok, adult_role_18_id} = get_role_id_by_name(server_roles, @adult_role_18_name)
    {:ok, adult_role_30_id} = get_role_id_by_name(server_roles, @adult_role_30_name)
    {:ok, minor_role_13_id} = get_role_id_by_name(server_roles, @minor_role_13_name)
    {:ok, minor_role_16_id} = get_role_id_by_name(server_roles, @minor_role_16_name)
    {:ok, closed_dm_role_id} = get_role_id_by_name(server_roles, @closed_dm_role_name)

    is_author_adult =
      Enum.member?(author_roles, adult_role_18_id) ||
        Enum.member?(author_roles, adult_role_30_id)

    # is_author_minor = Enum.member?(author_roles, minor_role_id)

    # is_mentioned_adult = user_has_role?(guild_id, mentioned_user_id, adult_role_id)
    is_mentioned_minor =
      user_has_role?(guild_id, mentioned_user_id, minor_role_13_id) ||
        user_has_role?(guild_id, mentioned_user_id, minor_role_16_id)

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

  @doc """
    finds matching option from list of options using the option_name, pulls out option value from ApplicationCommandInteractionDataOption
  """
  @spec get_option(
          [Nostrum.Struct.ApplicationCommandInteractionDataOption.t()],
          String.t(),
          any()
        ) :: any()

  def get_option(options, option_name, default \\ nil)

  def get_option(options, option_name, default)
      when is_list(options) and is_binary(option_name) do
    option_values = for %{name: ^option_name, value: value} = _opt <- options, do: value

    case option_values do
      [value | _] -> value
      _ -> default
    end
  end

  def get_option(nil, _option_name, default), do: default
end
