# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project Overview

This is a multi-host NixOS flake configuration for home servers, workstations,
and WSL. The entire system -- services, networking, users, secrets, disk
layout, and Home Manager profiles -- is declared in Nix. There is no Docker
and no imperative setup scripts. Changes go through pull requests with CI
validation, and each host rebuilds from the flake declaratively.

Some hosts use an **impermanent root** (tmpfs) with persisted state under
`/persist`, while others use a conventional persistent root. Check the host
family defaults before assuming impermanence is enabled.

Declarative users are the default across the repo. `users.mutableUsers = true`
should remain the exception; `hosts/wsl/wanzl` is currently the only host that
uses it because it intentionally avoids secrets.

## Agent Restrictions

**NEVER run NixOS build/switch commands.** These are denied:
- `nh os switch`, `nh os build`, `nixos-rebuild` -- the user will build manually

**Allowed tooling:** `nix fmt`, `nix flake check`, `nix flake show`,
`nix eval` are permitted for formatting and validation.

**Formatting rule:** After making any repository changes, agents MUST run
`nix fmt` from the repository root before finishing.

**Git permissions:**
- **Allow**: status, diff, log, show, blame, grep, reflog, add, restore, rm, mv, fetch
- **Ask**: commit, checkout, switch, branch, pull, remote, revert
- **Deny**: push, merge, rebase, cherry-pick, reset, filter-repo, gc, prune

**Secrets**: Never commit unencrypted secrets. `sops` commands require confirmation.

## Repository Layout

```
flake.nix                 Entry point. Defines inputs (nixpkgs, home-manager,
                           stylix, sops-nix, disko, impermanence, nvf,
                           git-hooks) and
                           all NixOS host configurations.
.envrc                    Direnv config -- activates devShell and installs
                           pre-commit hooks automatically.
.github/workflows/ci.yml  GitHub Actions CI -- runs on every PR to main.
SERVER_SETUP.md           Installation guide for server hosts.
WORKSTATION_SETUP.md      Installation guide for workstation hosts.

hosts/servers/            Server host family.
  common.nix              Shared server defaults.
  example/                Example server host.
  mu/                     Current home server.

hosts/workstations/       Desktop/laptop host family.
  common.nix              Shared workstation defaults.
  example/                Example workstation host.
  desktop/                Desktop host.
  laptop/                 Laptop host.

hosts/wsl/                WSL host family.
  common.nix              Shared WSL defaults.
  example/                Example WSL host.
  wanzl/                  Current WSL host.

home/common.nix           Repo-wide Home Manager policy shared by all users.
home/<username>/          Per-user Home Manager configuration.
  base.nix                Identity, locale, and per-user shared config.
  headless.nix            CLI/TUI profile for servers, WSL, or remote hosts.
  workstation.nix         GUI/desktop profile layered on top of headless.
home/example/             Example user for reference.

modules/nixos/            NixOS module tree.
  host/                   Host management and persistence modules.
  services/               Homelab and always-on service modules.
  workstation/            Desktop/laptop system feature modules.
  example.nix             Example NixOS module for reference.

modules/home-manager/     User environment modules.
  cli/                    Command-line tools (zsh, tmux, starship, etc.).
  tui/                    Terminal UI tools (nvf, opencode, yazi, etc.).
  gui/                    Graphical applications (kitty, mpv, librewolf, etc.).
  desktop/                Desktop/session configuration (Hyprland, Waybar, etc.).
  example.nix             Example Home Manager module for reference.

secrets/hosts/<hostname>.yaml  Encrypted host secrets (sops + age).
secrets/users/<username>.yaml  Encrypted user secrets (sops-menu passwords).
secrets/hosts/example.yaml     Example host secrets (unencrypted reference).
secrets/users/example.yaml     Example user secrets (unencrypted reference).
.sops.yaml                     sops encryption key configuration.
```

## Validation

### Pre-commit hooks

Pre-commit hooks are installed automatically via `direnv` (or `nix develop`).
They run on every commit:
- **nixfmt-rfc-style** -- formats staged `.nix` files
- **check-merge-conflicts** -- catches leftover conflict markers
- **detect-private-keys** -- prevents committing private keys

### CI (GitHub Actions)

