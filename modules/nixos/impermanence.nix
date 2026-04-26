# ═══════════════════════════════════════════════════════════════════
#  Impermanence — Persistent State on Ephemeral Root
# ═══════════════════════════════════════════════════════════════════
#  Root (/) is tmpfs and wiped every reboot. This module declares
#  which system state and service data survive reboots by
#  bind-mounting from /persist (rpool/persist on the SSD).
#
#  Per-user home directories and user-specific persistence are
#  declared in each host's default.nix, not here.
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
  caddy = config.services.caddy.enable;
  pihole = config.homelab.pihole;
in
{
  environment.persistence."/persist" = {
    hideMounts = true;

    # ─── System State ───────────────────────────────────────────
    directories = [
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
    ++ (lib.optional cc.enable "/etc/coolercontrol")
    ++ (lib.optionals caddy [
      {
        directory = "/var/lib/caddy";
        user = "caddy";
        group = "caddy";
        mode = "0700";
      }
    ])
    ++ (lib.optionals pihole.enable [
      {
        directory = "/etc/pihole";
        user = "pihole";
        group = "pihole";
        mode = "0700";
      }
      {
        directory = "/var/lib/pihole";
        user = "pihole";
        group = "pihole";
        mode = "0700";
      }
    ]);

    # ─── System Files ───────────────────────────────────────────
    files = [
      "/etc/machine-id" # stable machine identity for systemd/journal
    ];
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

}
