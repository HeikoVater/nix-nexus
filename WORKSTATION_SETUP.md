# Workstation Setup Guide

Step-by-step installation of a workstation host from a graphical NixOS live
USB. This guide is for hosts under `hosts/workstations/`.

Server hosts use `SERVER_SETUP.md` instead. WSL hosts do not follow this live
USB install flow.

This guide assumes a conventional persistent root filesystem and the simpler
`hosts/workstations/example/` pattern with a generated
`hardware-configuration.nix`. Existing hosts such as `desktop` and `laptop`
use a more customized split (`hardware.nix`, `disks.nix`, optional
`facter.json`), but that is not required for new workstation hosts.

## What You Need

Two USB drives plugged into the workstation:

1. **Installer USB** -- Graphical NixOS 25.11 ISO (GNOME or Plasma), booted.
   Download from https://nixos.org/download.
2. **Data USB** -- containing:
   - A clone of this repository
   - Your SSH private key (`id_ed25519`) -- needed to edit sops files and later
     decrypt `sops-menu` user secrets
   - The host's age key (`key.txt`) -- needed if this workstation uses host
     secrets via `sops-nix`

**Internet required**.

---

## Step 1: Boot and Open a Terminal

Boot from the installer USB. Once the graphical desktop loads, open a
terminal.

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

The graphical desktop usually auto-mounts USB drives under
`/run/media/nixos/`.

```sh
ls /run/media/nixos/
USB=/run/media/nixos/<label>
```

If auto-mount did not work:

```sh
lsblk
sudo mkdir -p /tmp/usb
sudo mount /dev/sdX1 /tmp/usb    # replace sdX1 with your device
USB=/tmp/usb
```

---

## Step 3: Copy the Repo and Keys

```sh
cp -r "$USB/nix-nexus" /tmp/nix-nexus
mkdir -p ~/.ssh
cp "$USB/id_ed25519" ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519
```

If this host uses `host.secrets.enable = true`, also copy the host age key:

```sh
cp "$USB/key.txt" /tmp/host-age-key.txt
```

Adjust paths to match your USB layout.

---

## Step 4: Enter a Tool Shell

```sh
nix-shell -p sops age mkpasswd git
export NIX_CONFIG="experimental-features = nix-command flakes"
export EDITOR=vim
```

Stay in this shell for the remaining steps.

---

## Step 5: Prepare the Host Config

For a brand new workstation host, start from the example directory:

```sh
cp -r /tmp/nix-nexus/hosts/workstations/example \
  /tmp/nix-nexus/hosts/workstations/<hostname>
```

Then update:

1. `hosts/workstations/<hostname>/default.nix`
2. `flake.nix` -- add the host under `nixosConfigurations`
3. `secrets/hosts/<hostname>.yaml` if the host uses `sops-nix`

At minimum, make sure the host config sets:

- `networking.hostName = hostname;`
- the correct Home Manager import (`home/<username>/workstation.nix` or
  `headless.nix`)
- the user account definition
- `sops.defaultSopsFile = ../../../secrets/hosts/<hostname>.yaml;` when using
  host secrets

---

## Step 6: Partition and Mount the Target Disks

This repo does not use Disko for workstations. Partition the drive with the
layout you want, then mount the target system under `/mnt`.

Typical mounting flow:

```sh
lsblk -f
sudo mount /dev/disk/by-uuid/<root-uuid> /mnt
sudo mkdir -p /mnt/boot
sudo mount /dev/disk/by-uuid/<boot-uuid> /mnt/boot
```

If you use LUKS, open the encrypted volume before mounting it.

---

## Step 7: Generate Hardware Configuration

```sh
sudo nixos-generate-config --root /mnt
cp /mnt/etc/nixos/hardware-configuration.nix \
  /tmp/nix-nexus/hosts/workstations/<hostname>/hardware-configuration.nix
```

The example workstation host already imports `./hardware-configuration.nix`.

If you intentionally follow the more customized `desktop` or `laptop` pattern,
update `hardware.nix`, `disks.nix`, and optional `facter.json` instead of
using the simple generated file directly.

---

## Step 8: Generate the User Password Hash

```sh
mkpasswd -m sha-512
```

