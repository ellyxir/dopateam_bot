defmodule DopaTeam.ConsumerIntroTest do
  use ExUnit.Case, async: true

  import Mox

  alias DopaTeam.Consumer
  alias DopaTeam.DiscordMock
  alias Nostrum.Struct.Guild.{Member, Role}
  alias Nostrum.Struct.{Message, User}

  @guild_id 1_160_011_667_204_231_300
  @intro_channel_id 1_160_011_668_500_250_734
  @general_log_channel_id 1_160_011_671_515_971_619

  @no_intro_role 1
  @intro_role 2
  @rules_role 3
  @adult_role 18
  @author_id 100

  setup :verify_on_exit!

  setup do
    stub(DiscordMock, :get_guild_roles, fn @guild_id ->
      {:ok,
       [
         %Role{id: @no_intro_role, name: "No Intro"},
         %Role{id: @intro_role, name: "Intro"},
         %Role{id: @rules_role, name: "Rules"},
         %Role{id: @adult_role, name: "18+"}
       ]}
    end)

    :ok
  end

  defp intro(author_roles, content) do
    message = %Message{
      id: 400,
      author: %User{id: @author_id, bot: nil},
      guild_id: @guild_id,
      channel_id: @intro_channel_id,
      member: %Member{roles: author_roles},
      content: content
    }

    Consumer.handle_event({:MESSAGE_CREATE, message, nil})
  end

  test "a No Intro member who posts an intro gets Intro and loses No Intro and Rules" do
    expect(DiscordMock, :modify_guild_member, fn @guild_id, @author_id, options ->
      assert Enum.sort(options[:roles]) == [@intro_role, @adult_role]
      {:ok, %Member{user_id: @author_id}}
    end)

    intro([@no_intro_role, @rules_role, @adult_role], "hi, i'm new here")
  end

  test "a one word message does not count as an intro" do
    expect(DiscordMock, :modify_guild_member, 0, fn _guild_id, _user_id, _options -> :ok end)

    intro([@no_intro_role, @rules_role], "hi")
  end

  test "a member without No Intro keeps their roles" do
    expect(DiscordMock, :modify_guild_member, 0, fn _guild_id, _user_id, _options -> :ok end)

    intro([@intro_role, @adult_role], "welcome to the server!")
  end

  test "an intro from a member with neither intro role is flagged in the general log" do
    expect(DiscordMock, :modify_guild_member, 0, fn _guild_id, _user_id, _options -> :ok end)

    expect(DiscordMock, :create_message, fn @general_log_channel_id, content ->
      assert content =~ "<@#{@author_id}>"
      assert content =~ "https://discord.com/channels/#{@guild_id}/#{@intro_channel_id}/400"
      {:ok, %Message{id: 401}}
    end)

    intro([@adult_role], "hi, i'm new here")
  end

  test "the flag mentions the Helpers role, so helpers see it" do
    stub(DiscordMock, :get_guild_roles, fn @guild_id ->
      {:ok,
       [
         %Role{id: @no_intro_role, name: "No Intro"},
         %Role{id: @intro_role, name: "Intro"},
         %Role{id: @rules_role, name: "Rules"},
         %Role{id: 7, name: "Helpers"}
       ]}
    end)

    expect(DiscordMock, :create_message, fn @general_log_channel_id, content ->
      assert content =~ "<@&7>"
      {:ok, %Message{id: 401}}
    end)

    intro([@adult_role], "hi, i'm new here")
  end

  test "an intro from a member with Access is not flagged" do
    stub(DiscordMock, :get_guild_roles, fn @guild_id ->
      {:ok,
       [
         %Role{id: @no_intro_role, name: "No Intro"},
         %Role{id: @intro_role, name: "Intro"},
         %Role{id: @rules_role, name: "Rules"},
         %Role{id: 5, name: "Access"}
       ]}
    end)

    expect(DiscordMock, :create_message, 0, fn _channel_id, _content -> :ok end)
    expect(DiscordMock, :modify_guild_member, 0, fn _guild_id, _user_id, _options -> :ok end)

    intro([5], "hi, i'm new here")
  end

  test "a one word message from a member with neither intro role is not flagged" do
    expect(DiscordMock, :create_message, 0, fn _channel_id, _content -> :ok end)

    intro([@adult_role], "hi")
  end

  test "a server without a Rules role still moves a No Intro member to Intro" do
    stub(DiscordMock, :get_guild_roles, fn @guild_id ->
      {:ok, [%Role{id: @no_intro_role, name: "No Intro"}, %Role{id: @intro_role, name: "Intro"}]}
    end)

    expect(DiscordMock, :modify_guild_member, fn @guild_id, @author_id, options ->
      assert options[:roles] == [@intro_role]
      {:ok, %Member{user_id: @author_id}}
    end)

    intro([@no_intro_role], "hi, i'm new here")
  end
end
