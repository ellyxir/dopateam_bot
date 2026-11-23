defmodule DopaTeam.IntroReportCommand do
  @moduledoc """
  The `/intro-report` slash command: shows staff the members who have not
  done an intro.
  """

  require Logger

  alias DopaTeam.{Consumer, IntroReportPage, MemberReport, ReportStore}
  alias Nostrum.Struct.Interaction

  # interaction response types and flags, see "Interaction Response Object"
  # in the Discord API docs
  @channel_message_with_source 4
  @deferred_channel_message_with_source 5
  @update_message 7
  @ephemeral 64

  @typedoc "options for `handle/2`"
  @type option() :: {:task_supervisor, atom()} | {:store, atom()}

  @doc """
  answers an `/intro-report` interaction

  Staff get a private "thinking" reply straight away; the report is built in
  a task and stored under the interaction's id, and the reply is then edited
  to show its counts.

  Options:
  * `task_supervisor:` - where the report is built, defaults to
    `DopaTeam.TaskSupervisor`
  * `store:` - the `DopaTeam.ReportStore` to keep the report in
  """
  @spec handle(Interaction.t(), [option()]) :: term()
  def handle(%Interaction{} = interaction, options \\ []) do
    {:ok, server_roles} = discord().get_guild_roles(interaction.guild_id)

    if Consumer.staff?(server_roles, interaction.member.roles) do
      {:ok} =
        discord().create_interaction_response(interaction, %{
          type: @deferred_channel_message_with_source,
          data: %{flags: @ephemeral}
        })

      task_supervisor = Keyword.get(options, :task_supervisor, DopaTeam.TaskSupervisor)
      store = Keyword.get(options, :store, ReportStore)

      Task.Supervisor.start_child(task_supervisor, fn ->
        build_and_reply(
          interaction,
          store,
          {interaction.id, group(interaction), months(interaction), 1}
        )
      end)
    else
      discord().create_interaction_response(interaction, %{
        type: @channel_message_with_source,
        data: %{content: "Sorry, /intro-report is for staff only.", flags: @ephemeral}
      })
    end
  end

  @doc """
  answers a click on a report page's previous or next button by showing the
  page it leads to, read from the stored report

  Takes the same options as `handle/2`.
  """
  @spec handle_button(Interaction.t(), [option()]) :: term()
  def handle_button(%Interaction{data: %{custom_id: custom_id}} = interaction, options \\ []) do
    case IntroReportPage.parse_button_id(custom_id) do
      {:ok, page} ->
        show_page(interaction, page, options)

      :error ->
        Logger.warning("ignored an intro report button with id #{inspect(custom_id)}")
    end
  end

  @spec show_page(
          Interaction.t(),
          IntroReportPage.page_ref(),
          [option()]
        ) :: term()
  defp show_page(interaction, {report_id, _group, _months, _page_number} = page, options) do
    store = Keyword.get(options, :store, ReportStore)

    case ReportStore.fetch(store, report_id) do
      {:ok, report} ->
        update_message(interaction, IntroReportPage.render(report, page, Date.utc_today()))

      # the report expired or was lost in a restart
      :error ->
        rebuild(interaction, store, page, options)
    end
  end

  # the buttons go while we build, so the message can't be clicked again;
  # two clicks that land together can still both build, and both store the
  # same report. if the message can't be updated, we don't build
  @spec rebuild(
          Interaction.t(),
          atom(),
          IntroReportPage.page_ref(),
          [option()]
        ) :: term()
  defp rebuild(interaction, store, page, options) do
    rebuilding = %{content: "Rebuilding the report…", embeds: [], components: []}

    with :ok <- update_message(interaction, rebuilding) do
      task_supervisor = Keyword.get(options, :task_supervisor, DopaTeam.TaskSupervisor)

      Task.Supervisor.start_child(task_supervisor, fn ->
        build_and_reply(interaction, store, page)
      end)
    end
  end

  @spec update_message(Interaction.t(), map()) :: :ok | :error
  defp update_message(interaction, data) do
    case discord().create_interaction_response(interaction, %{type: @update_message, data: data}) do
      {:ok} ->
        :ok

      error ->
        Logger.error("couldn't update the intro report message: #{inspect(error)}")
        :error
    end
  end

  # the group the command's option asks for, no intro by default
  @spec group(Interaction.t()) :: IntroReportPage.group()
  defp group(%Interaction{data: %{options: options}}) do
    case options |> Consumer.get_option("group", "no_intro") |> IntroReportPage.parse_group() do
      {:ok, group} -> group
      :error -> :no_intro
    end
  end

  defp group(%Interaction{}), do: :no_intro

  # how many months ago members must have joined by to be listed, 0 for all
  @spec months(Interaction.t()) :: IntroReportPage.months()
  defp months(%Interaction{data: %{options: options}}) do
    case Consumer.get_option(options, "joined_months_ago", 0) do
      months when is_integer(months) and months >= 0 -> months
      _other -> 0
    end
  end

  defp months(%Interaction{}), do: 0

  # whatever happens while building, the deferred reply gets edited, so staff
  # aren't left on "thinking"
  @spec build_and_reply(
          Interaction.t(),
          atom(),
          IntroReportPage.page_ref()
        ) :: :ok
  defp build_and_reply(interaction, store, page) do
    reply =
      try do
        build_and_store(interaction, store, page)
      catch
        kind, reason ->
          Logger.error("intro report crashed: " <> Exception.format(kind, reason, __STACKTRACE__))

          %{content: "Sorry, the report failed, see the bot's log."}
      end

    case discord().edit_interaction_response(interaction, reply) do
      {:ok, _message} ->
        :ok

      error ->
        Logger.error("couldn't edit the intro report reply: #{inspect(error)}")
    end
  end

  # the reply shows the report's counts and the page asked for
  @spec build_and_store(
          Interaction.t(),
          atom(),
          IntroReportPage.page_ref()
        ) :: map()
  defp build_and_store(interaction, store, {report_id, _group, _months, _page_number} = page) do
    case MemberReport.build(interaction.guild_id) do
      {:ok, report} ->
        :ok = ReportStore.put(store, report_id, report)

        report
        |> IntroReportPage.render(page, Date.utc_today())
        |> Map.put(:content, MemberReport.summary(report))

      error ->
        Logger.error("intro report failed: #{inspect(error)}")
        %{content: "Sorry, the report failed: #{inspect(error)}"}
    end
  end

  defp discord, do: Application.fetch_env!(:dopa_team, :discord)
end
