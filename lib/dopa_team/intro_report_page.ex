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

  @typedoc "message data for a reply: its embed and its buttons"
  @type page() :: %{embeds: [Embed.t()], components: [map()]}

  @doc "renders a page of one of the report's member lists"
  @spec render(report_id(), MemberReport.t(), group(), page_number()) :: page()
  def render(report_id, %MemberReport{} = report, group, page_number) do
    # nil sorts after every number, so members with no join date come last
    members = report |> Map.fetch!(group) |> Enum.sort_by(& &1.joined_at)
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
            text: "Page #{page_number} of #{page_count} · #{length(members)} #{label(group)}"
          }
        }
      ],
      components: [
        %{
          type: @action_row,
          components: [
            button("Previous", "prev", report_id, group, page_number - 1, page_number == 1),
            button("Next", "next", report_id, group, page_number + 1, page_number == page_count)
          ]
        }
      ]
    }
  end

  @doc """
  reads the report id, group and page number from a page button's custom id
  """
  @spec parse_button_id(String.t()) :: {:ok, {report_id(), group(), page_number()}} | :error
  def parse_button_id(custom_id) do
    with [@button_prefix, direction, id, group, page] when direction in ["prev", "next"] <-
           String.split(custom_id, ":"),
         {report_id, ""} when report_id >= 0 <- Integer.parse(id),
         {:ok, group} <- parse_group(group),
         {page_number, ""} when page_number >= 1 <- Integer.parse(page) do
      {:ok, {report_id, group, page_number}}
    else
      _not_a_page_button -> :error
    end
  end

  # the direction keeps the two buttons' ids apart when they lead to the
  # same page, as discord wants each id in a message to be unique
  @spec button(String.t(), String.t(), report_id(), group(), non_neg_integer(), boolean()) ::
          map()
  defp button(label, direction, report_id, group, page_number, disabled?) do
    %{
      type: @button,
      style: @secondary,
      label: label,
      custom_id: Enum.join([@button_prefix, direction, report_id, group, page_number], ":"),
      disabled: disabled?
    }
  end

  @doc "reads a group from its name, as a button id or command option gives it"
  @spec parse_group(String.t()) :: {:ok, group()} | :error
  def parse_group("no_intro"), do: {:ok, :no_intro}
  def parse_group("without_intro_roles"), do: {:ok, :without_intro_roles}
  def parse_group(_other), do: :error

  # discord rejects an embed with an empty description
  @spec description([String.t()]) :: String.t()
  defp description([]), do: "Nobody."
  defp description(lines), do: Enum.join(lines, "\n")

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
  defp joined(unix_seconds), do: unix_seconds |> DateTime.from_unix!() |> Date.to_string()
end
