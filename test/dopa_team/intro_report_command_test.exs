defmodule DopaTeam.IntroReportCommandTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Mox

  alias DopaTeam.DiscordMock
  alias DopaTeam.IntroReportCommand
  alias DopaTeam.{MemberReport, ReportStore}
  alias Nostrum.Struct.Guild.{Member, Role}
  alias Nostrum.Struct.{Interaction, Message, User}

  @guild_id 1_176_811_717_213_306_880

  @mod_role 2
  @adult_role 18

  setup :verify_on_exit!

  setup do
    stub(DiscordMock, :get_guild_roles, fn @guild_id ->
      {:ok,
       [
         %Role{id: 1, name: "No Intro"},
         %Role{id: @mod_role, name: "MOD"},
         %Role{id: 3, name: "Intro"},
         %Role{id: @adult_role, name: "18+"}
       ]}
    end)

    :ok
  end

  defp interaction(author_roles) do
    %Interaction{id: 900, guild_id: @guild_id, member: %Member{roles: author_roles}}
  end

  test "someone who isn't staff is told the command is for staff" do
    expect(DiscordMock, :create_interaction_response, fn %Interaction{id: 900}, response ->
      assert %{type: 4, data: %{flags: 64, content: content}} = response
      assert content =~ "staff"
      {:ok}
    end)

    expect(DiscordMock, :list_guild_members, 0, fn _guild_id, _options -> {:ok, []} end)

    IntroReportCommand.handle(interaction([@adult_role]))
  end

  test "staff get a private 'thinking' reply, then the counts once the report is built",
       context do
    test_pid = self()
    task_supervisor = Module.concat(__MODULE__, "Tasks#{context.line}")
    store = Module.concat(__MODULE__, "Store#{context.line}")
    start_supervised!({Task.Supervisor, name: task_supervisor})
    start_supervised!({ReportStore, name: store})

    expect(DiscordMock, :create_interaction_response, fn %Interaction{id: 900}, response ->
      assert response == %{type: 5, data: %{flags: 64}}
      {:ok}
    end)

    stub(DiscordMock, :list_guild_members, fn @guild_id, _options ->
      {:ok,
       [
         %Member{user_id: 10, roles: [1]},
         %Member{user_id: 11, roles: [3]},
         %Member{user_id: 12, roles: []}
       ]}
    end)

    stub(DiscordMock, :get_user, fn user_id -> {:ok, %User{id: user_id, bot: nil}} end)

    expect(DiscordMock, :edit_interaction_response, fn %Interaction{id: 900}, response ->
      send(test_pid, {:edited, response})
      {:ok, %Message{id: 901}}
    end)

    IntroReportCommand.handle(interaction([@adult_role, @mod_role]),
      task_supervisor: task_supervisor,
      store: store
    )

    assert_receive {:edited, %{content: content}}
    assert content =~ "1 with No Intro"
    assert content =~ "1 with neither Intro nor No Intro"
    assert {:ok, %MemberReport{member_count: 3}} = ReportStore.fetch(store, 900)
  end

  test "staff are told when the report fails", context do
    test_pid = self()
    task_supervisor = Module.concat(__MODULE__, "Tasks#{context.line}")
    store = Module.concat(__MODULE__, "Store#{context.line}")
    start_supervised!({Task.Supervisor, name: task_supervisor})
    start_supervised!({ReportStore, name: store})

    stub(DiscordMock, :create_interaction_response, fn _interaction, _response -> {:ok} end)

    stub(DiscordMock, :list_guild_members, fn @guild_id, _options ->
      {:error, %Nostrum.Error.ApiError{status_code: 500}}
    end)

    expect(DiscordMock, :edit_interaction_response, fn %Interaction{id: 900}, response ->
      send(test_pid, {:edited, response})
      {:ok, %Message{id: 901}}
    end)

    log =
      capture_log(fn ->
        IntroReportCommand.handle(interaction([@mod_role]),
          task_supervisor: task_supervisor,
          store: store
        )

        assert_receive {:edited, %{content: content}}
        assert content =~ "report failed"
      end)

    assert log =~ "intro report failed"
    assert ReportStore.fetch(store, 900) == :error
  end

  test "staff are told the report failed when building it crashes", context do
    test_pid = self()
    task_supervisor = Module.concat(__MODULE__, "Tasks#{context.line}")
    start_supervised!({Task.Supervisor, name: task_supervisor})

    stub(DiscordMock, :create_interaction_response, fn _interaction, _response -> {:ok} end)
    stub(DiscordMock, :list_guild_members, fn @guild_id, _options -> {:ok, []} end)

    expect(DiscordMock, :edit_interaction_response, fn %Interaction{id: 900}, response ->
      send(test_pid, {:edited, response})
      {:ok, %Message{id: 901}}
    end)

    log =
      capture_log(fn ->
        # no store runs under this name, so storing the report crashes
        IntroReportCommand.handle(interaction([@mod_role]),
          task_supervisor: task_supervisor,
          store: Module.concat(__MODULE__, "NoStore")
        )

        assert_receive {:edited, %{content: content}}
        assert content =~ "report failed"
      end)

    assert log =~ "intro report crashed"
  end

  test "a reply that can't be edited is logged", context do
    test_pid = self()
    task_supervisor = Module.concat(__MODULE__, "Tasks#{context.line}")
    store = Module.concat(__MODULE__, "Store#{context.line}")
    start_supervised!({Task.Supervisor, name: task_supervisor})
    start_supervised!({ReportStore, name: store})

    stub(DiscordMock, :create_interaction_response, fn _interaction, _response -> {:ok} end)
    stub(DiscordMock, :list_guild_members, fn @guild_id, _options -> {:ok, []} end)

    stub(DiscordMock, :edit_interaction_response, fn _interaction, _response ->
      send(test_pid, :edited)
      {:error, %Nostrum.Error.ApiError{status_code: 404}}
    end)

    log =
      capture_log(fn ->
        {:ok, pid} =
          IntroReportCommand.handle(interaction([@mod_role]),
            task_supervisor: task_supervisor,
            store: store
          )

        ref = Process.monitor(pid)
        assert_receive :edited
        assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
      end)

    assert log =~ "couldn't edit the intro report reply"
  end
end
