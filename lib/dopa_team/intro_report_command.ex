defmodule DopaTeam.IntroReportCommand do
  @moduledoc """
  The `/intro-report` slash command: shows staff the members who have not
  done an intro.
  """

  require Logger

  alias DopaTeam.{Consumer, MemberReport, ReportStore}
  alias Nostrum.Struct.Interaction

  # interaction response types and flags, see "Interaction Response Object"
  # in the Discord API docs
  @channel_message_with_source 4
  @deferred_channel_message_with_source 5
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
        build_and_reply(interaction, store)
      end)
    else
      discord().create_interaction_response(interaction, %{
        type: @channel_message_with_source,
        data: %{content: "Sorry, /intro-report is for staff only.", flags: @ephemeral}
      })
    end
  end

  # whatever happens while building, the deferred reply gets edited, so staff
  # aren't left on "thinking"
  @spec build_and_reply(Interaction.t(), atom()) :: :ok
  defp build_and_reply(interaction, store) do
    content =
      try do
        build_and_store(interaction, store)
      catch
        kind, reason ->
          Logger.error("intro report crashed: " <> Exception.format(kind, reason, __STACKTRACE__))

          "Sorry, the report failed, see the bot's log."
      end

    case discord().edit_interaction_response(interaction, %{content: content}) do
      {:ok, _message} ->
        :ok

      error ->
        Logger.error("couldn't edit the intro report reply: #{inspect(error)}")
    end
  end

  @spec build_and_store(Interaction.t(), atom()) :: String.t()
  defp build_and_store(interaction, store) do
    case MemberReport.build(interaction.guild_id) do
      {:ok, report} ->
        :ok = ReportStore.put(store, interaction.id, report)
        MemberReport.summary(report)

      error ->
        Logger.error("intro report failed: #{inspect(error)}")
        "Sorry, the report failed: #{inspect(error)}"
    end
  end

  defp discord, do: Application.fetch_env!(:dopa_team, :discord)
end
