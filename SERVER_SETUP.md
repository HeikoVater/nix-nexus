# Server Setup Guide

Step-by-step installation of a new host from a graphical NixOS live USB.
Everything happens on the server itself -- no separate workstation needed for
the initial install. Changes are then pushed as a PR from your workstation.

This guide is specifically for server hosts under `hosts/servers/`. Workstation
and WSL hosts share the same repo structure, but they do not follow the
Disko/ZFS/impermanence-specific install flow below. For workstation hosts, use
`WORKSTATION_SETUP.md` instead.

This guide assumes the repo already contains `hosts/servers/<hostname>/` and
any host-specific files needed for the machine you are installing. For a brand
new host, start from `hosts/servers/example/` and adapt it first, or copy a
similar existing host if you want to reuse its Disko/ZFS layout.

## What You Need

Two USB drives plugged into the server:

1. **Installer USB** -- Graphical NixOS 25.11 ISO (GNOME or Plasma), booted.
   Download from https://nixos.org/download (select the graphical live ISO).
2. **Data USB** -- containing:
   - A clone of this repository
   - Your SSH private key (`id_ed25519`) -- needed to edit sops files and later
     decrypt `sops-menu` user secrets
   - The host's age key (`key.txt`) and its public key -- needed for host
     secrets at boot

**Internet required** (Ethernet cable connected to your router).

---

## Step 1: Boot and Open a Terminal

Boot from the installer USB (enter BIOS, set USB as first boot device). Once
the graphical desktop loads, open a terminal.

Verify internet connectivity:

```sh
ping -c 3 1.1.1.1
```

Enable flakes for the live session:

```sh
export NIX_CONFIG="experimental-features = nix-command flakes"
```

---

## Step 2: Locate the Data USB

The graphical desktop auto-mounts USB drives under `/run/media/nixos/`. Find
your data USB:

```sh
ls /run/media/nixos/
```

Set a variable for convenience (replace `<label>` with the actual name shown):

```sh
USB=/run/media/nixos/<label>
```

If auto-mount did not work, mount manually:

```sh
lsblk
sudo mkdir -p /tmp/usb
sudo mount /dev/sdX1 /tmp/usb    # replace sdX1 with your device
USB=/tmp/usb
```

---

## Step 3: Copy Files from the Data USB

```sh
cp -r "$USB/nix-nexus" /tmp/nix-nexus
cp "$USB/key.txt" /tmp/host-age-key.txt
mkdir -p ~/.ssh
cp "$USB/id_ed25519" ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519
```

Adjust source paths to match your USB layout.

---

## Step 4: Enter a Tool Shell

```sh
nix-shell -p sops age mkpasswd git
export NIX_CONFIG="experimental-features = nix-command flakes"
export EDITOR=vim
```

Stay in this shell for all remaining steps.

---

## Step 5: Prepare the Host Config and Identify Disk IDs

If the host directory does not exist yet, create it from the example template:

```sh
cp -r /tmp/nix-nexus/hosts/servers/example \
  /tmp/nix-nexus/hosts/servers/<hostname>
```

Then update at least:

1. `hosts/servers/<hostname>/default.nix`
2. `hosts/servers/<hostname>/hardware-configuration.nix`
3. `flake.nix` -- add the host under `nixosConfigurations`
4. `secrets/hosts/<hostname>.yaml` if the host uses `sops-nix`
5. `hosts/servers/<hostname>/disko.nix` if the host uses Disko

At minimum, make sure the host config sets:

- `networking.hostName = hostname;`
- a declarative wheel user plus matching `home-manager.users.<username>`
- `sops.defaultSopsFile = ../../../secrets/hosts/<hostname>.yaml;`
- `sops.secrets.<username>_password_hash.neededForUsers = true;`

This repo does not ship a one-size-fits-all server `disko.nix` because disk
counts, pool layouts, and mount strategy vary by host. If you want a
declarative Disko layout, copy a similar host's `disko.nix` first and then
adapt its device paths and pool layout to this machine.

Identify the real disk IDs for the target machine:

```sh
ls -l /dev/disk/by-id/ | grep -v part
```

Note the base IDs (without the `-partN` suffix) for each disk:

