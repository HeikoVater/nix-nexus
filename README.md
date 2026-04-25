# nix-nexus

Declarative NixOS configuration for a home server running a smart home automation
stack. The entire system is defined as a single Nix flake and deploys
automatically from GitHub.

## Architecture

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
  │ → local ZFS repo │   │ ← github:heikov/      │
  │                  │   │   home-server          │
  └──────────────────┘   └───────────────────────┘
```

## Services

| Service | Description |
|---------|-------------|
| **Caddy** | Reverse proxy with self-signed TLS and subdomain routing |
| **Home Assistant** | Smart home automation platform |
| **Zigbee2MQTT** | Bridges Zigbee devices to MQTT for Home Assistant discovery |
| **Mosquitto** | MQTT broker for inter-service messaging (localhost only) |
| **BorgBackup** | Daily encrypted backups of service state to a local ZFS pool |
| **Auto-Upgrade** | Pulls the latest flake from GitHub and rebuilds daily |

## Repository Structure

```
.
├── flake.nix                        # Flake entry point
├── hosts/
│   └── home-server/
│       ├── default.nix              # Host config, service toggles, networking
│       └── hardware-configuration.nix
├── modules/
│   ├── nixos/                       # System-level service modules
│   │   ├── auto-upgrade.nix
│   │   ├── backups.nix
│   │   ├── caddy.nix
│   │   ├── home-assistant.nix
│   │   ├── mosquitto.nix
│   │   ├── secrets.nix
│   │   └── zigbee2mqtt.nix
│   └── home-manager/                # User environment modules
│       ├── nvf.nix
│       ├── opencode.nix
│       ├── tmux.nix
│       └── zsh.nix
├── home/
│   └── admin/
│       └── default.nix              # Home Manager config for the admin user
└── secrets/
    └── secrets.yaml                 # Encrypted secrets (sops + age)
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
};
```

Setting any toggle to `false` cleanly disables the service and adjusts
dependents automatically (firewall rules, backup paths, Caddy routes).

User-level tools are toggled in `home/admin/default.nix`:

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
sops secrets/secrets.yaml
```

The age key must be present on the server at `/var/lib/sops-nix/key.txt` before
the first deploy. See `.sops.yaml` for the encryption key configuration.

## License

[MIT](LICENSE)
