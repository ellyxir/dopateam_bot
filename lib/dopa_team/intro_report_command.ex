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
  @deferred_update_message 6
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
        build_and_reply(interaction, store, {interaction.id, group(interaction), 1})
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
    store = Keyword.get(options, :store, ReportStore)
    {:ok, {report_id, group, page_number} = page} = IntroReportPage.parse_button_id(custom_id)

    case ReportStore.fetch(store, report_id) do
      {:ok, report} ->
        discord().create_interaction_response(interaction, %{
          type: @update_message,
          data: IntroReportPage.render(report_id, report, group, page_number)
        })

      # the report expired or was lost in a restart, so we build it again
      :error ->
        {:ok} =
          discord().create_interaction_response(interaction, %{type: @deferred_update_message})

        task_supervisor = Keyword.get(options, :task_supervisor, DopaTeam.TaskSupervisor)

        Task.Supervisor.start_child(task_supervisor, fn ->
          build_and_reply(interaction, store, page)
        end)
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

  # whatever happens while building, the deferred reply gets edited, so staff
  # aren't left on "thinking"
  @spec build_and_reply(
          Interaction.t(),
          atom(),
          {IntroReportPage.report_id(), IntroReportPage.group(), IntroReportPage.page_number()}
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
          {IntroReportPage.report_id(), IntroReportPage.group(), IntroReportPage.page_number()}
        ) :: map()
  defp build_and_store(interaction, store, {report_id, group, page_number}) do
    case MemberReport.build(interaction.guild_id) do
      {:ok, report} ->
        :ok = ReportStore.put(store, report_id, report)

        report_id
        |> IntroReportPage.render(report, group, page_number)
        |> Map.put(:content, MemberReport.summary(report))

      error ->
        Logger.error("intro report failed: #{inspect(error)}")
        %{content: "Sorry, the report failed: #{inspect(error)}"}
    end
  end

  defp discord, do: Application.fetch_env!(:dopa_team, :discord)
end
