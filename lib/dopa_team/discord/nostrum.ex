defmodule DopaTeam.Discord.Nostrum do
  @moduledoc """
  The production `DopaTeam.Discord`: passes each call to `Nostrum.Api`.
  """

  @behaviour DopaTeam.Discord

  @impl true
  defdelegate bulk_overwrite_guild_application_commands(guild_id, commands), to: Nostrum.Api

  @impl true
  defdelegate create_interaction_response(interaction, response), to: Nostrum.Api

  @impl true
  defdelegate create_message(channel_id, options), to: Nostrum.Api

  @impl true
  defdelegate delete_message(message), to: Nostrum.Api

  @impl true
  defdelegate delete_message(channel_id, message_id), to: Nostrum.Api

  @impl true
  defdelegate get_channel(channel_id), to: Nostrum.Api

  @impl true
  defdelegate get_guild_member(guild_id, user_id), to: Nostrum.Api

  @impl true
  defdelegate get_guild_roles(guild_id), to: Nostrum.Api

  @impl true
  defdelegate get_user(user_id), to: Nostrum.Api

  @impl true
  defdelegate modify_guild_member(guild_id, user_id, options), to: Nostrum.Api
end
