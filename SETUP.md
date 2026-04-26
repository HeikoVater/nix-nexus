# Setup Guide

Step-by-step installation of a new host from a graphical NixOS live USB.
Everything happens on the server itself -- no separate workstation needed for
the initial install. Changes are then pushed as a PR from your workstation.

This guide uses `mu` and `heikov` as concrete examples throughout. Replace
them with your actual hostname and username where indicated.

## What You Need

Two USB drives plugged into the server:

1. **Installer USB** -- Graphical NixOS 25.11 ISO (GNOME or Plasma), booted.
   Download from https://nixos.org/download (select the graphical live ISO).

2. **Data USB** -- containing:
   - A clone of this repository
   - The `heikov` SSH private key (`id_ed25519`) -- needed for sops decryption
   - The host's age key (`key.txt`) and its public key

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
cp -r $USB/nix-nexus /tmp/nix-nexus
cp $USB/key.txt /tmp/host-age-key.txt
mkdir -p ~/.ssh
cp $USB/id_ed25519 ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519
```

Adjust source paths to match your USB layout.

---

## Step 4: Enter a Tool Shell

```sh
nix-shell -p sops age mkpasswd
export NIX_CONFIG="experimental-features = nix-command flakes"
export EDITOR=vim
```

Stay in this shell for all remaining steps.

---

## Step 5: Identify Disk IDs

```sh
ls -l /dev/disk/by-id/ | grep -v part
```

Note the base IDs (without the `-partN` suffix) for each disk:

| Disk | Looks like |
|---|---|
| NVMe SSD | `nvme-WD_BLACK_SN7100_1TB_XXXX...` |
| HDD 1 | `ata-ST12000VN0008-2YS101_XXXX...` |
| HDD 2 | same model, different serial |

---

## Step 6: Edit Disk IDs in disko.nix

```sh
vim /tmp/nix-nexus/hosts/mu/disko.nix
```

Replace the three placeholders with the disk IDs from step 5:

| Placeholder | Replace with |
|---|---|
| `PLACEHOLDER_SSD` | NVMe SSD disk ID |
| `PLACEHOLDER_HDD1` | First HDD disk ID |
| `PLACEHOLDER_HDD2` | Second HDD disk ID |

Save and exit (`:wq`).

---

## Step 7: Generate User Password Hash

```sh
mkpasswd -m sha-512
```

Enter the desired password for the `heikov` user when prompted. Copy the
output hash (starts with `$6$...`). This is used for console login and
persists across reboots via sops.

---

## Step 8: Edit Secrets

```sh
sops /tmp/nix-nexus/secrets/hosts/mu.yaml
```

sops decrypts using `~/.ssh/id_ed25519` directly -- no key conversion needed.

Set the user password and verify all service secrets have real values:

```yaml
heikov_password_hash: "$6$rounds=..."
mqtt_password_homeassistant: "..."
mqtt_password_zigbee2mqtt: "..."
borg_passphrase: "..."
```

Save and exit. sops re-encrypts automatically.

---

## Step 9: Lock the Flake

```sh
cd /tmp/nix-nexus
git add -A
nix flake lock
git add flake.lock
```

`git add` is required because Nix flakes ignore untracked files in git repos.
`nix flake lock` pins all input versions (fetches from the internet).

---

## Step 10: Set the ZFS Host ID

ZFS embeds the host ID when creating pools. It must match
`networking.hostId` in `hardware-configuration.nix` (value `163dd8b3`), or
pools will not import after reboot.

The live ISO has a read-only `/etc`. Write to it with an overlay:

```sh
sudo rm /etc/hostid
sudo zgenhostid 163dd8b3
```

Verify:
```sh
hostid    # should print 163dd8b3
```

---

## Step 11: Partition Disks with Disko

**WARNING: This destroys all data on the NVMe SSD and both HDDs.**

```sh
sudo nix run github:nix-community/disko -- \
  --mode destroy,format,mount \
  /tmp/nix-nexus/hosts/mu/disko.nix
```

This partitions the NVMe (ESP, swap, L2ARC, rpool) and both HDDs, creates
ZFS pools `rpool` and `tank`, and mounts everything under `/mnt`.

Verify:
```sh
mount | grep /mnt
sudo zpool status rpool    # single SSD vdev, ONLINE
sudo zpool status tank     # mirror of 2 HDDs + cache, ONLINE
```

---

## Step 12: Place the Age Key

```sh
sudo mkdir -p /mnt/persist/var/lib/sops-nix
sudo cp /tmp/host-age-key.txt /mnt/persist/var/lib/sops-nix/key.txt
sudo chmod 600 /mnt/persist/var/lib/sops-nix/key.txt
```

This is the server's identity for decrypting secrets at boot. Without it,
no sops-managed secrets will work after reboot. Store it under `/persist`
because it must be available early during boot.

---

## Step 13: Generate SSH Host Keys

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

## Step 14: Create User Home Directory

```sh
sudo mkdir -p /mnt/persist/home/heikov/.ssh
sudo chmod 700 /mnt/persist/home/heikov/.ssh
```

Repeat for each user defined on this host.

---

## Step 15: Install NixOS

```sh
sudo nixos-install \
  --flake /tmp/nix-nexus#mu \
  --no-root-passwd
```

`--no-root-passwd` is safe because root login is disabled in the config.
The `heikov` user's password is managed by sops.

This builds the full system closure -- expect a while on first run.

---

## Step 16: Save Changes and Push a PR

The modified repo in `/tmp/nix-nexus` lives only in the live environment's
RAM and will be lost on reboot. Copy it back to the data USB:

```sh
sudo cp -r /tmp/nix-nexus $USB/nix-nexus-configured
sudo umount $USB
```

From your workstation, create a branch and open a PR:

```sh
cp -r /path/to/usb/nix-nexus-configured ./nix-nexus
cd nix-nexus