Every PR to `main` runs these checks:
1. `nix fmt -- --check` -- formatting gate
2. `nix flake check` -- schema validation
3. `nix eval` for **every** host in `nixosConfigurations` -- deep evaluation

CI evaluates all hosts dynamically, so adding a new host to `flake.nix`
automatically includes it in CI.

### Local validation

```sh
# Format all Nix files
nix fmt

# Inspect flake outputs
nix flake show

# Quick sanity check -- verifies flake schema and output types
nix flake check

# Deep evaluation of a specific host
nix eval .#nixosConfigurations.<hostname>.config.system.build.toplevel --apply 'x: "ok"'
```

### Deployment

After a PR is merged to `main`, each server's auto-upgrade timer picks up
changes (typically at 04:00). For human operators who need immediate
deployment, SSH in and run:

```sh
nixos-rebuild switch --flake github:<org>/<repo>
```

## Impermanence

Only hosts that enable `host.impermanence.enable` use a tmpfs root that is
wiped on reboot. Their surviving paths are declared in
`modules/nixos/host/impermanence.nix` and bind-mounted from `/persist`.

**Rule: when adding a service that stores state to an impermanent host, you
must persist it.** Add the path to `modules/nixos/host/impermanence.nix` or
the state will be lost on reboot.

## Module Conventions

### NixOS modules

The repo uses three NixOS namespaces:

- **Host** (`modules/nixos/host/`): host lifecycle and machine management.
- **Services** (`modules/nixos/services/`): homelab services under `homelab.*`.
- **Workstation** (`modules/nixos/workstation/`): desktop/laptop system
  features under `workstation.*`.

Every NixOS module follows the same pattern:

1. **Option declaration** under `host.<name>.enable`, `homelab.<name>.enable`,
   or `workstation.<name>.enable` using `lib.mkEnableOption`.
2. **Conditional config** wrapped in `lib.mkIf cfg.enable`.
3. **Web UI proxying** -- browser-facing homelab services bind to localhost and
   register a `services.caddy.virtualHosts."<name>.${config.homelab.domain}"`
   entry. The shared `caddy.nix` module enables Caddy automatically when at
   least one virtualHost exists. Non-HTTP protocols such as DNS are exposed on
   their native ports instead of going through Caddy.

See `modules/nixos/example.nix` for the full template.

### Home Manager modules

Home Manager modules are split into `cli/`, `tui/`, `gui/`, and `desktop/`
subdirectories:

- **CLI** (`modules/home-manager/cli/`): Command-line tools -- shells, prompts,
  aliases, simple utilities.
- **TUI** (`modules/home-manager/tui/`): Terminal UI applications -- editors,
  file managers, AI assistants.
- **GUI** (`modules/home-manager/gui/`): Graphical applications -- terminal
  emulators, browsers, media tools, launchers.
- **Desktop** (`modules/home-manager/desktop/`): Desktop session setup -- window
  managers, bars, autostart, desktop-specific behavior.

Each module follows the pattern:
1. **Option declaration** under `user.cli.<tool>.enable`,
   `user.tui.<tool>.enable`, `user.gui.<tool>.enable`, or
   `user.desktop.<tool>.enable`.
2. **Conditional config** wrapped in `lib.mkIf cfg.enable`.

### Stylix on headless vs workstation profiles

`home/common.nix` owns the repo-wide Home Manager policy for Stylix targets
that emit `dconf.settings`. It gates the current set --
`stylix.targets.gtk`, `stylix.targets.gnome`, `stylix.targets.eog`, and
`stylix.targets."gnome-text-editor"` -- from `user.profile.kind`.

Host-family common modules should set `user.profile.kind` through
`home-manager.sharedModules`: `hosts/workstations/common.nix` uses
`"workstation"`, while `hosts/servers/common.nix` and `hosts/wsl/common.nix`
use `"headless"`. The fallback default in `home/common.nix` remains
`"headless"`, which keeps standalone Home Manager profiles safe unless they
explicitly override it. Browser-facing homelab web UIs do not use the server's
local `dconf` state; they are themed by the client browser.

If you add or re-enable Home Manager GUI theming that writes `dconf.settings`,
make sure it only applies to graphical hosts or that the host also provides
`programs.dconf.enable` on the NixOS side.

See `modules/home-manager/example.nix`.

## Secrets

This repo intentionally uses two secret flows:

