defmodule DopaTeam.Discord do
  @moduledoc """
  The Discord API calls the bot makes.

  `DopaTeam.Consumer` calls the module set as `:discord` in the
  `:dopa_team` app config. In production that is `DopaTeam.Discord.Nostrum`,
  which passes each call to nostrum's api modules; tests set a mock instead.
  """

  alias DopaTeam.Discord.GuildMember
  alias Nostrum.Struct.{Channel, Guild, Interaction, Message, User}
  alias Nostrum.Struct.Guild.{Member, Role}

  @typedoc "the error tuple nostrum returns when a discord api call fails"
  @type error() :: Nostrum.Api.error()

  @typedoc "a slash command definition, as discord's api takes it"
  @type command() :: map()

  @typedoc "an interaction response, as discord's api takes it"
  @type interaction_response() :: map()

  @typedoc "message text, or keyword options such as `content:` and `embeds:`"
  @type message_options() :: keyword() | map() | String.t()

  @typedoc "member fields to change, such as `roles:`"
  @type member_options() :: keyword() | map()

  @typedoc "paging options for a list call, such as `limit:` and `after:`"
  @type list_options() :: keyword()

  @doc "replaces the server's slash commands with these"
  @callback bulk_overwrite_guild_application_commands(Guild.id(), [command()]) ::
              {:ok, [map()]} | error()

  @doc "answers a slash command"
  @callback create_interaction_response(Interaction.t(), interaction_response()) ::
              {:ok} | error()

  @doc "replaces the reply to a slash command, such as a deferred one"
  @callback edit_interaction_response(Interaction.t(), interaction_response()) ::
              {:ok, Message.t()} | error()

  @doc "posts a message in a channel"
  @callback create_message(Channel.id(), message_options()) :: {:ok, Message.t()} | error()

  @doc "deletes a message"
  @callback delete_message(Message.t()) :: {:ok} | error()

  @doc "deletes the message with this id in a channel"
  @callback delete_message(Channel.id(), Message.id()) :: {:ok} | error()

  @doc "fetches a channel"
  @callback get_channel(Channel.id()) :: {:ok, Channel.t()} | error()

  @doc "fetches a member of a server"
  @callback get_guild_member(Guild.id(), User.id()) :: {:ok, Member.t()} | error()

  @doc "fetches every role in a server"
  @callback get_guild_roles(Guild.id()) :: {:ok, [Role.t()]} | error()

  @doc "fetches a user"
  @callback get_user(User.id()) :: {:ok, User.t()} | error()

  @doc """
  fetches one page of a server's members, up to `limit:` of them with user
  ids above `after:`, each with their username and whether they are a bot
  """
  @callback list_guild_members(Guild.id(), list_options()) ::
              {:ok, [GuildMember.t()]} | error()

  @doc "changes a member of a server"
  @callback modify_guild_member(Guild.id(), User.id(), member_options()) ::
              {:ok, Member.t()} | error()
end
