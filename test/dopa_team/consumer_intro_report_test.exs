defmodule DopaTeam.ConsumerIntroReportTest do
  use ExUnit.Case, async: true

  import Mox

  alias DopaTeam.Consumer
  alias DopaTeam.DiscordMock
  alias Nostrum.Struct.{ApplicationCommandInteractionData, Interaction}
  alias Nostrum.Struct.Event.Ready
  alias Nostrum.Struct.Guild.{Member, Role, UnavailableGuild}

  @guild_id 1_176_811_717_213_306_880

  setup :verify_on_exit!

  test "/intro-report goes to the intro report command" do
    stub(DiscordMock, :get_guild_roles, fn @guild_id -> {:ok, [%Role{id: 2, name: "MOD"}]} end)

    expect(DiscordMock, :create_interaction_response, fn %Interaction{id: 900}, response ->
      assert response.data.content =~ "staff only"
      {:ok}
    end)

    interaction = %Interaction{
      id: 900,
      guild_id: @guild_id,
      member: %Member{roles: []},
      data: %ApplicationCommandInteractionData{name: "intro-report"}
    }

    Consumer.handle_event({:INTERACTION_CREATE, interaction, nil})
  end

  test "the bot registers /intro-report when it connects" do
    expect(DiscordMock, :bulk_overwrite_guild_application_commands, fn @guild_id, commands ->
      assert "intro-report" in Enum.map(commands, & &1.name)
      {:ok, []}
    end)

    Consumer.handle_event({:READY, %Ready{guilds: [%UnavailableGuild{id: @guild_id}]}, nil})
  end
end
