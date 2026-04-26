# nix-nexus

Declarative multi-host NixOS configuration for home servers. The entire system
-- services, networking, users, secrets, disk layout -- is defined as a Nix
flake with impermanent root (tmpfs) and ZFS storage. Changes go through PRs
with CI validation, and servers auto-deploy from `main`.

## Repository Structure

```
.
├── flake.nix                           # Flake entry point, all inputs and host definitions
├── .envrc                              # Direnv -- activates devShell, installs pre-commit hooks
├── .github/workflows/ci.yml           # CI -- runs on every PR to main
├── hosts/
│   ├── mu/                             # Per-host configuration
│   │   ├── default.nix                 # Service toggles, networking, users
│   │   ├── hardware-configuration.nix  # Boot, kernel, storage
│   │   └── disko.nix                   # Declarative disk layout
│   └── example/                        # Example host template
├── home/
│   ├── heikov/                         # Per-user Home Manager config
│   │   └── default.nix                 # Module toggles, git, locale, packages
│   └── example/                        # Example user template
├── modules/
│   ├── nixos/                          # System service modules (one per service)
│   │   ├── impermanence.nix            # Persistent state declarations
│   │   ├── secrets.nix                 # sops-nix secret declarations
│   │   ├── caddy.nix                   # Reverse proxy
│   │   ├── home-assistant.nix          # Smart home automation
│   │   ├── mosquitto.nix               # MQTT broker
│   │   ├── zigbee2mqtt.nix             # Zigbee bridge
│   │   ├── backups.nix                 # BorgBackup
│   │   ├── auto-upgrade.nix            # Daily flake rebuild from GitHub
│   │   ├── nh.nix                      # Nix helper / garbage collection
│   │   ├── coolercontrol.nix           # Fan management
│   │   └── example.nix                 # Example module template
│   └── home-manager/                   # User environment modules
│       ├── cli/                        # CLI tools (zsh, tmux, starship, etc.)
│       └── tui/                        # TUI tools (nvf, opencode, yazi, etc.)
└── secrets/
    ├── hosts/<hostname>.yaml           # Encrypted host secrets (sops + age)
    ├── users/<username>.yaml           # Encrypted user secrets (sops-menu)
    └── */example.yaml                  # Unencrypted reference files
```

## Getting Started

### Prerequisites

- [Nix](https://nixos.org/download/) with flakes enabled
- [direnv](https://direnv.net/) (recommended)

### Setup

```sh
git clone <repo-url>
cd nix-nexus
direnv allow    # installs pre-commit hooks via devShell
```

### Configuration

System services are toggled per-host in `hosts/<hostname>/default.nix`:

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

User-level tools are toggled per-user in `home/<username>/default.nix`:

```nix
user = {
  cli = {
    packages.enable = true;
    zsh.enable = true;
    tmux.enable = true;
    starship.enable = true;
    # ...
  };
  tui = {
    nvf.enable = true;
    opencode.enable = true;
    yazi.enable = true;
    # ...
  };
};
```

Setting any toggle to `false` cleanly disables it and adjusts dependents
automatically (firewall rules, backup paths, Caddy routes, persisted state,
secrets).

## Validation & CI

### Pre-commit hooks

Installed automatically via `direnv allow` (or `nix develop`). Runs on every
commit:
- **nixfmt-rfc-style** -- formats staged `.nix` files
- **check-merge-conflicts** -- catches leftover conflict markers
- **detect-private-key** -- prevents committing private keys

### CI (GitHub Actions)

Every PR to `main` runs:
1. `nix fmt -- --check` -- formatting gate
2. `nix flake check` -- schema validation
3. `nix eval` for **every** host -- deep evaluation

Adding a new host to `flake.nix` automatically includes it in CI.

### Local validation

```sh
nix fmt                                  # format all Nix files
nix flake check                          # validate flake schema
nix eval .#nixosConfigurations.<host>.config.system.build.toplevel --apply 'x: "ok"'  # deep eval
nixos-rebuild build --flake .#<host>     # full build without switching
```

## Deployment

After a PR is merged to `main`, each server's auto-upgrade timer picks up
changes (typically at 04:00). For immediate deployment:

```sh
ssh <host>
nixos-rebuild switch --flake github:<org>/<repo>
```

## Secrets Management

Secrets are encrypted at rest with [sops-nix](https://github.com/Mic92/sops-nix)
using age keys, decrypted to `/run/secrets/<name>` at activation time.
User password hashes also stay in sops and are made available early enough
during boot for declarative user creation.

```sh
sops secrets/hosts/<hostname>.yaml       # edit host secrets
sops secrets/users/<username>.yaml       # edit user secrets (sops-menu)
```

The age key must be present on the server at
`/persist/var/lib/sops-nix/key.txt` before the first deploy. It needs to be
reachable during early boot, before users are recreated.
See `.sops.yaml` for encryption key configuration and `secrets/*/example.yaml`
for file format reference.

## Adding Hosts, Users, and Modules

See [AGENTS.md](AGENTS.md) for detailed instructions on:
- Adding a new host
- Adding a new user
- Adding NixOS service modules
- Adding Home Manager modules (CLI/TUI)
- Adding secrets

Example templates are provided in `hosts/example/`, `home/example/`,
`modules/nixos/example.nix`, `modules/home-manager/cli/example.nix`,
`modules/home-manager/tui/example.nix`, and `secrets/*/example.yaml`.

## License

[MIT](LICENSE)
