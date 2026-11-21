defmodule DopaTeam.ConsumerIntroTest do
  use ExUnit.Case, async: true

  import Mox

  alias DopaTeam.Consumer
  alias DopaTeam.DiscordMock
  alias Nostrum.Struct.Guild.{Member, Role}
  alias Nostrum.Struct.{Message, User}

  @guild_id 1_160_011_667_204_231_300
  @intro_channel_id 1_160_011_668_500_250_734

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
end