| Disk | Looks like |
|---|---|
| NVMe SSD | `nvme-WD_BLACK_SN7100_1TB_XXXX...` |
| HDD 1 | `ata-ST12000VN0008-2YS101_XXXX...` |
| HDD 2 | same model, different serial |

If the host uses Disko, update the
`device = "/dev/disk/by-id/...";` entries in
`hosts/servers/<hostname>/disko.nix` to match the IDs from this machine. If
you copied a `disko.nix` from another host, replace all of its existing disk
IDs before running Disko.

The remaining steps assume a Disko-based ZFS install with persisted state under
`/persist`.

---

## Step 6: Generate User Password Hash

```sh
mkpasswd -m sha-512
```

Enter the desired password for the `<username>` user when prompted. Copy the
output hash (starts with `$6$...`). This is used for console login and
persists across reboots via sops.

---

## Step 7: Edit Secrets

If the host secrets file does not exist yet:

```sh
cp /tmp/nix-nexus/secrets/hosts/example.yaml \
  /tmp/nix-nexus/secrets/hosts/<hostname>.yaml
```

```sh
sops /tmp/nix-nexus/secrets/hosts/<hostname>.yaml
```

sops decrypts using `~/.ssh/id_ed25519` directly -- no key conversion needed.

Set the user password and verify all enabled service secrets have real values:

```yaml
<username>_password_hash: "$6$rounds=..."
mqtt_password_homeassistant: "..."
mqtt_password_zigbee2mqtt: "..."
borg_passphrase: "..."
```

Save and exit. sops re-encrypts automatically.

`secrets/users/<username>.yaml` is separate from this: it stays encrypted to
the user's SSH key for `sops-menu` and is not needed during boot.

---

## Step 8: Lock the Flake

```sh
cd /tmp/nix-nexus
git add -A
nix flake lock
git add flake.lock
```

`git add` is required because Nix flakes ignore untracked files in git repos.
`nix flake lock` pins all input versions (fetches from the internet).

---

## Step 9: Set the ZFS Host ID

ZFS embeds the host ID when creating pools. It must match
`networking.hostId` in your host config, or pools will not import after reboot.

Read the configured value from the flake and write it into the live ISO:

```sh
HOST_ID=$(nix eval "/tmp/nix-nexus#nixosConfigurations.<hostname>.config.networking.hostId" --raw)
sudo rm /etc/hostid
sudo zgenhostid "$HOST_ID"
```

Verify:

```sh
hostid    # should print the configured hostId
```

---

## Step 10: Partition Disks with Disko

**WARNING: This destroys all data on the disks referenced by
`hosts/servers/<hostname>/disko.nix`.**

```sh
sudo nix run github:nix-community/disko -- \
  --mode destroy,format,mount \
  /tmp/nix-nexus/hosts/servers/<hostname>/disko.nix
```

This partitions the target disks, creates the declared filesystems and ZFS
pools, and mounts everything under `/mnt`.

Verify:

```sh
mount | grep /mnt
sudo zpool status
```

---

## Step 11: Place the Age Key

```sh
sudo mkdir -p /mnt/persist/var/lib/sops-nix
sudo cp /tmp/host-age-key.txt /mnt/persist/var/lib/sops-nix/key.txt
sudo chmod 600 /mnt/persist/var/lib/sops-nix/key.txt
```

This is the server's identity for decrypting secrets at boot. Without it,
no sops-managed secrets will work after reboot. Store it under `/persist`
because it must be available early during boot.

---

## Step 12: Generate SSH Host Keys

```sh
sudo mkdir -p /mnt/persist/etc/ssh

sudo ssh-keygen -t ed25519 \
  -f /mnt/persist/etc/ssh/ssh_host_ed25519_key -N ""

sudo ssh-keygen -t rsa -b 4096 \
  -f /mnt/persist/etc/ssh/ssh_host_rsa_key -N ""
```

These persist across reboots (via impermanence), giving the server a stable
SSH fingerprint.

---

## Step 13: Create User Home Directory

```sh
sudo mkdir -p /mnt/persist/home/<username>/.ssh
sudo chmod 700 /mnt/persist/home/<username>/.ssh
```

Repeat for each user defined on this host.

---

## Step 14: Install NixOS

```sh
sudo nixos-install \
  --flake /tmp/nix-nexus#<hostname> \
  --no-root-passwd
```

