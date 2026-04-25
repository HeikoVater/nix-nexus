# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project Overview

This is a single-host NixOS flake configuration for a home server. The entire
system -- services, networking, users, secrets -- is declared in Nix. There is no
Docker, no CI pipeline, and no imperative setup scripts. Changes are pushed to
GitHub and the server pulls and rebuilds automatically.

The flake defines one output: `nixosConfigurations.home-server`.

## Repository Layout

```
flake.nix                 Entry point. Defines inputs (nixpkgs, home-manager,
                          sops-nix) and the single NixOS configuration.
hosts/home-server/        Host-specific config: service toggles, networking,
                          firewall, SSH, users.
modules/nixos/            System service modules (one file per service).
modules/home-manager/     User environment modules (shell, editor, tools).
home/admin/               Home Manager config for the admin user.
secrets/secrets.yaml      Encrypted secrets (sops + age). NEVER plaintext.
.sops.yaml                sops encryption key configuration.
```

## Module Conventions

Every NixOS service module follows the same pattern:

1. **Option declaration** under `homelab.<service>.enable` using `lib.mkEnableOption`.
2. **Conditional config** wrapped in `lib.mkIf cfg.enable`.
3. **Caddy awareness** -- each module with a web UI uses `lib.mkMerge` with two
   branches:
   - `lib.mkIf config.homelab.caddy.enable` -- binds to localhost and registers
     a Caddy `virtualHost`.
   - `lib.mkIf (!config.homelab.caddy.enable)` -- opens its own firewall port
     and binds to `0.0.0.0`.

Home Manager modules use the same pattern under `user.<tool>.enable`.

When adding a new module:
- Create the file in the appropriate directory (`modules/nixos/` or
  `modules/home-manager/`).
- Add it to the corresponding `default.nix` imports list.
- Follow the existing option/config structure.

## Service Dependencies

```
Zigbee2MQTT ──requires──► Mosquitto
Home Assistant ──uses────► Mosquitto (configured via HA UI, not Nix)
Caddy ──proxies──────────► Home Assistant, Zigbee2MQTT
BorgBackup ──backs up────► Home Assistant state, Zigbee2MQTT state
                           (dynamically based on which are enabled)
sops-nix ──provides──────► MQTT passwords, borg passphrase
```

Zigbee2MQTT has an explicit assertion requiring `homelab.mosquitto.enable = true`.
BorgBackup stops services before backup and restarts them after.

## Secrets

Secrets are managed with [sops-nix](https://github.com/Mic92/sops-nix) and
encrypted with age.

Rules:
- **Never put plaintext secrets in Nix files.** They end up in the world-readable
  Nix store.
- Secrets are declared in `modules/nixos/secrets.nix`, conditionally based on
  which services are enabled.
- At runtime they are decrypted to `/run/secrets/<name>`.
- Reference them via `config.sops.secrets.<name>.path`.
- To inject a secret into a service config file (like Zigbee2MQTT), use a
  `systemd.services.<name>.preStart` script.
- Edit secrets with `sops secrets/secrets.yaml`. The `.sops.yaml` file controls
  which age/SSH keys can decrypt.

## Validating Changes

There is no CI. Validate locally before pushing:

```sh
# Quick sanity check — verifies flake schema and output types
nix flake check

# Full validation — builds the entire system closure without switching
nixos-rebuild build --flake .#home-server
```

`nix flake check` is fast but shallow (schema and types only).
`nixos-rebuild build` is the real validation — it evaluates and builds the full
configuration, catching evaluation errors, missing dependencies, and build
failures.

When `nh` is enabled, `nh os build` is an alternative to `nixos-rebuild build`
with nicer output (build-tree visualization and package diffs).

After pushing to `main`, the server's auto-upgrade timer will pick up changes at
04:00. For immediate deployment, SSH in and run:

```sh
nixos-rebuild switch --flake github:heikov/home-server
```

## Common Tasks

### Add a new NixOS service module

1. Create `modules/nixos/<service>.nix` following the existing pattern
   (option + mkIf + Caddy awareness if it has a web UI).
2. Add the import to `modules/nixos/default.nix`.
3. Add the toggle `homelab.<service>.enable = true;` in
   `hosts/home-server/default.nix`.
4. If the service needs secrets, add them to `secrets/secrets.yaml` (via sops)
   and declare them conditionally in `modules/nixos/secrets.nix`.
5. If it has persistent state, add its data path to the BorgBackup job in
   `modules/nixos/backups.nix`.

### Add a new Home Manager module

1. Create `modules/home-manager/<tool>.nix` with `user.<tool>.enable`.
2. Add the import to `modules/home-manager/default.nix`.
3. Add the toggle in `home/admin/default.nix`.

### Add a secret

1. Run `sops secrets/secrets.yaml` and add the key/value.
2. Declare it in `modules/nixos/secrets.nix` (conditionally if tied to a
   service).
3. Reference `config.sops.secrets.<name>.path` where needed.

### Toggle a service

Set `homelab.<service>.enable` to `true` or `false` in
`hosts/home-server/default.nix`. Dependencies, firewall rules, Caddy routes,
backup paths, and secrets are adjusted automatically.