git checkout -b setup/mu

git add hosts/mu/disko.nix flake.lock
git commit -m "configure mu: disk IDs and flake lock"

git push -u origin setup/mu
# Open a PR on GitHub. CI will validate the config.
# Once CI passes, merge to main. The server will auto-upgrade at 04:00.
```

> **Note:** Do not commit secrets or private keys. The secrets file is
> already encrypted by sops -- it is safe to commit.

---

## Step 17: Reboot

```sh
sudo reboot
```

Remove the installer USB during reboot (or set the NVMe as first boot device
in BIOS beforehand).

---

## Step 18: Verify

The server gets its IP via DHCP. Find it via your router's admin page, or
attach a keyboard and monitor and run `ip a`.

SSH in:
```sh
ssh heikov@<server-ip>
```

Run checks:
```sh
# System identity
hostnamectl                           # should show "mu"
df -h /                               # tmpfs, ~4 GB

# ZFS
zpool status                          # rpool and tank both ONLINE

# Persistent state
ls /persist/var/lib/sops-nix/key.txt  # age key present
ls /persist/etc/ssh/                  # SSH host keys present
ls /persist/home/heikov/              # user home exists

# Secrets decrypted at runtime
sudo ls /run/secrets/                 # mqtt_*, borg_passphrase (when enabled)

# Services (adjust based on which are enabled)
systemctl status caddy
systemctl status home-assistant
systemctl status mosquitto
systemctl status zigbee2mqtt

# Network
ip addr show                          # DHCP address on en* interface

# Hardware monitoring
sudo dmesg | grep nct6775             # fan controller detected
sensors                               # temp and fan readings
```

---

## Step 19: Network DNS

The server uses DHCP by default. Create a static DHCP reservation on your
router so the IP stays stable, then configure DNS.

Clients need to resolve `*.mu.lan` to the server's IP.

**Quick option** -- add to `/etc/hosts` on each client:
```
<server-ip>  mu.lan
<server-ip>  hass.mu.lan
<server-ip>  z2m.mu.lan
<server-ip>  coolercontrol.mu.lan
```

**Better option** -- configure a local DNS server (Pi-hole, Unbound, etc.)
with a wildcard A record for `*.mu.lan`.

When ready for a static IP, uncomment the `systemd.network` block in
`hosts/mu/default.nix` and set `networking.useDHCP = false`.

---

## Step 20: Configure Services

### Home Assistant

1. Open `https://hass.mu.lan` (accept the self-signed cert)
2. Complete the onboarding wizard
3. Add MQTT: Settings > Devices & Services > Add Integration > MQTT
   - Broker: `localhost`, Port: `1883`
   - Username: `homeassistant`
   - Password: the `mqtt_password_homeassistant` value from secrets

### Zigbee2MQTT

1. Open `https://z2m.mu.lan`
2. The Sonoff adapter should appear at `/dev/zigbee`
3. Click "Permit Join" to pair devices (auto-discover in Home Assistant via MQTT)

### CoolerControl

1. Open `https://coolercontrol.mu.lan`
2. Configure fan curves using nct6775 sensor readings
3. Cross-reference with `sensors` output

### Backups

Trigger a manual run to confirm BorgBackup works:
```sh
sudo systemctl start borgbackup-job-mu.service
sudo journalctl -u borgbackup-job-mu.service -f
sudo borg list /tank/backups/borg
```

---

## Step 21: Final Checks

```sh
# Firewall -- only SSH, HTTP, HTTPS should be open
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
- **detect-private-key** -- prevents committing private keys

Local validation:
```sh
nix fmt                                  # format all Nix files
nix flake check                          # validate flake schema
nix eval .#nixosConfigurations.<host>.config.system.build.toplevel --apply 'x: "ok"'
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Secrets not decrypting | Age key missing, mismatched, or mounted too late | Verify `/persist/var/lib/sops-nix/key.txt` exists, `sops.age.keyFile` points there, and its public key matches `.sops.yaml`; re-encrypt with `sops updatekeys` if needed |
| ZFS pool won't import | hostId mismatch (step 10 skipped) | Boot from USB, set the hostId, destroy and recreate pools with disko |
| No network after boot | NIC name doesn't match `en*` | Check `ip link`; update `matchConfig.Name` in `hosts/mu/default.nix` |
| Zigbee adapter not found | USB stick missing or udev mismatch | Check `ls -l /dev/zigbee` and `lsusb` for CP2102N (`10c4:ea60`) |
| Fan sensors missing | nct6775 chip ID mismatch | Run `sensors-detect`, update `force_id` in `hardware-configuration.nix` |
| State lost after reboot | Path not in impermanence | Add it to `modules/nixos/impermanence.nix` or the host's `default.nix` |
| Can't log in after reboot | `<username>_password_hash` missing, or the age key was unavailable before user creation | Add the password hash per steps 7-8 and check the journal for `cannot read keyfile` / `password file ... does not exist` |
| SSH fingerprint changes | Host keys not persisted | Regenerate per step 13 |
| `nixos-install` fails to evaluate | `flake.lock` missing or files not staged | Run `git add -A && nix flake lock && git add flake.lock` |
| `sops` can't decrypt | Wrong SSH key or age key mismatch | Verify `~/.ssh/id_ed25519` is in place and its public key is listed in `.sops.yaml` |
| Pre-commit hooks not running | Hooks not installed | Run `direnv allow` or `nix develop` in the repo root |
| CI fails on PR | Formatting or eval error | Run `nix fmt` then `nix eval .#nixosConfigurations.<host>...` locally to debug |
