# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

NixOS flake-based configuration for a home server (x86_64-linux, AMD CPU, btrfs on NVMe). The system runs NixOS unstable (`nixpkgs-unstable`) with flakes and nix-command enabled.

## Build & Deploy

```bash
# Build the full system (validate changes compile)
nix build .#nixosConfigurations.simoserver.config.system.build.toplevel

# Rebuild and switch using nh (preferred)
nh os switch .

# Rebuild and switch using nixos-rebuild
sudo nixos-rebuild switch --flake .

# Build without switching (dry run with diff)
nh os build .

# Format nix files
nixfmt configuration.nix

# Enter dev shell (has claude-code and mcp-nixos)
nix develop
```

**Important:** New `.nix` files must be `git add`ed before `nix build` — flakes only see tracked files.

## Architecture

`flake.nix` defines `nixosConfigurations.simoserver` and a devShell (claude-code + mcp-nixos).

`configuration.nix` is a thin entry point that imports modules and sets host-specific config (hostname, user, stateVersion).

`modules/` contains focused modules:
- `base.nix` — boot, timezone, locale, nix settings, base packages, core services (SSH, direnv, nix-ld)
- `nh.nix` — nh rebuild helper + automatic GC (15 days, 4 generations)

**Target architecture** (from `_reference/`): The config should evolve toward:
- More modules: networking, users, docker, per-container modules under `modules/containers/`
- `home-manager` for user-level config (shell, git, tools)
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

## MCP Tools Available

- **mcp-nixos**: Query NixOS options, packages, and Home Manager options. Use for looking up correct option names and types.
- **tavily**: Web search and research. Use for finding NixOS configuration examples and documentation.

## Nix Style

- Use `nixfmt-rfc-style` formatting (the RFC 166 style)
- Follow the module pattern from `_reference/`: each concern in its own file under `modules/`
- New files must be `git add`ed before building (flake requirement)
