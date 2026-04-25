# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project Overview

This is a multi-host NixOS flake configuration for home servers. The entire
system -- services, networking, users, secrets, disk layout -- is declared in
Nix. There is no Docker and no imperative setup scripts. Changes go through
pull requests with CI validation, and each server pulls and rebuilds
automatically.

Hosts use an **impermanent root** (tmpfs) with ZFS storage. Only explicitly
declared state survives reboots.

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
                          sops-nix, disko, impermanence, nvf, git-hooks) and
                          all NixOS host configurations.
.envrc                    Direnv config -- activates devShell and installs
                          pre-commit hooks automatically.
.github/workflows/ci.yml  GitHub Actions CI -- runs on every PR to main.

hosts/<hostname>/         Per-host configuration.
  default.nix             Service toggles, networking, firewall, SSH, users.
  hardware-configuration.nix  Boot, kernel, storage, hardware-specific tuning.
  disko.nix               Declarative disk layout (if applicable).
hosts/example/            Example host for reference.

home/<username>/          Per-user Home Manager configuration.
  default.nix             Module toggles, git, locale, session, packages.
home/example/             Example user for reference.

modules/nixos/            System service modules (one file per service).
  impermanence.nix        Declares which state survives reboots.
  secrets.nix             sops-nix secret declarations.
  caddy.nix               Reverse proxy.
  home-assistant.nix      Smart home automation.
  mosquitto.nix           MQTT broker.
  zigbee2mqtt.nix         Zigbee bridge.
  backups.nix             BorgBackup.
  auto-upgrade.nix        Daily flake rebuild from GitHub.
  nh.nix                  Nix helper / garbage collection.
  example.nix             Example NixOS module for reference.

modules/home-manager/     User environment modules.
  cli/                    Command-line tools (zsh, tmux, starship, etc.).
    example.nix           Example CLI module for reference.
  tui/                    Terminal UI tools (nvf, opencode, yazi, etc.).
    example.nix           Example TUI module for reference.

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
- **detect-private-key** -- prevents committing private keys

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

# Quick sanity check -- verifies flake schema and output types
nix flake check

# Deep evaluation of a specific host
nix eval .#nixosConfigurations.<hostname>.config.system.build.toplevel --apply 'x: "ok"'

# Full build without switching (most thorough, but slow)
nixos-rebuild build --flake .#<hostname>
```

### Deployment

After a PR is merged to `main`, each server's auto-upgrade timer picks up
changes (typically at 04:00). For immediate deployment, SSH in and run:

```sh
nixos-rebuild switch --flake github:<org>/<repo>
```

## Impermanence

Root (`/`) is tmpfs on hosts that use impermanence -- wiped every reboot.
Only paths declared in `modules/nixos/impermanence.nix` survive, bind-mounted
from `/persist`.

**Rule: when adding a service that stores state, you must persist it.**
Add the path to `modules/nixos/impermanence.nix` or the state will be lost
on reboot.

## Module Conventions

### NixOS service modules

Every NixOS service module follows the same pattern:

1. **Option declaration** under `homelab.<service>.enable` using `lib.mkEnableOption`.
2. **Conditional config** wrapped in `lib.mkIf cfg.enable`.
3. **Caddy awareness** -- modules with a web UI use `lib.mkMerge` with two branches:
   - `lib.mkIf config.homelab.caddy.enable` -- binds to localhost, registers Caddy virtualHost.
   - `lib.mkIf (!config.homelab.caddy.enable)` -- opens its own firewall port, binds to `0.0.0.0`.

See `modules/nixos/example.nix` for the full template.

### Home Manager modules

Home Manager modules are split into `cli/` and `tui/` subdirectories:

- **CLI** (`modules/home-manager/cli/`): Command-line tools -- shells, prompts,
  aliases, simple utilities.
- **TUI** (`modules/home-manager/tui/`): Terminal UI applications -- editors,
  file managers, AI assistants.

Each module follows the pattern:
1. **Option declaration** under `user.cli.<tool>.enable` or `user.tui.<tool>.enable`.
2. **Conditional config** wrapped in `lib.mkIf cfg.enable`.

See `modules/home-manager/cli/example.nix` and `modules/home-manager/tui/example.nix`.

## Secrets

Secrets are managed with [sops-nix](https://github.com/Mic92/sops-nix) and
encrypted with age.

Rules:
- **Never put plaintext secrets in Nix files.** They end up in the world-readable
  Nix store.
- Host secrets are declared in `modules/nixos/secrets.nix`, conditionally based
  on which services are enabled.
- At runtime they are decrypted to `/run/secrets/<name>`.
- Reference them via `config.sops.secrets.<name>.path`.
- To inject a secret into a service config file, use a
  `systemd.services.<name>.preStart` script.
- Edit secrets with `sops secrets/hosts/<hostname>.yaml`.
- The `.sops.yaml` file controls which age/SSH keys can decrypt which files.
- The age key lives at `/var/lib/sops-nix/key.txt` which must be persisted via
  impermanence.

User secrets (for sops-menu) live in `secrets/users/<username>.yaml`. See
`secrets/users/example.yaml` for the schema.

## Common Tasks

### Add a new host

1. Create `hosts/<hostname>/` with `default.nix` and `hardware-configuration.nix`
   (see `hosts/example/` for the template).
2. Add the host to `flake.nix` under `nixosConfigurations`.
3. Add the host's age key to `.sops.yaml` and create
   `secrets/hosts/<hostname>.yaml`.
4. CI will automatically evaluate the new host on the next PR.

### Add a new user

1. Create `home/<username>/default.nix` (see `home/example/` for the template).
2. Reference it from the host config:
   `home-manager.users.<username> = import ../../home/<username>;`
3. Add user secrets if needed: `secrets/users/<username>.yaml`.

### Add a new NixOS service module

1. Create `modules/nixos/<service>.nix` following the existing pattern
   (option + mkIf + Caddy awareness if it has a web UI).
   See `modules/nixos/example.nix`.
2. Add the import to `modules/nixos/default.nix`.
3. Add the toggle `homelab.<service>.enable = true;` in the host's `default.nix`.
4. If the service needs secrets, add them to `secrets/hosts/<hostname>.yaml`
   (via sops) and declare them conditionally in `modules/nixos/secrets.nix`.
5. **If the service stores state**, add it to `modules/nixos/impermanence.nix`
   (conditionally on the service being enabled).
6. If it has persistent state worth backing up, add its data path to the
   BorgBackup job in `modules/nixos/backups.nix`.

### Add a new Home Manager module

1. Create `modules/home-manager/cli/<tool>.nix` or `modules/home-manager/tui/<tool>.nix`
   (see the example files for templates).
2. Add the import to the corresponding `default.nix` in `cli/` or `tui/`.
3. Enable it in `home/<username>/default.nix`.

### Add a secret

1. Run `sops secrets/hosts/<hostname>.yaml` and add the key/value.
2. Declare it in `modules/nixos/secrets.nix` (conditionally if tied to a service).
3. Reference `config.sops.secrets.<name>.path` where needed.

### Toggle a service

Set `homelab.<service>.enable` to `true` or `false` in the host's `default.nix`.
Dependencies, firewall rules, Caddy routes, backup paths, persisted state, and
secrets are adjusted automatically.
