defmodule DopaTeam.MemberReportTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Mox

  alias DopaTeam.DiscordMock
  alias DopaTeam.MemberReport
  alias Nostrum.Struct.Guild.{Member, Role}
  alias Nostrum.Struct.User

  @guild_id 1_176_811_717_213_306_880

  @no_intro_role 1
  @intro_role 2
  @adult_role 18

  setup :verify_on_exit!

  setup do
    stub(DiscordMock, :get_guild_roles, fn @guild_id ->
      {:ok,
       [
         %Role{id: @no_intro_role, name: "No Intro"},
         %Role{id: @intro_role, name: "Intro"},
         %Role{id: @adult_role, name: "18+"}
       ]}
    end)

    stub(DiscordMock, :get_user, fn user_id -> {:ok, %User{id: user_id, bot: nil}} end)

    :ok
  end

  defp member(user_id, roles), do: %Member{user_id: user_id, roles: roles}

  test "lists the members who have No Intro" do
    stub(DiscordMock, :list_guild_members, fn @guild_id, _options ->
      {:ok,
       [
         member(10, [@no_intro_role]),
         member(11, [@intro_role, @adult_role]),
         member(12, [@no_intro_role, @adult_role])
       ]}
    end)

    assert {:ok, report} = MemberReport.build(@guild_id)
    assert Enum.map(report.no_intro, & &1.user_id) == [10, 12]
  end

  test "lists the members who have neither Intro nor No Intro" do
    stub(DiscordMock, :list_guild_members, fn @guild_id, _options ->
      {:ok,
       [
         member(10, [@no_intro_role]),
         member(11, [@intro_role, @adult_role]),
         member(12, [@adult_role]),
         member(13, [])
       ]}
    end)

    assert {:ok, report} = MemberReport.build(@guild_id)
    assert Enum.map(report.without_intro_roles, & &1.user_id) == [12, 13]
  end

  test "leaves bots out, looking up only members with neither role" do
    stub(DiscordMock, :list_guild_members, fn @guild_id, _options ->
      {:ok,
       [
         member(10, [@no_intro_role]),
         member(11, [@intro_role]),
         member(12, []),
         member(13, [@adult_role])
       ]}
    end)

    expect(DiscordMock, :get_user, 2, fn
      12 -> {:ok, %User{id: 12, bot: true}}
      13 -> {:ok, %User{id: 13, bot: nil}}
    end)

    assert {:ok, report} = MemberReport.build(@guild_id)
    assert Enum.map(report.without_intro_roles, & &1.user_id) == [13]
  end

  test "leaves out a member whose bot lookup fails, keeping the rest" do
    stub(DiscordMock, :list_guild_members, fn @guild_id, _options ->
      {:ok, [member(12, []), member(13, [@adult_role])]}
    end)

    stub(DiscordMock, :get_user, fn
      12 -> {:error, %Nostrum.Error.ApiError{status_code: 500}}
      13 -> {:ok, %User{id: 13, bot: nil}}
    end)

    {result, log} = with_log(fn -> MemberReport.build(@guild_id) end)

    assert {:ok, report} = result
    assert Enum.map(report.without_intro_roles, & &1.user_id) == [13]
    assert log =~ "12"
  end

  test "follows the pages until a page comes back short" do
    expect(DiscordMock, :list_guild_members, fn @guild_id, options ->
      assert options == [limit: 2, after: 0]
      {:ok, [member(10, [@no_intro_role]), member(11, [@intro_role])]}
    end)

    expect(DiscordMock, :list_guild_members, fn @guild_id, options ->
      assert options == [limit: 2, after: 11]
      {:ok, [member(12, [@no_intro_role]), member(13, [@intro_role])]}
    end)

    expect(DiscordMock, :list_guild_members, fn @guild_id, options ->
      assert options == [limit: 2, after: 13]
      {:ok, [member(14, [@no_intro_role])]}
    end)

    assert {:ok, report} = MemberReport.build(@guild_id, page_size: 2)
    assert Enum.map(report.no_intro, & &1.user_id) == [10, 12, 14]
  end

  test "says which role is missing when the server has no Intro role" do
    stub(DiscordMock, :get_guild_roles, fn @guild_id ->
      {:ok, [%Role{id: @no_intro_role, name: "No Intro"}]}
    end)

    stub(DiscordMock, :list_guild_members, fn @guild_id, _options -> {:ok, []} end)

    assert MemberReport.build(@guild_id) == {:error, {:missing_role, "Intro"}}
  end
end
