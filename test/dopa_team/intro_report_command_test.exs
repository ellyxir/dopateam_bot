defmodule DopaTeam.IntroReportCommandTest do
  use ExUnit.Case, async: true

  import DopaTeam.Factory
  import ExUnit.CaptureLog
  import Mox

  alias DopaTeam.DiscordMock
  alias DopaTeam.IntroReportCommand
  alias DopaTeam.{MemberReport, ReportStore}
  alias Nostrum.Struct.{ApplicationCommandInteractionData, Interaction, Message}
  alias Nostrum.Struct.Guild.{Member, Role}

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

  test "staff get a private 'thinking' reply, then the first page once the report is built",
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
         guild_member(10, roles: [1], joined_at: 1_767_225_600),
         guild_member(11, roles: [3], joined_at: 1_767_225_600),
         guild_member(12, joined_at: 1_767_225_600)
       ]}
    end)

    expect(DiscordMock, :edit_interaction_response, fn %Interaction{id: 900}, response ->
      send(test_pid, {:edited, response})
      {:ok, %Message{id: 901}}
    end)

    IntroReportCommand.handle(interaction([@adult_role, @mod_role]),
      task_supervisor: task_supervisor,
      store: store
    )

    assert_receive {:edited, %{content: content, embeds: [embed], components: [_buttons]}}
    assert content == "3 members, 1 with No Intro, 1 with neither Intro nor No Intro"
    assert embed.description == "<@10> · joined 2026-01-01"
    assert embed.footer.text == "Page 1 of 1 · 1 with No Intro"
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

  test "the group option picks which members the first page lists", context do
    test_pid = self()
    task_supervisor = Module.concat(__MODULE__, "Tasks#{context.line}")
    store = Module.concat(__MODULE__, "Store#{context.line}")
    start_supervised!({Task.Supervisor, name: task_supervisor})
    start_supervised!({ReportStore, name: store})

    stub(DiscordMock, :create_interaction_response, fn _interaction, _response -> {:ok} end)

    stub(DiscordMock, :list_guild_members, fn @guild_id, _options ->
      {:ok, [guild_member(10, roles: [1]), guild_member(12)]}
    end)

    expect(DiscordMock, :edit_interaction_response, fn %Interaction{id: 900}, response ->
      send(test_pid, {:edited, response})
      {:ok, %Message{id: 901}}
    end)

    option = %Nostrum.Struct.ApplicationCommandInteractionDataOption{
      name: "group",
      value: "without_intro_roles"
    }

    interaction = %{
      interaction([@mod_role])
      | data: %ApplicationCommandInteractionData{name: "intro-report", options: [option]}
    }

    IntroReportCommand.handle(interaction, task_supervisor: task_supervisor, store: store)

    assert_receive {:edited, %{embeds: [embed]}}
    assert embed.description =~ "<@12>"
    assert embed.footer.text =~ "1 with neither Intro nor No Intro"
  end

  describe "page buttons" do
    setup context do
      store = Module.concat(__MODULE__, "Store#{context.line}")
      task_supervisor = Module.concat(__MODULE__, "Tasks#{context.line}")
      start_supervised!({ReportStore, name: store})
      start_supervised!({Task.Supervisor, name: task_supervisor})
      %{store: store, task_supervisor: task_supervisor}
    end

    defp click(custom_id) do
      %Interaction{
        id: 950,
        type: 3,
        guild_id: @guild_id,
        member: %Member{roles: [@mod_role]},
        data: %ApplicationCommandInteractionData{custom_id: custom_id}
      }
    end

    defp no_intro_members(count) do
      for n <- 1..count, do: guild_member(n, roles: [1], joined_at: 1_767_225_600 + n)
    end

    test "a click on a stored report shows the page it asks for", context do
      report = %MemberReport{
        member_count: 30,
        no_intro: no_intro_members(30),
        without_intro_roles: []
      }

      :ok = ReportStore.put(context.store, 900, report)

      expect(DiscordMock, :create_interaction_response, fn %Interaction{id: 950}, response ->
        assert %{type: 7, data: %{embeds: [embed], components: [_buttons]}} = response
        assert embed.footer.text == "Page 2 of 2 · 30 with No Intro"
        {:ok}
      end)

      expect(DiscordMock, :list_guild_members, 0, fn _guild_id, _options -> {:ok, []} end)

      IntroReportCommand.handle_button(click("intro-report:next:900:no_intro:2"),
        store: context.store,
        task_supervisor: context.task_supervisor
      )
    end

    test "a button id that doesn't parse is logged and left alone", context do
      expect(DiscordMock, :create_interaction_response, 0, fn _interaction, _response -> {:ok} end)

      log =
        capture_log(fn ->
          IntroReportCommand.handle_button(click("intro-report:next:900:everyone:2"),
            store: context.store,
            task_supervisor: context.task_supervisor
          )
        end)

      assert log =~ "intro-report:next:900:everyone:2"
    end

    test "a page change discord rejects is logged", context do
      report = %MemberReport{member_count: 0, no_intro: [], without_intro_roles: []}
      :ok = ReportStore.put(context.store, 900, report)

      stub(DiscordMock, :create_interaction_response, fn _interaction, _response ->
        {:error, %Nostrum.Error.ApiError{status_code: 404}}
      end)

      log =
        capture_log(fn ->
          IntroReportCommand.handle_button(click("intro-report:next:900:no_intro:2"),
            store: context.store,
            task_supervisor: context.task_supervisor
          )
        end)

      assert log =~ "couldn't update the intro report message"
    end

    test "no rebuild starts when the rebuilding message can't be shown", context do
      stub(DiscordMock, :create_interaction_response, fn _interaction, _response ->
        {:error, %Nostrum.Error.ApiError{status_code: 404}}
      end)

      expect(DiscordMock, :list_guild_members, 0, fn _guild_id, _options -> {:ok, []} end)

      log =
        capture_log(fn ->
          result =
            IntroReportCommand.handle_button(click("intro-report:next:900:no_intro:2"),
              store: context.store,
              task_supervisor: context.task_supervisor
            )

          assert result == :error
        end)

      assert log =~ "couldn't update the intro report message"
    end

    test "a click on a report that's gone says it's rebuilding, then shows the page",
         context do
      test_pid = self()

      # the buttons go, so the message can't be clicked again during the build
      expect(DiscordMock, :create_interaction_response, fn %Interaction{id: 950}, response ->
        assert response == %{
                 type: 7,
                 data: %{content: "Rebuilding the report…", embeds: [], components: []}
               }

        {:ok}
      end)

      stub(DiscordMock, :list_guild_members, fn @guild_id, _options ->
        {:ok, no_intro_members(30)}
      end)

      expect(DiscordMock, :edit_interaction_response, fn %Interaction{id: 950}, response ->
        send(test_pid, {:edited, response})
        {:ok, %Message{id: 901}}
      end)

      IntroReportCommand.handle_button(click("intro-report:next:900:no_intro:2"),
        store: context.store,
        task_supervisor: context.task_supervisor
      )

      assert_receive {:edited, %{embeds: [embed], components: [_buttons]}}
      assert embed.footer.text == "Page 2 of 2 · 30 with No Intro"
      assert {:ok, %MemberReport{member_count: 30}} = ReportStore.fetch(context.store, 900)
    end
  end
end