Copy the output hash (starts with `$6$...`). This is the login password for the
declarative user account.

---

## Step 9: Edit Host Secrets

If this workstation uses host secrets:

```sh
sops /tmp/nix-nexus/secrets/hosts/<hostname>.yaml
```

Set the user password hash and any host-specific secrets required by enabled
modules. Common examples:

```yaml
<username>_password_hash: "$6$rounds=..."
crypto-tracker-api-key: "..."
smb-credentials: |
  username=...
  password=...
```

`secrets/users/<username>.yaml` is separate from this. It stays encrypted to
the user's SSH key for `sops-menu` and is not needed during boot.

---

## Step 10: Lock the Flake

```sh
cd /tmp/nix-nexus
git add -A
nix flake lock
git add flake.lock
```

`git add` is required because Nix flakes ignore untracked files in git repos.

---

## Step 11: Install the Host Age Key

If the workstation uses `sops-nix`, place the host age key where the host will
expect it:

```sh
sudo mkdir -p /mnt/root/.config/sops/age
sudo cp /tmp/host-age-key.txt /mnt/root/.config/sops/age/keys.txt
sudo chmod 600 /mnt/root/.config/sops/age/keys.txt
```

Skip this step for secret-free hosts.

If OpenSSH is enabled on the workstation, also generate SSH host keys in the
target system before installation:

```sh
sudo ssh-keygen -A -f /mnt
```

This creates the workstation's SSH server identity under `/mnt/etc/ssh/` so
activation does not fail with missing host key errors.
---

## Step 12: Install NixOS

```sh
sudo nixos-install \
  --flake /tmp/nix-nexus#<hostname> \
  --no-root-passwd
```

`--no-root-passwd` is fine when root login is disabled and the declarative user
password comes from host secrets.

---

## Step 13: Save Changes and Open a PR

The modified repo in `/tmp/nix-nexus` lives only in the live environment.
Copy it back to the data USB:

```sh
sudo cp -r /tmp/nix-nexus "$USB/nix-nexus-configured"
sudo umount "$USB"
```

From another machine, create a branch and open a PR:

```sh
cp -r /path/to/usb/nix-nexus-configured ./nix-nexus
cd nix-nexus

git checkout -b setup/<hostname>
git add -A
git commit -m "configure <hostname>: add workstation host"
git push -u origin setup/<hostname>
```

Do not commit private keys. Host secret files are safe to commit because they
are already encrypted with sops.

---

## Step 14: Reboot

```sh
sudo reboot
```

Remove the installer USB during reboot.

---

## Step 15: Verify

SSH in or log in locally and run:

```sh
# System identity
hostnamectl

# Secrets (when enabled)
sudo ls /run/secrets/
sudo ls /root/.config/sops/age/keys.txt

# SSH host keys
sudo ls /etc/ssh/ssh_host_*

# Desktop / display manager
systemctl status display-manager

# Network
ip addr show
nmcli general status

# Optional workstation features
mount | grep -i cifs                 # when mount-nas is enabled
systemctl status sunshine            # when enabled
systemctl status comfyui             # when enabled
```

If the host enables `sops-menu`, the user secrets still decrypt with the user's
SSH key, not the host age key:

```sh
ssh-add ~/.ssh/id_ed25519
sops-menu
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| OpenSSH activation fails with missing host key errors | SSH host keys were not generated in the target system before install | From the live installer, run `sudo ssh-keygen -A -f /mnt`, then rerun `nixos-install` |
| Secrets not decrypting at boot | Host age key missing or wrong path | Verify `/root/.config/sops/age/keys.txt` exists and matches `.sops.yaml` |
| Login fails for the declarative user | `<username>_password_hash` missing or wrong | Re-check `secrets/hosts/<hostname>.yaml` and reinstall |
| No network after boot | Wrong NetworkManager or NIC config | Check `nmcli`, `ip link`, and the host's networking module settings |
| `sops-menu` cannot decrypt | User SSH key not loaded into the agent | Run `ssh-add ~/.ssh/id_ed25519` or use agent forwarding |
| `nixos-install` fails to evaluate | `flake.lock` missing or files not staged | Run `git add -A && nix flake lock && git add flake.lock` |
