defmodule DopaTeam.ConsumerTest do
  use ExUnit.Case, async: true

  alias DopaTeam.Consumer
  alias Nostrum.Struct.Guild.Role

  @server_roles [
    %Role{id: 1, name: "Admins"},
    %Role{id: 2, name: "MOD"},
    %Role{id: 3, name: "Helpers"},
    %Role{id: 4, name: "18+"}
  ]

  describe "staff?/2" do
    test "an author with the Admins role is staff" do
      assert Consumer.staff?(@server_roles, [4, 1])
    end

    test "an author with the MOD role is staff" do
      assert Consumer.staff?(@server_roles, [2])
    end

    test "an author with the Helpers role is staff" do
      assert Consumer.staff?(@server_roles, [3])
    end

    test "a server without a staff role does not crash the check" do
      server_roles = [%Role{id: 2, name: "MOD"}, %Role{id: 4, name: "18+"}]

      refute Consumer.staff?(server_roles, [4])
    end
  end

  describe "get_mentions/1" do
    test "returns the ids of the mentioned users in order" do
      content = "hi <@1176811717213306880>, can i dm you and <@964397371666604076>?"

      assert Consumer.get_mentions(content) == [
               1_176_811_717_213_306_880,
               964_397_371_666_604_076
             ]
    end

    test "ignores role and channel mentions" do
      assert Consumer.get_mentions("ping <@&1160011667606863892> in <#964397371666604079>") == []
    end
  end

  describe "has_mentions?/1" do
    test "is true when the message mentions a user" do
      assert Consumer.has_mentions?("dm me <@1176811717213306880>")
    end

    test "is false when the message mentions no one" do
      refute Consumer.has_mentions?("anyone want to chat?")
    end
  end

  describe "get_option/3" do
    alias Nostrum.Struct.ApplicationCommandInteractionDataOption, as: Option

    test "returns the value of the named option" do
      options = [%Option{name: "water_message", value: "stay hydrated"}]

      assert Consumer.get_option(options, "water_message") == "stay hydrated"
    end

    test "returns the default when no option has that name" do
      options = [%Option{name: "other", value: "x"}]

      assert Consumer.get_option(options, "water_message", "none") == "none"
    end

    test "returns the default when the command has no options" do
      assert Consumer.get_option(nil, "water_message", "none") == "none"
    end
  end
end
