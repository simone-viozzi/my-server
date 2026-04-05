# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

NixOS flake-based configuration for a home server (x86_64-linux, AMD CPU, btrfs on NVMe). The system runs NixOS unstable (`nixpkgs-unstable`) with flakes and nix-command enabled.

## Build & Deploy

The system is **not flake-based yet**. The flake only provides a devShell (claude-code + mcp-nixos). The NixOS config is applied traditionally:

```bash
# Rebuild and switch (copies config to /etc/nixos/ first)
sudo nixos-rebuild switch

# Build without switching (dry run / test)
sudo nixos-rebuild build

# Test (switch but don't add to bootloader)
sudo nixos-rebuild test

# Format nix files (nixfmt-rfc-style is installed on the system)
nixfmt configuration.nix

# Enter dev shell (has claude-code and mcp-nixos)
nix develop
```

## Architecture

**Current state:** Early-stage traditional NixOS config — a single `configuration.nix` imports `hardware-configuration.nix`. Not yet flake-based for system builds.

**Target architecture** (from `_reference/`): The config should evolve toward a modular NixOS flake with:
- `flake.nix` defining `nixosConfigurations.<hostname>` (not just a devShell)
- `configuration.nix` as a thin import list
- `modules/` directory with focused modules (base, networking, users, docker, per-container)
- `home-manager` for user-level config
- `sops-nix` for secrets management

## Reference Configuration

The `_reference/` directory (gitignored) contains a working homelab NixOS config to use as a pattern guide. Key patterns:

**Container modules** (`_reference/containers/nixos/modules/containers/`):
- Use `virtualisation.oci-containers.containers.<name>` for Docker containers
- Pin images with `image:tag@sha256:digest`
- Add `systemd.services.docker-<name>` overlays for ordering (after/requires network + volume services)
- Use `environmentFiles` pointing to sops-nix decrypted paths for secrets

**Docker infrastructure** (`_reference/containers/nixos/modules/docker.nix`):
- Helper functions `mkNetworkService`, `mkVolumeService`, `mkBtrfsVolumeService` for systemd oneshots
- External Docker networks: `proxy`, `homepage-net`, `dockerproxy`
- Btrfs-backed volumes for persistent data, plain volumes for disposable data

**nh** is used for NixOS rebuilds and GC (keeps 15 days, 4 generations).

## MCP Tools Available

- **mcp-nixos**: Query NixOS options, packages, and Home Manager options. Use for looking up correct option names and types.
- **tavily**: Web search and research. Use for finding NixOS configuration examples and documentation.

## Nix Style

- Use `nixfmt-rfc-style` formatting (the RFC 166 style)
- Follow the module pattern from `_reference/`: each concern in its own file under `modules/`
