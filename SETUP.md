# Home Server Setup Guide

Step-by-step installation from a graphical NixOS live USB. Everything
happens on the server itself -- no separate workstation needed.

## What You Need

Two USB drives plugged into the server:

1. **Installer USB** -- Graphical NixOS 25.11 ISO (GNOME or Plasma), booted.
   Download from https://nixos.org/download (select the graphical live ISO).

2. **Data USB** -- containing:
   - A clone of this repository
   - The `heikov` SSH private key (`id_ed25519`)
   - The home-server age key (`key.txt`) and its public key

**Hardware assembled and connected:**
- ASRock B650M Pro RS motherboard with AMD Ryzen 5 7600
- 48 GB DDR5 RAM
- WD_BLACK SN7100 1 TB NVMe in the M.2 slot
- 2x Seagate IronWolf 12 TB HDDs via SATA
- Sonoff Zigbee 3.0 Plus USB stick
- Ethernet cable to Fritz!Box (internet required)

---

## Step 1: Boot and Open a Terminal

Boot from the installer USB (enter BIOS with DEL key, set USB as first
boot device). Once the graphical desktop loads, open a terminal
(search "Terminal" in the activities menu).

Verify internet:
```sh
ping -c 3 1.1.1.1
```

If there is no connectivity, check that the Ethernet cable is plugged in
and use the desktop's network settings to configure it.

Enable flakes for the session:
```sh
export NIX_CONFIG="experimental-features = nix-command flakes"
```

---

## Step 2: Locate the Data USB

The graphical desktop auto-mounts USB drives under `/run/media/nixos/`.
Find your data USB:

```sh
ls /run/media/nixos/
```

Set a variable for convenience (replace `<label>` with the actual
directory name shown above):

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
cp $USB/key.txt /tmp/server-age-key.txt
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

Note down three IDs (the base names, not the `-partN` suffixed ones):

| Disk | Looks like |
|---|---|
| NVMe SSD | `nvme-WD_BLACK_SN7100_1TB_XXXX...` |
| HDD 1 | `ata-ST12000VN0008-2YS101_XXXX...` |
| HDD 2 | same model, different serial |

---

## Step 6: Edit Disk IDs in disko.nix

```sh
vim /tmp/nix-nexus/hosts/home-server/disko.nix
```

Replace the three placeholders with the disk IDs from step 5:

| Placeholder | Replace with |
|---|---|
| `PLACEHOLDER_SSD` | NVMe SSD disk ID |
| `PLACEHOLDER_HDD1` | First HDD disk ID |
| `PLACEHOLDER_HDD2` | Second HDD disk ID |

Save and exit (:wq).

---

## Step 7: Generate User Password Hash

```sh
mkpasswd -m sha-512
```

Enter your desired password for the `heikov` user when prompted. Copy
the output hash (starts with `$6$...`). This password is used for
console login and persists across reboots via sops.

---

## Step 8: Edit Secrets

```sh
sops /tmp/nix-nexus/secrets/hosts/home-server.yaml
```

This decrypts and opens the secrets file. sops uses the SSH key at
`~/.ssh/id_ed25519` directly -- no conversion needed.

Add the user password:

```yaml
heikov_password_hash: "$6$rounds=..."
```

Also verify these existing secrets contain real values (not
placeholders):

- `mqtt_password_homeassistant`
- `mqtt_password_zigbee2mqtt`
- `borg_passphrase`

Save and exit. sops re-encrypts the file automatically.

---

## Step 9: Generate the Flake Lock File

```sh
cd /tmp/nix-nexus
git add -A
nix flake lock
git add flake.lock
```

`git add` is required because nix flakes ignore untracked files in git
repos. `nix flake lock` pins all input versions (downloads from the
internet).

---

## Step 10: Set the ZFS Host ID

ZFS embeds the host ID when creating pools. It must match
`networking.hostId` from `hardware-configuration.nix` (value
`163dd8b3`), or pools will not import after reboot.

The graphical live USB has a read-only `/etc`. Layer a writable overlay
on top, then write the hostid:

