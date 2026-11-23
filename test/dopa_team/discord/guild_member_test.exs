defmodule DopaTeam.Discord.GuildMemberTest do
  use ExUnit.Case, async: true

  alias DopaTeam.Discord.GuildMember

  test "reads a member from discord's json" do
    json = %{
      "user" => %{"id" => "700866619030765680", "username" => "outdatedjokes", "bot" => true},
      "roles" => ["1160011667204231301", "1160011667204231302"],
      "joined_at" => "2025-08-19T12:34:56.789000+00:00",
      "nick" => "Jokes"
    }

    assert GuildMember.from_json(json) == %GuildMember{
             user_id: 700_866_619_030_765_680,
             username: "outdatedjokes",
             roles: [1_160_011_667_204_231_301, 1_160_011_667_204_231_302],
             joined_at: ~U[2025-08-19 12:34:56Z] |> DateTime.to_unix(),
             bot?: true
           }
  end

  test "a user discord doesn't mark as a bot is not one" do
    json = %{"user" => %{"id" => "1", "username" => "someone"}, "roles" => [], "joined_at" => nil}

    assert %GuildMember{bot?: false} = GuildMember.from_json(json)
  end

  test "a member discord gives no join date for has none" do
    json = %{"user" => %{"id" => "1", "username" => "someone"}, "roles" => [], "joined_at" => nil}

    assert %GuildMember{joined_at: nil} = GuildMember.from_json(json)
  end
end
