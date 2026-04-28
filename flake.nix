{
  description = "NixOS homelab server";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    claude-code.url = "github:sadjow/claude-code-nix";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      claude-code,
      home-manager,
      git-hooks,
      sops-nix,
      ...
    }:
    {
      # ── NixOS system configuration ──────────────────────────────────
      nixosConfigurations.simoserver = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          ./hardware-configuration.nix

          sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = {
                claudeCodePkg = claude-code.packages.x86_64-linux.default;
              };
              users.simone = import ./home/simone.nix;
            };
          }
        ];
      };
    }
    //
      # ── Dev shell (claude-code + mcp-nixos) ──────────────────────────
      flake-utils.lib.eachDefaultSystem (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [ claude-code.overlays.default ];
          };

          pre-commit-check = git-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              nixfmt.enable = true;
              deadnix = {
                enable = true;
                args = [ "--edit" ];
              };
              statix = {
                enable = true;
                entry = "${pkgs.statix}/bin/statix fix";
              };
              flake-checker.enable = true;
            };
          };

        in
        {
          checks = {
            inherit pre-commit-check;
          };

          devShells.default = pkgs.mkShell {
            inherit (pre-commit-check) shellHook;
            packages = [
              pkgs.claude-code
              pkgs.mcp-nixos
              pkgs.nixd
            ];
          };
        }
      );
}
