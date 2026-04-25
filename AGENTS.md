# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project Overview

This is a single-host NixOS flake configuration for a home server. The entire
system -- services, networking, users, secrets, disk layout -- is declared in
Nix. There is no Docker, no CI pipeline, and no imperative setup scripts.
Changes are pushed to GitHub and the server pulls and rebuilds automatically.

The system uses an **impermanent root** (tmpfs) with two-tier ZFS storage.
Only explicitly declared state survives reboots.

The flake defines one output: `nixosConfigurations.home-server`.

## Repository Layout

```
flake.nix                 Entry point. Defines inputs (nixpkgs, home-manager,
                          sops-nix, disko, impermanence) and the single
                          NixOS configuration.
hosts/home-server/        Host-specific config.
  default.nix             Service toggles, networking, firewall, SSH, users.
  hardware-configuration.nix  Boot loader, kernel, ZFS, tmpfs root, zram,
                              ARC tuning.
  disko.nix               Declarative disk layout (partitions, ZFS pools,
                          datasets, L2ARC).
modules/nixos/            System service modules (one file per service).
  impermanence.nix        Declares which state survives reboots.
  secrets.nix             sops-nix secret declarations.
  caddy.nix               Reverse proxy.
  home-assistant.nix      Smart home automation.
  mosquitto.nix           MQTT broker.
  zigbee2mqtt.nix         Zigbee bridge.
  backups.nix             BorgBackup to tank pool.
  auto-upgrade.nix        Daily flake rebuild from GitHub.
  nh.nix                  Nix helper / garbage collection.
modules/home-manager/     User environment modules (shell, editor, tools).
home/heikov/              Home Manager config for the heikov user.
secrets/hosts/home-server.yaml  Encrypted secrets (sops + age). NEVER plaintext.
.sops.yaml                sops encryption key configuration.
```

## Storage Architecture

The server uses a two-tier ZFS storage model with an ephemeral root.

### Ephemeral Root

Root (`/`) is a 4 GB tmpfs -- wiped every reboot. Only paths explicitly
declared in `modules/nixos/impermanence.nix` survive. This ensures the
system is always in a clean, known state.

### Disk Layout

```
NVMe SSD (1 TB WD_BLACK SN7100)
┌──────┬──────┬─────────┬──────────────────────────────┐
│ ESP  │ Swap │ L2ARC   │ rpool (ZFS)                  │
│ 1 GB │ 8 GB │ 150 GB  │ ~841 GB                      │
└──────┴──────┴─────────┴──────────────────────────────┘

HDD 1 (12 TB IronWolf)    HDD 2 (12 TB IronWolf)
┌──────────────────────┐   ┌──────────────────────┐
│   tank (mirror) ─────┤   ├───── tank (mirror)   │
└──────────────────────┘   └──────────────────────┘
```

### ZFS Pools

**rpool** (SSD, single disk, ~841 GB):
- `rpool/nix` -> `/nix` -- Nix store
- `rpool/persist` -> `/persist` -- all persistent system/service state
- `rpool/postgres` -> `/var/lib/postgresql` -- database (recordsize=16K)

**tank** (2x 12 TB mirror, 150 GB SSD L2ARC):
- `tank/safe` -> `/tank/safe` -- important docs/photos (secondarycache=all)
- `tank/data` -> `/tank/data` -- Syncthing/Samba (secondarycache=all)
- `tank/media` -> `/tank/media` -- Jellyfin video (recordsize=1M, secondarycache=metadata)
- `tank/backups` -> `/tank/backups` -- BorgBackup repo (secondarycache=metadata)

All datasets use legacy mounts for explicit systemd mount ordering.

### Key Settings

- ZFS ARC capped at 16 GB (of 48 GB RAM)
- zram swap (16% of RAM) + 8 GB SSD swap partition
- Monthly auto-scrub, weekly TRIM on SSD pool
- L2ARC persistent across reboots (OpenZFS default)

## Impermanence

Since root is tmpfs, any state that must survive reboots is bind-mounted
from `/persist` via the impermanence module.

**What survives reboots** (defined in `modules/nixos/impermanence.nix`):
- System: `/var/log`, `/var/lib/nixos`, `/var/lib/systemd/timers`,
  `/var/lib/systemd/coredump`, `/etc/zfs`, `/etc/machine-id`
- Secrets: `/var/lib/sops-nix` (age decryption key -- critical)
- SSH: Host keys stored directly at `/persist/etc/ssh/`
- Services: `/var/lib/hass`, `/var/lib/zigbee2mqtt`, `/var/lib/mosquitto`
  (conditional on service being enabled)
- User: `/home/heikov` (bind-mounted from `/persist/home/heikov`)

**Rule: when adding a service that stores state, you must persist it.**
Add the path to `modules/nixos/impermanence.nix` or the state will be
lost on reboot.

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
impermanence ──persists──► All service state dirs under /persist
disko ──manages──────────► Disk partitions, ZFS pools, datasets
```

Zigbee2MQTT has an explicit assertion requiring `homelab.mosquitto.enable = true`.
BorgBackup stops services before backup and restarts them after.
BorgBackup writes to `/tank/backups/borg` on the HDD mirror pool.

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
- Edit secrets with `sops secrets/hosts/home-server.yaml`. The `.sops.yaml` file controls
  which age/SSH keys can decrypt.
- The age key lives at `/var/lib/sops-nix/key.txt` which is persisted via
  impermanence (critical -- without it, secrets cannot be decrypted on boot).

## Validating Changes

There is no CI. Validate locally before pushing:

```sh
# Quick sanity check -- verifies flake schema and output types
nix flake check

# Full validation -- builds the entire system closure without switching
nixos-rebuild build --flake .#home-server
```

`nix flake check` is fast but shallow (schema and types only).
`nixos-rebuild build` is the real validation -- it evaluates and builds the full
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
4. If the service needs secrets, add them to `secrets/hosts/home-server.yaml` (via sops)
   and declare them conditionally in `modules/nixos/secrets.nix`.
5. **If the service stores state** (e.g. under `/var/lib/<name>`), add it to
   `modules/nixos/impermanence.nix` (conditionally on the service being
   enabled). Without this, the state will be lost on every reboot.
6. If it has persistent state worth backing up, add its data path to the
   BorgBackup job in `modules/nixos/backups.nix`.

### Add a new Home Manager module

1. Create `modules/home-manager/<tool>.nix` with `user.<tool>.enable`.
2. Add the import to `modules/home-manager/default.nix`.
3. Add the toggle in `home/heikov/default.nix`.

### Add a secret

1. Run `sops secrets/hosts/home-server.yaml` and add the key/value.
2. Declare it in `modules/nixos/secrets.nix` (conditionally if tied to a
   service).
3. Reference `config.sops.secrets.<name>.path` where needed.

### Toggle a service

Set `homelab.<service>.enable` to `true` or `false` in
`hosts/home-server/default.nix`. Dependencies, firewall rules, Caddy routes,
backup paths, persisted state, and secrets are adjusted automatically.

### Add a new ZFS dataset

1. Add the dataset to the appropriate pool in `hosts/home-server/disko.nix`.
2. Set `mountpoint = "legacy"` in options and provide the disko `mountpoint`.
3. If the dataset stores service state on the SSD pool, ensure it is persisted
   via impermanence or has its own mount point.
