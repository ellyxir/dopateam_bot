# `nix develop` to start shell
# `nix flake update` to update all packages (inputs)
{
  description = "elixir/erlang dev flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
        f (import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        }));
    in {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            helix
            ripgrep
            glow
            mdcat
            beam29Packages.elixir_1_20
            beam29Packages.expert
            git
            gh
            delta
            tea
            marksman
          ];
        };
      });
    };
}
