# nix-nexus

Declarative NixOS configuration for a home server running smart home
automation and media services. The entire system is defined as a single Nix
flake with impermanent root (tmpfs) and two-tier ZFS storage. Deploys
automatically from GitHub.

## Hardware

| Component | Model |
|-----------|-------|
| CPU | AMD Ryzen 5 7600 (Zen 4, 6-core) |
| RAM | 48 GB DDR5-5600 (2x 24 GB Crucial Pro) |
| Motherboard | ASRock B650M Pro RS (AM5) |
| Boot / Hot Storage | WD_BLACK SN7100 1 TB NVMe |
| Bulk Storage | 2x Seagate IronWolf 12 TB (7200 RPM) |
| Case | Fractal Design Define R5 |
| PSU | be quiet! Pure Power 13 M 550W 80+ Gold |

## Storage Architecture

```
           ┌─────────── RAM (48 GB) ───────────┐
           │                                    │
           │  / (tmpfs, 4 GB)  ← wiped on boot │
           │  ZFS ARC (16 GB cap)               │
           │  zram swap (~8 GB compressed)      │
           └────────────────────────────────────┘

  NVMe SSD (1 TB)
  ┌──────┬──────┬─────────┬────────────────────┐
  │ ESP  │ Swap │ L2ARC   │ rpool              │
  │ 1 GB │ 8 GB │ 150 GB  │ ~841 GB            │
  └──────┴──────┴────┬────┴────────────────────┘
                     │ cache
  HDD 1 (12 TB)  ┌──▼──┐  HDD 2 (12 TB)
  ┌───────────────┤tank ├───────────────┐
  │               │mirror│              │
  └───────────────┴─────┴───────────────┘

  rpool/nix       → /nix              (Nix store)
  rpool/persist   → /persist          (all persistent state)
  rpool/postgres  → /var/lib/postgresql

  tank/safe       → /tank/safe        (photos, documents)
  tank/data       → /tank/data        (Syncthing, Samba)
  tank/media      → /tank/media       (Jellyfin video)
  tank/backups    → /tank/backups     (BorgBackup repo)
```

Root (`/`) is tmpfs and wiped every reboot. Only paths declared in
`modules/nixos/impermanence.nix` survive, bind-mounted from `/persist`.

## Services

```
                  ┌──────────────────────────────┐
                  │     Caddy (ports 80/443)      │
                  │  hass.<domain> → localhost:8123│
                  │  z2m.<domain>  → localhost:8080│
                  └──────┬───────────────┬────────┘
                         │               │
              ┌──────────▼───┐   ┌───────▼──────────┐
              │Home Assistant│   │   Zigbee2MQTT     │
              │  (port 8123) │   │   (port 8080)     │
              └──────┬───────┘   │  serial: /dev/zigbee
                     │           └───────┬──────────┘
                     │  ┌────────────┐   │
                     └─►│ Mosquitto  │◄──┘
                        │(port 1883) │
                        └────────────┘

  ┌──────────────────┐   ┌───────────────────────┐
  │ BorgBackup (3 AM)│   │ Auto-Upgrade (4 AM)   │
  │ → /tank/backups  │   │ ← github:heikov/      │
  │                  │   │   home-server          │
  └──────────────────┘   └───────────────────────┘
```

| Service | Description |
|---------|-------------|
| **Caddy** | Reverse proxy with self-signed TLS and subdomain routing |
| **Home Assistant** | Smart home automation platform |
| **Zigbee2MQTT** | Bridges Zigbee devices to MQTT for Home Assistant discovery |
| **Mosquitto** | MQTT broker for inter-service messaging (localhost only) |
| **BorgBackup** | Daily encrypted backups of service state to the tank pool |
| **Auto-Upgrade** | Pulls the latest flake from GitHub and rebuilds daily |

## Repository Structure

```
.
├── flake.nix                        # Flake entry point
├── hosts/
│   └── home-server/
│       ├── default.nix              # Host config, service toggles, networking
│       ├── hardware-configuration.nix  # Boot, kernel, ZFS, tmpfs root, zram
│       └── disko.nix                # Declarative disk layout (partitions, pools)
├── modules/
│   ├── nixos/                       # System-level service modules
│   │   ├── impermanence.nix         # Persistent state declarations
│   │   ├── secrets.nix
│   │   ├── caddy.nix
│   │   ├── home-assistant.nix
│   │   ├── mosquitto.nix
│   │   ├── zigbee2mqtt.nix
│   │   ├── backups.nix
│   │   ├── auto-upgrade.nix
│   │   └── nh.nix
│   └── home-manager/                # User environment modules
│       ├── nvf.nix
│       ├── opencode.nix
│       ├── tmux.nix
│       └── zsh.nix
├── home/
│   └── heikov/
│       └── default.nix              # Home Manager config for the heikov user
└── secrets/
    └── hosts/
        └── home-server.yaml         # Encrypted secrets (sops + age)
```

## Deployment

Build and apply the configuration locally:

```sh
nixos-rebuild switch --flake .#home-server
```

Or build without switching to verify it evaluates cleanly:

```sh
nixos-rebuild build --flake .#home-server
```

When `homelab.auto-upgrade.enable` is `true`, the server pulls the latest flake
from GitHub at 04:00 daily and rebuilds itself. Reboots (for kernel updates) are
permitted within a 03:00-05:00 maintenance window.

## Configuration

All services are toggled in `hosts/home-server/default.nix`:

```nix
homelab = {
  caddy.enable = true;
  home-assistant.enable = true;
  mosquitto.enable = true;
  zigbee2mqtt.enable = true;
  backups.enable = true;
  auto-upgrade.enable = true;
  nh.enable = true;
};
```

Setting any toggle to `false` cleanly disables the service and adjusts
dependents automatically (firewall rules, backup paths, Caddy routes,
persisted state, secrets).

User-level tools are toggled in `home/heikov/default.nix`:

```nix
user = {
  nvf.enable = true;
  zsh.enable = true;
  tmux.enable = true;
  opencode.enable = true;
};
```

## Secrets Management

Secrets are encrypted at rest with [sops-nix](https://github.com/Mic92/sops-nix)
using age keys. They are decrypted to `/run/secrets/<name>` at activation time.

Edit secrets:

```sh
sops secrets/hosts/home-server.yaml
```

The age key must be present on the server at `/var/lib/sops-nix/key.txt` before
the first deploy. This path is persisted via impermanence so it survives
reboots. See `.sops.yaml` for the encryption key configuration.

## License

[MIT](LICENSE)
