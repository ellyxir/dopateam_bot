defmodule DopaTeam.Discord.Nostrum do
  @moduledoc """
  The production `DopaTeam.Discord`: passes each call to nostrum's api
  modules, such as `Nostrum.Api.Message` and `Nostrum.Api.Guild`.
  """

  @behaviour DopaTeam.Discord

  alias Nostrum.Api.{ApplicationCommand, Channel, Guild, Interaction, Message, User}

  @impl true
  defdelegate bulk_overwrite_guild_application_commands(guild_id, commands),
    to: ApplicationCommand,
    as: :bulk_overwrite_guild_commands

  @impl true
  defdelegate create_interaction_response(interaction, response),
    to: Interaction,
    as: :create_response

  @impl true
  defdelegate create_message(channel_id, options), to: Message, as: :create

  @impl true
  defdelegate delete_message(message), to: Message, as: :delete

  @impl true
  defdelegate delete_message(channel_id, message_id), to: Message, as: :delete

  @impl true
  defdelegate edit_interaction_response(interaction, response),
    to: Interaction,
    as: :edit_response

  @impl true
  defdelegate get_channel(channel_id), to: Channel, as: :get

  @impl true
  defdelegate get_guild_member(guild_id, user_id), to: Guild, as: :member

  @impl true
  defdelegate get_guild_roles(guild_id), to: Guild, as: :roles

  @impl true
  defdelegate get_user(user_id), to: User, as: :get

  @impl true
  defdelegate list_guild_members(guild_id, options), to: Guild, as: :members

  @impl true
  defdelegate modify_guild_member(guild_id, user_id, options), to: Guild, as: :modify_member
end
