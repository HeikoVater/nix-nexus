# nix-nexus

Declarative multi-host NixOS configuration for home servers, workstations, and
WSL. The entire system -- services, networking, users, secrets, disk layout,
and Home Manager profiles -- is defined as a Nix flake. Changes go through PRs
with CI validation, and each host rebuilds declaratively from the repo.

## Repository Structure

```
.
├── flake.nix                           # Flake entry point, all inputs and host definitions
├── .envrc                              # Direnv -- activates devShell, installs pre-commit hooks
├── .github/workflows/ci.yml           # CI -- runs on every PR to main
├── SERVER_SETUP.md                     # Server installation guide
├── WORKSTATION_SETUP.md                # Workstation installation guide
├── hosts/
│   ├── servers/
│   │   ├── common.nix                  # Shared server defaults
│   │   ├── example/                    # Example server host
│   │   └── mu/                         # Current home server
│   ├── workstations/
│   │   ├── common.nix                  # Shared desktop/laptop defaults
│   │   ├── example/                    # Example workstation host
│   │   ├── desktop/                    # Desktop host
│   │   └── laptop/                     # Laptop host
│   └── wsl/
│       ├── common.nix                  # Shared WSL defaults
│       ├── example/                    # Example WSL host
│       └── wanzl/                      # Current WSL host
├── home/
│   ├── heikov/                         # Per-user Home Manager config
│   │   ├── base.nix                    # Identity, locale, shared Stylix
│   │   ├── headless.nix                # CLI/TUI profile
│   │   └── workstation.nix             # GUI/desktop profile
│   └── example/                        # Example user template
├── modules/
│   ├── nixos/                          # NixOS module tree
│   │   ├── host/                       # Host lifecycle and persistence modules
│   │   ├── services/                   # Homelab and always-on services
│   │   ├── workstation/                # Desktop/laptop system features
│   │   └── example.nix                 # Example module template
│   └── home-manager/                   # User environment modules
│       ├── cli/                        # CLI tools (zsh, starship, etc.)
│       ├── tui/                        # TUI tools (tmux, nvf, opencode, yazi, etc.)
│       ├── gui/                        # Graphical applications
│       ├── desktop/                    # Desktop/session configuration
│       └── example.nix                 # Example Home Manager module
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

Installation guides:
- `SERVER_SETUP.md` for `hosts/servers/*`
- `WORKSTATION_SETUP.md` for `hosts/workstations/*`

### Configuration

System features are toggled per-host in `hosts/<family>/<hostname>/default.nix`:

```nix
host.auto-upgrade.enable = true;

homelab = {
  hostIPv4 = "192.168.188.2";
  # Optional override; defaults to "<hostname>.lan"
  domain = "mu.lan";
  pihole.enable = true;
  home-assistant.enable = true;
  mosquitto.enable = true;
  zigbee2mqtt.enable = true;
  backups.enable = true;
};
```

User-level tools are toggled per-user in `home/<username>/headless.nix` or
`home/<username>/workstation.nix`:

```nix
user = {
  cli = {
    packages.enable = true;
    zsh.enable = true;
    starship.enable = true;
    # ...
  };
  tui = {
    tmux.enable = true;
    nvf.enable = true;
    opencode.enable = true;
    yazi.enable = true;
    # ...
  };
};
```

Setting any toggle to `false` cleanly disables it and adjusts dependents
automatically (firewall rules, backup paths, Caddy routes, persisted state,
secrets). Browser-facing services always publish Caddy virtual hosts and start
Caddy automatically when needed.

When `homelab.pihole.enable = true`, Pi-hole serves DNS on port `53`, exposes
its dashboard at `https://pihole.<domain>`, and creates local DNS aliases for
all Caddy-backed service hostnames under `homelab.domain`. Set
`homelab.hostIPv4` on statically addressed hosts so shared modules can refer to
the same LAN address.

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

The repo uses two secret flows on purpose:

1. **Host secrets** such as password hashes, NAS credentials, MQTT passwords,
   and API keys.
   These are encrypted for the host age key, decrypted by
   [sops-nix](https://github.com/Mic92/sops-nix), and exposed under
   `/run/secrets/<name>` at activation time.
2. **User secrets** for `sops-menu`.
   These live in `secrets/users/<username>.yaml`, stay encrypted in the repo,
   and are normally decrypted on demand by the user with `sops` plus their SSH
   key or forwarded SSH agent.

That split keeps boot-time host secrets automated while still letting user
secrets remain tied to the user's own SSH identity.

```sh
sops secrets/hosts/<hostname>.yaml       # edit host secrets
sops secrets/users/<username>.yaml       # edit user secrets (sops-menu)
```

Servers with impermanence keep the age key at
`/persist/var/lib/sops-nix/key.txt` so it is available before declarative
users are recreated. Workstations use `/root/.config/sops/age/keys.txt` for
host secrets only; `sops-menu` still uses the user's SSH key.
See `.sops.yaml` for encryption key configuration and `secrets/*/example.yaml`
for file format reference.

## Adding Hosts, Users, and Modules

See [AGENTS.md](AGENTS.md) for detailed instructions on:
- Adding a new host
- Adding a new user
- Adding NixOS service modules
- Adding Home Manager modules
- Adding secrets

Example templates are provided in `hosts/servers/example/`,
`hosts/workstations/example/`, `hosts/wsl/example/`, `home/example/`,
`modules/nixos/example.nix`, `modules/home-manager/example.nix`, and
`secrets/*/example.yaml`.

## License

[MIT](LICENSE)