`--no-root-passwd` is safe because root login is disabled in the config.
The `<username>` user's login password is managed by host secrets in sops.

This builds the full system closure -- expect a while on first run.

---

## Step 15: Save Changes and Push a PR

The modified repo in `/tmp/nix-nexus` lives only in the live environment's
RAM and will be lost on reboot. Copy it back to the data USB:

```sh
sudo cp -r /tmp/nix-nexus "$USB/nix-nexus-configured"
sudo umount "$USB"
```

From your workstation, create a branch and open a PR:

```sh
cp -r /path/to/usb/nix-nexus-configured ./nix-nexus
cd nix-nexus

git checkout -b setup/<hostname>

git add hosts/servers/<hostname> flake.nix flake.lock secrets/hosts/<hostname>.yaml
git commit -m "add <hostname> server configuration"

git push -u origin setup/<hostname>
# Open a PR on GitHub. CI will validate the config.
# Once CI passes, merge to main. The server will auto-upgrade at 04:00.
```

> **Note:** Do not commit secrets or private keys. The secrets file is
> already encrypted by sops -- it is safe to commit.

---

## Step 16: Reboot

```sh
sudo reboot
```

Remove the installer USB during reboot (or set the boot disk as first boot
device in BIOS beforehand).

---

## Step 17: Verify

If the host sets `homelab.hostIPv4`, use that address. Otherwise use the IP
address shown on the console or assigned by DHCP.

SSH in:

```sh
ssh <username>@<server-ip>
```

Run checks:

```sh
# System identity
hostnamectl                           # should show "<hostname>"
df -h /                               # tmpfs, ~4 GB

# ZFS
zpool status                          # pools ONLINE

# Persistent state
ls /persist/var/lib/sops-nix/key.txt  # age key present
ls /persist/etc/ssh/                  # SSH host keys present
ls /persist/home/<username>/          # user home exists

# Secrets decrypted at runtime
sudo ls /run/secrets/                 # service secrets (when enabled)

# Optional: user secrets for sops-menu
# These are decrypted on demand with the user's SSH key, not the host age key.
# ssh-add ~/.ssh/id_ed25519            # if the key is local to the host
# sops-menu

# Services (adjust based on which are enabled)
systemctl status caddy                # when any web UI is enabled
systemctl status home-assistant
systemctl status mosquitto
systemctl status zigbee2mqtt

# Network
ip addr show                          # expected LAN address on the server NIC

# Hardware monitoring
sudo dmesg | grep nct6775             # fan controller detected
sensors                               # temp and fan readings
```

---

## Step 18: Network DNS

Browser-facing services are always served through Caddy over HTTPS. If you use
the default `homelab.domain`, clients need to resolve `*.<hostname>.lan`
hostnames to the server's IP. If you override `homelab.domain`, substitute
that custom domain in the examples below.

**Quick option** -- add to `/etc/hosts` on each client:

```text
<server-ip>  <hostname>.lan
<server-ip>  hass.<hostname>.lan
<server-ip>  z2m.<hostname>.lan
<server-ip>  coolercontrol.<hostname>.lan
```

**Better option** -- configure a local DNS server (Pi-hole, Unbound, etc.)
with records for `<hostname>.lan` and the service subdomains you expose through
Caddy.

If `homelab.pihole.enable = true`, Pi-hole will serve `<hostname>.lan` plus
Caddy-backed service aliases like `hass.<hostname>.lan`, `z2m.<hostname>.lan`,
`coolercontrol.<hostname>.lan`, and `pihole.<hostname>.lan` automatically.
Point your router's LAN DNS server setting at the server IP so clients
actually query Pi-hole.

---

## Step 19: Configure Services

### Home Assistant

1. Open `https://hass.<hostname>.lan` (accept the self-signed cert)
2. Complete the onboarding wizard
3. Add MQTT: Settings > Devices & Services > Add Integration > MQTT
   Broker: `localhost`, Port: `1883`
   Username: `homeassistant`
   Password: the `mqtt_password_homeassistant` value from secrets

### Zigbee2MQTT

1. Open `https://z2m.<hostname>.lan`
2. The Sonoff adapter should appear at `/dev/zigbee`
3. Click "Permit Join" to pair devices (auto-discover in Home Assistant via MQTT)