- **Host secrets** live in `secrets/hosts/<hostname>.yaml`. They are decrypted
  by [sops-nix](https://github.com/Mic92/sops-nix) at activation time and
  exposed via `config.sops.secrets.<name>.path`.
- **User secrets** for `sops-menu` live in `secrets/users/<username>.yaml`.
  They stay encrypted in the repo and are decrypted on demand by the user with
  `sops` plus their SSH key or forwarded SSH agent. They are not wired through
  `sops-nix`.

Rules:
- **Never put plaintext secrets in Nix files.** They end up in the world-readable
  Nix store.
- **Never commit unencrypted secrets.**
- `sops` commands require confirmation.
- Host secrets are declared in `modules/nixos/host/secrets.nix`, conditionally
  based on which services are enabled.
- To inject a host secret into a service config file, use a
  `systemd.services.<name>.preStart` script.
- Edit host secrets with `sops secrets/hosts/<hostname>.yaml`.
- Edit user secrets with `sops secrets/users/<username>.yaml`.
- The `.sops.yaml` file controls which age/SSH keys can decrypt which files.
- Servers with impermanence keep the host age key at
  `/persist/var/lib/sops-nix/key.txt` so it is available early during boot.
  Workstations use `/root/.config/sops/age/keys.txt` for host secrets.

See `secrets/hosts/example.yaml` and `secrets/users/example.yaml` for the file
formats.

## Common Tasks

### Add a new host

1. Create `hosts/servers/<hostname>/`, `hosts/workstations/<hostname>/`, or
   `hosts/wsl/<hostname>/` with the appropriate files for that host family
   (see the matching `example/` directory).
2. Add the host to `flake.nix` under `nixosConfigurations`.
3. If the host uses `host.secrets.enable`, add the host's age key to
   `.sops.yaml` and create `secrets/hosts/<hostname>.yaml`.
4. CI will automatically evaluate the new host on the next PR.

### Add a new user

1. Create `home/<username>/base.nix`, `headless.nix`, and optionally `workstation.nix`
   (see `home/example/` for the template).
2. Reference it from the host config:
   `home-manager.users.<username> = import ../../home/<username>/headless.nix;`
   or `../../home/<username>/workstation.nix` for GUI hosts.
3. Add user secrets if needed: `secrets/users/<username>.yaml`.

### Add a new NixOS service module

1. Create `modules/nixos/services/<service>.nix` following the existing pattern
   (option + mkIf + localhost binding/Caddy virtualHost if it has a web UI).
   See `modules/nixos/example.nix`.
2. Add the import to `modules/nixos/services/default.nix`.
3. Add the toggle `homelab.<service>.enable = true;` in the host's `default.nix`.
4. If the service needs secrets, add them to `secrets/hosts/<hostname>.yaml`
   (via sops) and declare them conditionally in `modules/nixos/host/secrets.nix`.
5. **If the service stores state**, add it to `modules/nixos/host/impermanence.nix`
   (conditionally on the service being enabled).
6. If it has persistent state worth backing up, add its data path to the
   BorgBackup job in `modules/nixos/services/backups.nix`.

### Add a new Home Manager module

1. Create `modules/home-manager/cli/<tool>.nix`,
   `modules/home-manager/tui/<tool>.nix`,
   `modules/home-manager/gui/<tool>.nix`, or
   `modules/home-manager/desktop/<tool>.nix` as appropriate.
2. Add the import to the corresponding `default.nix` in that module directory.
3. Enable it in `home/<username>/headless.nix` or `home/<username>/workstation.nix`.

### Add a host secret

1. Run `sops secrets/hosts/<hostname>.yaml` and add the key/value.
2. Declare it in `modules/nixos/host/secrets.nix` (conditionally if tied to a service).
3. Reference `config.sops.secrets.<name>.path` where needed.

### Add a user secret

1. Run `sops secrets/users/<username>.yaml` and add the key/value.
2. Make sure `.sops.yaml` encrypts that file to the user's SSH key.
3. Reference the encrypted file from `user.cli.sops-menu.secretsFile` when the
   host should expose it through `sops-menu`.

### Toggle a service

Set `homelab.<service>.enable` to `true` or `false` in the host's `default.nix`.
Dependencies, firewall rules, Caddy routes, backup paths, persisted state, and
secrets are adjusted automatically.
