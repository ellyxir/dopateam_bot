defmodule DopaTeam.IntroReportPage do
  @moduledoc """
  Renders one page of a `DopaTeam.MemberReport` as a Discord embed.

  It only builds message data; it makes no Discord calls.
  """

  alias DopaTeam.Discord.GuildMember
  alias DopaTeam.MemberReport
  alias Nostrum.Struct.Embed

  @per_page 25
  @button_prefix "intro-report"

  # component types and button styles, see "Message Components" in the
  # Discord API docs
  @action_row 1
  @button 2
  @secondary 2

  @typedoc "which of the report's member lists a page shows"
  @type group() :: :no_intro | :without_intro_roles

  @typedoc "the id the report is stored under, the command's interaction id"
  @type report_id() :: non_neg_integer()

  @typedoc "a page number, counting from 1"
  @type page_number() :: pos_integer()

  @typedoc """
  how many months ago a member must have joined by to be listed; 0 lists
  every member
  """
  @type months() :: non_neg_integer()

  @typedoc "a page of a stored report: its id, which members, the months and the page"
  @type page_ref() :: {report_id(), group(), months(), page_number()}

  @typedoc "message data for a reply: its embed and its buttons"
  @type page() :: %{embeds: [Embed.t()], components: [map()]}

  @doc "renders a page of one of the report's member lists, as of `today`"
  @spec render(MemberReport.t(), page_ref(), Date.t()) :: page()
  def render(%MemberReport{} = report, {report_id, group, months, page_number}, today) do
    cutoff = cutoff(months, today)

    # nil sorts after every number, so members with no join date come last
    members =
      report
      |> Map.fetch!(group)
      |> joined_by(cutoff)
      |> Enum.sort_by(& &1.joined_at)

    page_count = max(1, ceil(length(members) / @per_page))
    # a rebuilt report can have fewer pages than the button expected
    page_number = min(page_number, page_count)

    first = (page_number - 1) * @per_page

    lines =
      members
      |> Enum.drop(first)
      |> Enum.take(@per_page)
      |> Enum.with_index(first + 1)
      |> Enum.map(fn {member, number} -> line(number, member) end)

    %{
      embeds: [
        %Embed{
          description: description(lines),
          footer: %Embed.Footer{
            text:
              "Page #{page_number} of #{page_count} · #{length(members)} #{label(group)}" <>
                cutoff_label(cutoff)
          }
        }
      ],
      components: [
        %{
          type: @action_row,
          components: [
            button(
              "Previous",
              "prev",
              {report_id, group, months, page_number - 1},
              page_number == 1
            ),
            button(
              "Next",
              "next",
              {report_id, group, months, page_number + 1},
              page_number == page_count
            )
          ]
        }
      ]
    }
  end

  @doc """
  reads the page a page button leads to from its custom id
  """
  @spec parse_button_id(String.t()) :: {:ok, page_ref()} | :error
  def parse_button_id(custom_id) do
    with [@button_prefix, direction, id, group, months, page] when direction in ["prev", "next"] <-
           String.split(custom_id, ":"),
         {report_id, ""} when report_id >= 0 <- Integer.parse(id),
         {:ok, group} <- parse_group(group),
         {months, ""} when months >= 0 <- Integer.parse(months),
         {page_number, ""} when page_number >= 1 <- Integer.parse(page) do
      {:ok, {report_id, group, months, page_number}}
    else
      _not_a_page_button -> :error
    end
  end

  # the direction keeps the two buttons' ids apart when they lead to the
  # same page, as discord wants each id in a message to be unique
  @spec button(String.t(), String.t(), {report_id(), group(), months(), integer()}, boolean()) ::
          map()
  defp button(label, direction, {report_id, group, months, page_number}, disabled?) do
    %{
      type: @button,
      style: @secondary,
      label: label,
      custom_id:
        Enum.join([@button_prefix, direction, report_id, group, months, page_number], ":"),
      disabled: disabled?
    }
  end

  @doc "reads a group from its name, as a button id or command option gives it"
  @spec parse_group(String.t()) :: {:ok, group()} | :error
  def parse_group("no_intro"), do: {:ok, :no_intro}
  def parse_group("without_intro_roles"), do: {:ok, :without_intro_roles}
  def parse_group(_other), do: :error

  # the latest join date a page lists, if it filters by months
  @spec cutoff(months(), Date.t()) :: Date.t() | nil
  defp cutoff(0, _today), do: nil
  defp cutoff(months, today), do: Date.shift(today, month: -months)

  # with a filter, a member with no join date is left out, as we can't tell
  # how long they have been here
  @spec joined_by([GuildMember.t()], Date.t() | nil) :: [GuildMember.t()]
  defp joined_by(members, nil), do: members

  defp joined_by(members, cutoff) do
    Enum.filter(members, fn member ->
      member.joined_at != nil and Date.compare(joined_on(member.joined_at), cutoff) != :gt
    end)
  end

  @spec joined_on(integer()) :: Date.t()
  defp joined_on(unix_seconds), do: unix_seconds |> DateTime.from_unix!() |> DateTime.to_date()

  # discord rejects an embed with an empty description
  @spec description([String.t()]) :: String.t()
  defp description([]), do: "Nobody."
  defp description(lines), do: Enum.join(lines, "\n")

  @spec cutoff_label(Date.t() | nil) :: String.t()
  defp cutoff_label(nil), do: ""
  defp cutoff_label(cutoff), do: ", joined on or before #{cutoff}"

  @spec label(group()) :: String.t()
  defp label(:no_intro), do: "with No Intro"
  defp label(:without_intro_roles), do: "with neither Intro nor No Intro"

  # the username shows even where discord can't turn the mention into a name
  @spec line(pos_integer(), GuildMember.t()) :: String.t()
  defp line(number, %GuildMember{} = member) do
    "#{number}. #{escape(member.username)} · <@#{member.user_id}> · joined #{joined(member.joined_at)}"
  end

  # usernames can hold underscores, which discord's markdown reads as
  # italics; letters, digits and dots are the only other characters allowed
  @spec escape(String.t()) :: String.t()
  defp escape(username), do: String.replace(username, "_", "\\_")

  # discord can leave out a member's join date
  @spec joined(GuildMember.joined_at()) :: String.t()
  defp joined(nil), do: "unknown"
  defp joined(unix_seconds), do: unix_seconds |> joined_on() |> Date.to_string()
end
