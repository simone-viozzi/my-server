{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    claude-code.url = "github:sadjow/claude-code-nix";
    mcp-nixos.url = "github:utensils/mcp-nixos";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      claude-code,
      mcp-nixos,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ claude-code.overlays.default ];
        };

      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.claude-code
            pkgs.mcp-nixos
          ];
        };
      }
    );
}
