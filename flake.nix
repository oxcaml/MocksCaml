{
  description = "MocksCaml - a mock repo for exercising OxCaml's GitHub CI";

  # Pinned by full commit hash (same rev as oxcaml's flake.lock) so that
  # resolution is deterministic even though no flake.lock is committed:
  # nobody here can run nix locally to generate one, and CI resolves the
  # pinned input on the fly.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/ca534a76c4afb2bdc07b681dbc11b453bab21af8";
  };

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      platforms = {
        "x86_64-linux" = "ubuntu-latest";
        "aarch64-linux" = "ubuntu-24.04-arm";
        "aarch64-darwin" = "macos-latest";
      };
      forAllSystems = lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          mockscaml = pkgs.callPackage ./default.nix { src = self; };
        in
        {
          inherit mockscaml;
          mockscaml-dev = mockscaml.override { dev = true; };
          default = mockscaml;
        }
      );

      checks = forAllSystems (
        system:
        lib.attrsets.filterAttrs (key: drv: !(drv.meta.broken or false)) {
          inherit (self.packages.${system})
            mockscaml
            mockscaml-dev
            ;
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

      # Hand-rolled equivalent of nix-github-actions.lib.mkGithubMatrix (which
      # oxcaml uses): matrix.include entries carry { attr, name, os, system },
      # where attr is a flake attr path that `nix build ".#$ATTR"` can build
      # directly.
      githubActions = {
        checks = self.checks;
        matrix.include = lib.concatMap (
          system:
          map (name: {
            inherit name system;
            os = platforms.${system};
            attr = "githubActions.checks.${system}.${name}";
          }) (builtins.attrNames self.checks.${system})
        ) systems;
      };
    };
}
