defmodule DopaTeam.IntroReportPageTest do
  use ExUnit.Case, async: true

  import DopaTeam.Factory

  alias DopaTeam.{IntroReportPage, MemberReport}

  # 2026-01-01 00:00:00 UTC
  @new_year 1_767_225_600
  @day 24 * 60 * 60

  # members who joined a day apart, listed newest first so the page has to
  # sort them
  defp members(count) do
    for n <- count..1//-1, do: guild_member(1000 + n, joined_at: @new_year + n * @day)
  end

  defp report(no_intro) do
    %MemberReport{member_count: 100, no_intro: no_intro, without_intro_roles: []}
  end

  test "the first page lists 25 members, oldest join first" do
    page = IntroReportPage.render(7, report(members(30)), :no_intro, 1)

    [embed] = page.embeds
    lines = String.split(embed.description, "\n")

    assert length(lines) == 25
    assert hd(lines) == "1. user1001 · <@1001> · joined 2026-01-02"
    assert List.last(lines) == "25. user1025 · <@1025> · joined 2026-01-26"
    assert embed.footer.text == "Page 1 of 2 · 30 with No Intro"
  end

  test "numbering carries on from the page before" do
    page = IntroReportPage.render(7, report(members(30)), :no_intro, 2)

    [embed] = page.embeds

    assert hd(String.split(embed.description, "\n")) ==
             "26. user1026 · <@1026> · joined 2026-01-27"
  end

  test "underscores in a username show as written, not as italics" do
    member = guild_member(5, username: "_some_name_", joined_at: @new_year)

    page = IntroReportPage.render(7, report([member]), :no_intro, 1)

    [embed] = page.embeds
    assert embed.description == "1. \\_some\\_name\\_ · <@5> · joined 2026-01-01"
  end

  test "a member with no join date is listed last, as joined unknown" do
    page = IntroReportPage.render(7, report([guild_member(999) | members(2)]), :no_intro, 1)

    [embed] = page.embeds

    assert String.split(embed.description, "\n") == [
             "1. user1001 · <@1001> · joined 2026-01-02",
             "2. user1002 · <@1002> · joined 2026-01-03",
             "3. user999 · <@999> · joined unknown"
           ]
  end

  test "the members with neither role are labelled as such" do
    report = %MemberReport{member_count: 100, no_intro: [], without_intro_roles: members(3)}

    page = IntroReportPage.render(7, report, :without_intro_roles, 1)

    [embed] = page.embeds
    assert embed.footer.text == "Page 1 of 1 · 3 with neither Intro nor No Intro"
  end

  test "previous and next buttons lead to the neighbouring pages" do
    page = IntroReportPage.render(7, report(members(60)), :no_intro, 2)

    assert [%{type: 1, components: [previous, next]}] = page.components
    assert %{type: 2, label: "Previous", disabled: false} = previous
    assert %{type: 2, label: "Next", disabled: false} = next
    assert IntroReportPage.parse_button_id(previous.custom_id) == {:ok, {7, :no_intro, 1}}
    assert IntroReportPage.parse_button_id(next.custom_id) == {:ok, {7, :no_intro, 3}}
  end

  test "previous is off on the first page and next is off on the last" do
    first = IntroReportPage.render(7, report(members(30)), :no_intro, 1)
    last = IntroReportPage.render(7, report(members(30)), :no_intro, 2)

    assert [%{components: [%{disabled: true}, %{disabled: false}]}] = first.components
    assert [%{components: [%{disabled: false}, %{disabled: true}]}] = last.components
  end

  test "an empty list says there is nobody, on a single page" do
    page = IntroReportPage.render(7, report([]), :no_intro, 1)

    [embed] = page.embeds
    assert embed.description == "Nobody."
    assert embed.footer.text == "Page 1 of 1 · 0 with No Intro"
    assert [%{components: [%{disabled: true}, %{disabled: true}]}] = page.components
  end

  test "a page past the end shows the last page" do
    page = IntroReportPage.render(7, report(members(30)), :no_intro, 5)

    [embed] = page.embeds
    assert embed.footer.text == "Page 2 of 2 · 30 with No Intro"
    assert length(String.split(embed.description, "\n")) == 5
  end

  test "ids that aren't page buttons are turned away" do
    for id <- [
          "something-else",
          "intro-report:prev:7:no_intro",
          "intro-report:up:7:no_intro:2",
          "intro-report:next:x:no_intro:2",
          "intro-report:next:7:everyone:2",
          "intro-report:next:7:no_intro:0"
        ] do
      assert IntroReportPage.parse_button_id(id) == :error, id
    end
  end
end
