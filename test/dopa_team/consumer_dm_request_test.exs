defmodule DopaTeam.ConsumerDmRequestTest do
  # the warning is deleted from a process the consumer spawns, so the mock
  # has to be global, which rules out async
  use ExUnit.Case, async: false

  import Mox

  alias DopaTeam.Consumer
  alias DopaTeam.DiscordMock
  alias Nostrum.Struct.Guild.{Member, Role}
  alias Nostrum.Struct.{Message, User}

  @guild_id 1_160_011_667_204_231_300
  @dm_channel_id 1_160_011_669_003_587_584
  @logging_channel_id 1_160_606_680_741_056_652

  @adult_role 18
  @minor_role 13
  @older_minor_role 16
  @author_id 100
  @minor_id 200
  @closed_dm_id 300

  @member_roles %{@minor_id => [@minor_role], @closed_dm_id => [@adult_role, 99]}

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    test_pid = self()

    stub(DiscordMock, :get_guild_roles, fn @guild_id ->
      {:ok,
       [
         %Role{id: 1, name: "Admins"},
         %Role{id: 2, name: "MOD"},
         %Role{id: 3, name: "Helpers"},
         %Role{id: @adult_role, name: "18+"},
         %Role{id: 30, name: "30+"},
         %Role{id: @minor_role, name: "13-15"},
         %Role{id: @older_minor_role, name: "16-17"},
         %Role{id: 99, name: "Closed DM"}
       ]}
    end)

    stub(DiscordMock, :get_guild_member, fn @guild_id, user_id ->
      {:ok, %Member{user_id: user_id, roles: Map.fetch!(@member_roles, user_id)}}
    end)

    stub(DiscordMock, :get_user, fn user_id ->
      {:ok, %User{id: user_id, bot: nil}}
    end)

    stub(DiscordMock, :create_message, fn channel_id, options ->
      send(test_pid, {:created, channel_id, options})
      {:ok, %Message{id: 500, channel_id: channel_id}}
    end)

    stub(DiscordMock, :delete_message, fn %Message{id: id} ->
      send(test_pid, {:deleted, id})
      {:ok}
    end)

    stub(DiscordMock, :delete_message, fn channel_id, message_id ->
      send(test_pid, {:deleted, channel_id, message_id})
      {:ok}
    end)

    :ok
  end

  defp dm_request(author_roles, content) do
    message = %Message{
      id: 400,
      author: %User{id: @author_id, bot: nil},
      guild_id: @guild_id,
      channel_id: @dm_channel_id,
      member: %Member{roles: author_roles},
      content: content
    }

    Consumer.handle_event({:MESSAGE_CREATE, message, nil})
  end

  test "an adult asking to dm a minor is warned, removed and logged" do
    dm_request([@adult_role], "can i dm you <@#{@minor_id}>?")

    assert_received {:created, @dm_channel_id, warning}
    assert warning[:content] =~ "<@#{@author_id}>"
    assert_received {:deleted, 400}
    assert_received {:created, @logging_channel_id, log}
    assert log =~ "<@#{@minor_id}>"
    assert_receive {:deleted, @dm_channel_id, 500}
  end

  test "staff can mention a minor" do
    dm_request([@adult_role, 2], "<@#{@minor_id}> please read the rules")

    refute_received {:created, _channel_id, _options}
    refute_received {:deleted, _message_id}
  end

  test "a minor may ask to dm a minor" do
    dm_request([@minor_role], "<@#{@minor_id}> can i dm you?")

    refute_received {:created, _channel_id, _options}
    refute_received {:deleted, _message_id}
  end

  test "a 16-17 member may ask to dm a minor" do
    dm_request([@older_minor_role], "<@#{@minor_id}> can i dm you?")

    refute_received {:created, _channel_id, _options}
    refute_received {:deleted, _message_id}
  end

  test "a member with no age role may not ask to dm a minor" do
    dm_request([], "<@#{@minor_id}> can i dm you?")

    assert_received {:created, @dm_channel_id, _warning}
    assert_received {:deleted, 400}
    assert_receive {:deleted, @dm_channel_id, 500}
  end

  test "nobody may ask to dm a member with the Closed DM role" do
    dm_request([], "<@#{@closed_dm_id}> can we chat in dms?")

    assert_received {:deleted, 400}
    # the warning is deleted from another process; wait for it so it can't
    # call the mock after this test ends
    assert_receive {:deleted, @dm_channel_id, 500}
  end
end