### Pi-hole

1. Open `https://pihole.<hostname>.lan`
2. Point your router's LAN DNS server at the server IP so clients use Pi-hole
3. Store the dashboard password hash in the `pihole_web_password_hash` secret

### CoolerControl

1. Open `https://coolercontrol.<hostname>.lan`
2. Configure fan curves using nct6775 sensor readings
3. Cross-reference with `sensors` output

### Backups

Trigger a manual run to confirm BorgBackup works:

```sh
sudo systemctl start borgbackup-job-<hostname>.service
sudo journalctl -u borgbackup-job-<hostname>.service -f
sudo borg-job-<hostname> list
sudo borg-job-<hostname> list ::<hostname>-YYYY-MM-DDTHH:MM:SS
```

After the first successful archive, test at least a file-level restore using
the restore runbook in `RESTORE.md`.

---

## Step 20: Final Checks

```sh
# Firewall -- SSH, HTTP, HTTPS, and DNS when Pi-hole is enabled
sudo nft list ruleset

# Auto-upgrade timer -- next trigger should be 04:00
systemctl list-timers nixos-upgrade.timer

# Test a clean reboot
sudo reboot
```

After reboot, confirm:

- All services are running
- `/` is a fresh empty tmpfs
- Persistent state survived (`/var/lib/hass`, `/var/lib/zigbee2mqtt`, etc.)
- Secrets are decrypted
- User password still works

---

## Developer Setup

To install pre-commit hooks for this repo on your workstation:

```sh
cd nix-nexus
direnv allow    # installs hooks via devShell automatically
```

Or without direnv:

```sh
nix develop     # enters the devShell, which installs hooks on entry
```

Hooks run on every `git commit`:

- **nixfmt-rfc-style** -- formats staged `.nix` files
- **check-merge-conflicts** -- catches leftover conflict markers
- **detect-private-keys** -- prevents committing private keys

Local validation:

```sh
nix fmt                                  # format all Nix files
nix flake check                          # validate flake schema
nix eval .#nixosConfigurations.<hostname>.config.system.build.toplevel --apply 'x: "ok"'
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Secrets not decrypting | Age key missing, mismatched, or mounted too late | Verify `/persist/var/lib/sops-nix/key.txt` exists, `sops.age.keyFile` points there, and its public key matches `.sops.yaml`; re-encrypt with `sops updatekeys` if needed |
| ZFS pool won't import | hostId mismatch (step 9 skipped) | Boot from USB, set the hostId, destroy and recreate pools with disko |
| No network after boot | NIC name doesn't match `en*` | Check `ip link`; update `matchConfig.Name` in `hosts/servers/<hostname>/default.nix` |
| Zigbee adapter not found | USB stick missing or udev mismatch | Check `ls -l /dev/zigbee` and `lsusb` for CP2102N (`10c4:ea60`) |
| Fan sensors missing | nct6775 chip ID mismatch | Run `sensors-detect`, update `force_id` in `hardware-configuration.nix` |
| State lost after reboot | Path not in impermanence | Add it to `modules/nixos/host/impermanence.nix` or the host's `default.nix` |
| Can't log in after reboot | `<username>_password_hash` missing, or the age key was unavailable before user creation | Add the password hash per steps 6-7 and check the journal for `cannot read keyfile` / `password file ... does not exist` |
| SSH fingerprint changes | Host keys not persisted | Regenerate per step 12 |
| `nixos-install` fails to evaluate | `flake.lock` missing or files not staged | Run `git add -A && nix flake lock && git add flake.lock` |
| `sops` can't decrypt | Wrong SSH key or age key mismatch | Verify `~/.ssh/id_ed25519` is in place and its public key is listed in `.sops.yaml` |
| `sops-menu` can't decrypt user secrets | SSH key not loaded into the user's agent | Run `ssh-add ~/.ssh/id_ed25519` locally, or use SSH agent forwarding when connecting to a remote host |
| Pre-commit hooks not running | Hooks not installed | Run `direnv allow` or `nix develop` in the repo root |
| CI fails on PR | Formatting or eval error | Run `nix fmt` then `nix eval .#nixosConfigurations.<hostname>...` locally to debug |