```sh
sudo rm /etc/hostid
sudo zgenhostid 163dd8b3
```

Verify:
```sh
hostid
```

Should print `163dd8b3`.

---

## Step 11: Partition Disks with Disko

**WARNING: This destroys all data on the NVMe SSD and both HDDs.**

```sh
sudo nix run github:nix-community/disko -- \
  --mode destroy,format,mount \
  /tmp/nix-nexus/hosts/home-server/disko.nix
```

This will:
- Partition the NVMe (ESP, swap, L2ARC, rpool)
- Partition both HDDs
- Create ZFS pool `rpool` on the NVMe with datasets: nix, persist,
  postgres
- Create ZFS pool `tank` as HDD mirror with SSD L2ARC and datasets:
  safe, data, media, backups
- Mount everything under `/mnt`

Verify:
```sh
mount | grep /mnt
sudo zpool status rpool    # single SSD vdev, ONLINE
sudo zpool status tank     # mirror of 2 HDDs + cache, ONLINE
ls /mnt/persist
sudo ls /mnt/boot
```

---

## Step 12: Place the Age Key

```sh
sudo mkdir -p /mnt/persist/var/lib/sops-nix
sudo cp /tmp/server-age-key.txt /mnt/persist/var/lib/sops-nix/key.txt
sudo chmod 600 /mnt/persist/var/lib/sops-nix/key.txt
```

This is the server's identity for decrypting secrets. Without it, no
sops-managed secrets will work after boot.

---

## Step 13: Generate SSH Host Keys

```sh
sudo mkdir -p /mnt/persist/etc/ssh

sudo ssh-keygen -t ed25519 \
  -f /mnt/persist/etc/ssh/ssh_host_ed25519_key -N ""

sudo ssh-keygen -t rsa -b 4096 \
  -f /mnt/persist/etc/ssh/ssh_host_rsa_key -N ""
```

These persist across reboots via impermanence, giving the server a
stable SSH fingerprint.

---

## Step 14: Create the User Home Directory

```sh
sudo mkdir -p /mnt/persist/home/heikov/.ssh
sudo chmod 700 /mnt/persist/home/heikov/.ssh
```

---

## Step 15: Install NixOS

```sh
sudo nixos-install --flake /tmp/nix-nexus#home-server --no-root-passwd
```

- `--no-root-passwd` is safe because root login is disabled in the
  config. The heikov user's password is managed by sops.
- This builds and installs the entire system closure. Expect it to take
  a while (it downloads and compiles packages).

---

## Step 16: Save Your Changes

