defmodule DopaTeam.ConsumerIntroReportStaffTest do
  # the consumer uses the app's named task supervisor and report store, so
  # this can't run alongside other tests that start them
  use ExUnit.Case, async: false

  import DopaTeam.Factory
  import Mox

  alias DopaTeam.{Consumer, DiscordMock, ReportStore}
  alias Nostrum.Struct.{ApplicationCommandInteractionData, Interaction, Message}
  alias Nostrum.Struct.Guild.{Member, Role}

  @guild_id 1_176_811_717_213_306_880
  @mod_role 2

  setup :verify_on_exit!

  setup do
    start_supervised!(ReportStore)
    start_supervised!({Task.Supervisor, name: DopaTeam.TaskSupervisor})
    :ok
  end

  test "/intro-report from staff builds the report and edits the reply" do
    test_pid = self()

    stub(DiscordMock, :get_guild_roles, fn @guild_id ->
      {:ok,
       [
         %Role{id: 1, name: "No Intro"},
         %Role{id: @mod_role, name: "MOD"},
         %Role{id: 3, name: "Intro"}
       ]}
    end)

    expect(DiscordMock, :create_interaction_response, fn %Interaction{id: 900}, %{type: 5} ->
      {:ok}
    end)

    stub(DiscordMock, :list_guild_members, fn @guild_id, _options ->
      {:ok, [guild_member(10, roles: [1])]}
    end)

    expect(DiscordMock, :edit_interaction_response, fn %Interaction{id: 900}, response ->
      send(test_pid, {:edited, response})
      {:ok, %Message{id: 901}}
    end)

    interaction = %Interaction{
      id: 900,
      guild_id: @guild_id,
      member: %Member{roles: [@mod_role]},
      data: %ApplicationCommandInteractionData{name: "intro-report"}
    }

    Consumer.handle_event({:INTERACTION_CREATE, interaction, nil})

    assert_receive {:edited, %{content: content}}
    assert content =~ "1 with No Intro"
    assert {:ok, _report} = ReportStore.fetch(900)
  end

  test "a click on a report page button goes to the intro report command" do
    report = %DopaTeam.MemberReport{member_count: 0, no_intro: [], without_intro_roles: []}
    :ok = ReportStore.put(900, report)

    expect(DiscordMock, :create_interaction_response, fn %Interaction{id: 950}, response ->
      assert %{type: 7} = response
      {:ok}
    end)

    interaction = %Interaction{
      id: 950,
      type: 3,
      guild_id: @guild_id,
      member: %Member{roles: [@mod_role]},
      data: %ApplicationCommandInteractionData{custom_id: "intro-report:next:900:no_intro:0:2"}
    }

    Consumer.handle_event({:INTERACTION_CREATE, interaction, nil})
  end
end
