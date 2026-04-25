# ═══════════════════════════════════════════════════════════════════
#  Impermanence — Persistent State on Ephemeral Root
# ═══════════════════════════════════════════════════════════════════
#  Root (/) is tmpfs and wiped every reboot. This module declares
#  which system state, service data, and user files survive reboots
#  by bind-mounting them from /persist (rpool/persist on the SSD).
#
#  Adding a new service? If it stores state under /var/lib/<name>,
#  add it to the conditional directories block below.
# ─────────────────────────────────────────────────────────────────
{ config, lib, ... }:

let
  ha = config.homelab.home-assistant;
  z2m = config.homelab.zigbee2mqtt;
  mqtt = config.homelab.mosquitto;
  cc = config.homelab.coolercontrol;
in
{
  environment.persistence."/persist" = {
    hideMounts = true;

    # ─── System State ───────────────────────────────────────────
    directories =
      [
        "/var/log" # systemd journal and service logs
        "/var/lib/nixos" # NixOS state (uid/gid map, etc.)
        "/var/lib/systemd/coredump" # crash dumps for debugging
        "/var/lib/systemd/timers" # persistent timer state (backup/upgrade schedules)
        "/var/lib/sops-nix" # age decryption key — CRITICAL for secrets
        "/etc/zfs" # ZFS cache files (avoids "device busy" on atomic updates)
      ]
      # ─── Service State (conditional) ──────────────────────────
      # Only persist directories for services that are enabled.
      ++ (lib.optional ha.enable "/var/lib/hass")
      ++ (lib.optional z2m.enable "/var/lib/zigbee2mqtt")
      ++ (lib.optional mqtt.enable "/var/lib/mosquitto")
      ++ (lib.optional cc.enable "/etc/coolercontrol");

    # ─── System Files ───────────────────────────────────────────
    files = [
      "/etc/machine-id" # stable machine identity for systemd/journal
    ];

    # ─── User State ─────────────────────────────────────────────
    # Persist the heikov user's entire home directory. Individual
    # users can be added here as the server grows.
    users.heikov = {
      directories = [
        { directory = ".ssh"; mode = "0700"; }
      ];
    };
  };

  # ─── SSH Host Keys ──────────────────────────────────────────
  # Store host keys directly under /persist rather than relying
  # on bind-mounting /etc/ssh. This is more reliable for
  # service-generated files on tmpfs root.
  services.openssh.hostKeys = [
    {
      path = "/persist/etc/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }
    {
      path = "/persist/etc/ssh/ssh_host_rsa_key";
      type = "rsa";
      bits = 4096;
    }
  ];

  # ─── Persist /home/heikov ───────────────────────────────────
  # Mount the home directory from persist so the heikov user's
  # shell history, config files, and working data survive reboots.
  # This is a plain bind mount rather than impermanence per-file
  # tracking — the entire home is persistent.
  fileSystems."/home/heikov" = {
    device = "/persist/home/heikov";
    fsType = "none";
    options = [ "bind" ];
    depends = [ "/persist" ];
    neededForBoot = true;
  };
}