The modified repo in `/tmp/nix-nexus` will be lost when you reboot
(it lives on the live environment's RAM). Copy it back to the data USB:

```sh
sudo cp -r /tmp/nix-nexus $USB/nix-nexus-configured
sudo umount $USB
```

Later, from another machine, push the changes to GitHub so the server's
auto-upgrade timer can pull them:

```sh
cd nix-nexus-configured
git add -A
git commit -m "configure disk IDs, server age key, user password, and lock flake inputs"
git push
```

---

## Step 17: Reboot

```sh
sudo reboot
```

Remove the installer USB during reboot (or set NVMe as first boot
device in BIOS beforehand).

---

## Step 18: Verify

The server gets its IP via DHCP. Find it through your router's admin
page, or use a keyboard and monitor on the console to run `ip a`.

SSH in from another machine on the same network:
```sh
ssh heikov@<server-ip>
```

Use the password from step 7, or SSH key auth if the heikov key is on
your client machine.

Run checks:
```sh
# System identity
hostnamectl                           # should show "home-server"
df -h /                               # tmpfs, ~4 GB

# ZFS
zpool status                          # rpool and tank both ONLINE

# Persistent state
ls /persist/var/lib/sops-nix/key.txt  # age key present
ls /persist/etc/ssh/                  # SSH host keys present
ls /persist/home/heikov/              # user home exists

# Secrets decrypted at runtime
sudo ls /run/secrets/                 # heikov_password_hash,
                                      # mqtt_password_homeassistant,
                                      # mqtt_password_zigbee2mqtt,
                                      # borg_passphrase

# Services
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

The server currently uses DHCP. Create a static DHCP reservation on the
Fritz!Box so the IP stays stable, then point DNS at it.

Clients need to resolve `*.home-server.lan` to the server's IP.

**Quick option** -- add to `/etc/hosts` on each client:
```
<server-ip>  home-server.lan
<server-ip>  hass.home-server.lan
<server-ip>  z2m.home-server.lan
<server-ip>  coolercontrol.home-server.lan
```

**Better option** -- configure a local DNS server (Pi-hole, Unbound,
etc.) with a wildcard A record for `*.home-server.lan`.

When ready for a static IP, uncomment the `systemd.network` block in
`hosts/home-server/default.nix` and set `networking.useDHCP = false`.

---

## Step 20: Configure Services

### Home Assistant

1. Open `https://hass.home-server.lan` (accept the self-signed cert)
2. Complete the onboarding wizard (create account, set timezone/location)
3. Add MQTT: Settings > Devices & Services > Add Integration > MQTT
   - Broker: `localhost`, Port: `1883`
   - Username: `homeassistant`
   - Password: the `mqtt_password_homeassistant` value from secrets

### Zigbee2MQTT

1. Open `https://z2m.home-server.lan`
2. The Sonoff adapter should show at `/dev/zigbee`
3. Click "Permit Join" to pair devices (paired devices auto-discover in
   Home Assistant via MQTT)

### CoolerControl

1. Open `https://coolercontrol.home-server.lan`
2. Configure fan curves using nct6775 sensor readings
3. Cross-reference with `sensors` output

### Backups

Trigger a manual run to confirm BorgBackup works:
```sh
sudo systemctl start borgbackup-job-home-server.service
sudo journalctl -u borgbackup-job-home-server.service -f
sudo borg list /tank/backups/borg
```

---

## Step 21: Final Checks

### Firewall
```sh
sudo nft list ruleset
```
Only TCP 22 (SSH), 80 (HTTP), and 443 (HTTPS) should be open. MQTT
(1883) is localhost-only.

### Auto-upgrade timer
```sh
systemctl list-timers nixos-upgrade.timer
```
Should show the next trigger at 04:00.

### Test a clean reboot
```sh
sudo reboot
```

After it comes back, confirm:
- All services are running
- `/` is a fresh empty tmpfs
- Persistent state survived (`/var/lib/hass`, `/var/lib/zigbee2mqtt`,
  etc.)
- Secrets are decrypted (`/run/secrets/`)
- User password still works

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Secrets not decrypting | Age key missing or mismatched | Verify `/persist/var/lib/sops-nix/key.txt` exists and its public key matches `.sops.yaml`; re-encrypt with `sops updatekeys` |
| ZFS pool won't import | hostId mismatch (step 10 skipped) | Boot from USB, set the hostId, destroy and recreate pools with disko |
| No network after boot | NIC name doesn't match `en*` | Check `ip link`; update `matchConfig.Name` in `hosts/home-server/default.nix` |
| Zigbee adapter not found | USB stick missing or udev mismatch | Check `ls -l /dev/zigbee` and `lsusb` for CP2102N (`10c4:ea60`) |
| Fan sensors missing | nct6775 chip ID mismatch | Run `sensors-detect`, update `force_id` in `hardware-configuration.nix` |
| State lost after reboot | Path not in impermanence | Add it to `modules/nixos/impermanence.nix` |
| Can't log in after reboot | `heikov_password_hash` missing from secrets | Add it per steps 7-8, push, rebuild |
| SSH fingerprint changes | Host keys not in `/persist/etc/ssh/` | Regenerate per step 13 |
| `nixos-install` fails to evaluate | `flake.lock` missing or files not staged | Run `git add -A && nix flake lock && git add flake.lock` |
| `sops` can't decrypt | Wrong SSH key or age key mismatch | Verify `~/.ssh/id_ed25519` is in place and its public key is listed in `.sops.yaml` |
