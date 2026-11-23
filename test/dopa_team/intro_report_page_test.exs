defmodule DopaTeam.IntroReportPageTest do
  use ExUnit.Case, async: true

  import DopaTeam.Factory

  alias DopaTeam.{IntroReportPage, MemberReport}

  # 2026-01-01 00:00:00 UTC
  @new_year 1_767_225_600
  @day 24 * 60 * 60
  @today ~D[2026-06-01]

  # members who joined a day apart, listed newest first so the page has to
  # sort them
  defp members(count) do
    for n <- count..1//-1, do: guild_member(1000 + n, joined_at: @new_year + n * @day)
  end

  defp report(no_intro) do
    %MemberReport{member_count: 100, no_intro: no_intro, without_intro_roles: []}
  end

  test "the first page lists 25 members, oldest join first" do
    page = IntroReportPage.render(report(members(30)), {7, :no_intro, 0, 1}, @today)

    [embed] = page.embeds
    lines = String.split(embed.description, "\n")

    assert length(lines) == 25
    assert hd(lines) == "1. user1001 · <@1001> · joined 2026-01-02"
    assert List.last(lines) == "25. user1025 · <@1025> · joined 2026-01-26"
    assert embed.footer.text == "Page 1 of 2 · 30 with No Intro"
  end

  test "numbering carries on from the page before" do
    page = IntroReportPage.render(report(members(30)), {7, :no_intro, 0, 2}, @today)

    [embed] = page.embeds

    assert hd(String.split(embed.description, "\n")) ==
             "26. user1026 · <@1026> · joined 2026-01-27"
  end

  test "underscores in a username show as written, not as italics" do
    member = guild_member(5, username: "_some_name_", joined_at: @new_year)

    page = IntroReportPage.render(report([member]), {7, :no_intro, 0, 1}, @today)

    [embed] = page.embeds
    assert embed.description == "1. \\_some\\_name\\_ · <@5> · joined 2026-01-01"
  end

  test "a months filter lists only members who joined by that many months ago" do
    report = report([guild_member(999) | members(5)])

    page = IntroReportPage.render(report, {7, :no_intro, 1, 1}, ~D[2026-02-03])

    [embed] = page.embeds

    assert String.split(embed.description, "\n") == [
             "1. user1001 · <@1001> · joined 2026-01-02",
             "2. user1002 · <@1002> · joined 2026-01-03"
           ]
  end

  test "a filtered page's footer gives the latest join date it lists" do
    page = IntroReportPage.render(report(members(5)), {7, :no_intro, 1, 1}, ~D[2026-02-03])

    [embed] = page.embeds
    assert embed.footer.text == "Page 1 of 1 · 2 with No Intro, joined on or before 2026-01-03"
  end

  test "a filtered page's buttons keep the filter" do
    page = IntroReportPage.render(report(members(60)), {7, :no_intro, 0, 1}, @today)
    filtered = IntroReportPage.render(report(members(60)), {7, :no_intro, 1, 1}, ~D[2026-04-01])

    assert [%{components: [_previous, next]}] = page.components
    assert [%{components: [_filtered_previous, filtered_next]}] = filtered.components
    assert IntroReportPage.parse_button_id(next.custom_id) == {:ok, {7, :no_intro, 0, 2}}
    assert IntroReportPage.parse_button_id(filtered_next.custom_id) == {:ok, {7, :no_intro, 1, 2}}
  end

  test "a member with no join date is listed last, as joined unknown" do
    page =
      IntroReportPage.render(
        report([guild_member(999) | members(2)]),
        {7, :no_intro, 0, 1},
        @today
      )

    [embed] = page.embeds

    assert String.split(embed.description, "\n") == [
             "1. user1001 · <@1001> · joined 2026-01-02",
             "2. user1002 · <@1002> · joined 2026-01-03",
             "3. user999 · <@999> · joined unknown"
           ]
  end

  test "the members with neither role are labelled as such" do
    report = %MemberReport{member_count: 100, no_intro: [], without_intro_roles: members(3)}

    page = IntroReportPage.render(report, {7, :without_intro_roles, 0, 1}, @today)

    [embed] = page.embeds
    assert embed.footer.text == "Page 1 of 1 · 3 with neither Intro nor No Intro"
  end

  test "previous and next buttons lead to the neighbouring pages" do
    page = IntroReportPage.render(report(members(60)), {7, :no_intro, 0, 2}, @today)

    assert [%{type: 1, components: [previous, next]}] = page.components
    assert %{type: 2, label: "Previous", disabled: false} = previous
    assert %{type: 2, label: "Next", disabled: false} = next
    assert IntroReportPage.parse_button_id(previous.custom_id) == {:ok, {7, :no_intro, 0, 1}}
    assert IntroReportPage.parse_button_id(next.custom_id) == {:ok, {7, :no_intro, 0, 3}}
  end

  test "previous is off on the first page and next is off on the last" do
    first = IntroReportPage.render(report(members(30)), {7, :no_intro, 0, 1}, @today)
    last = IntroReportPage.render(report(members(30)), {7, :no_intro, 0, 2}, @today)

    assert [%{components: [%{disabled: true}, %{disabled: false}]}] = first.components
    assert [%{components: [%{disabled: false}, %{disabled: true}]}] = last.components
  end

  test "an empty list says there is nobody, on a single page" do
    page = IntroReportPage.render(report([]), {7, :no_intro, 0, 1}, @today)

    [embed] = page.embeds
    assert embed.description == "Nobody."
    assert embed.footer.text == "Page 1 of 1 · 0 with No Intro"
    assert [%{components: [%{disabled: true}, %{disabled: true}]}] = page.components
  end

  test "a page past the end shows the last page" do
    page = IntroReportPage.render(report(members(30)), {7, :no_intro, 0, 5}, @today)

    [embed] = page.embeds
    assert embed.footer.text == "Page 2 of 2 · 30 with No Intro"
    assert length(String.split(embed.description, "\n")) == 5
  end

  test "ids that aren't page buttons are turned away" do
    for id <- [
          "something-else",
          "intro-report:prev:7:no_intro:0",
          "intro-report:up:7:no_intro:0:2",
          "intro-report:next:x:no_intro:0:2",
          "intro-report:next:7:everyone:0:2",
          "intro-report:next:7:no_intro:-1:2",
          "intro-report:next:7:no_intro:0:0"
        ] do
      assert IntroReportPage.parse_button_id(id) == :error, id
    end
  end
end
