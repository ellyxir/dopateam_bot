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
end
