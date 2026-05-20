{
  hostname,
  config,
  pkgs,
  ...
}:

let
  hostIPv4 = "192.168.188.30";
  routerIPv4 = "192.168.188.1";
in
{
  imports = [
    ../common.nix
    ./hardware-configuration.nix
    ./disko.nix
  ];

  # ═══════════════════════════════════════════════════════════════════
  #  Home Manager — heikov user
  # ═══════════════════════════════════════════════════════════════════
  # ─────────────────────────────────────────────────────────────────
  home-manager.users.heikov =
    {
      ...
    }:
    {
      imports = [ ../../../home/heikov/headless.nix ];

      user.cli.sops-menu = {
        enable = true;
        secretsFile = ../../../secrets/users/heikov.yaml;
      };
    };

  # ═══════════════════════════════════════════════════════════════════
  #  Host Features
  # ═══════════════════════════════════════════════════════════════════
  # ─────────────────────────────────────────────────────────────────
  host.auto-upgrade.enable = false;

  # ═══════════════════════════════════════════════════════════════════
  #  Service Toggles
  # ═══════════════════════════════════════════════════════════════════
  #  Flip any of these to false to cleanly disable a service.
  #  Dependencies are validated automatically (e.g. Zigbee2MQTT
  #  requires Mosquitto). Browser-facing services always bind to
  #  localhost and register Caddy routes automatically.
  # ─────────────────────────────────────────────────────────────────
  homelab = {
    hostIPv4 = hostIPv4;
    pihole.enable = true;
    samba.enable = true;
    backups.enable = true;
    coolercontrol.enable = true;
    homepage-dashboard.enable = true;
    nixarr = {
      enable = true;
      transmissionPeerPort = 15570;
    };

    home-assistant.enable = false;
    mosquitto.enable = false;
    zigbee2mqtt.enable = false;
    paperless = {
      enable = true;
      consumptionDirIsPublic = true;
    };
    immich.enable = true;
  };

  # Use the regular limits during the day and the alternate limits overnight.
  nixarr.transmission.extraSettings = {
    speed-limit-down = 2000;
    speed-limit-down-enabled = true;
    speed-limit-up = 500;
    speed-limit-up-enabled = true;

    alt-speed-down = 9000;
    alt-speed-up = 4000;
    alt-speed-time-enabled = true;
    alt-speed-time-begin = 0;
    alt-speed-time-end = 480;
    alt-speed-time-day = 127;
  };

  # ─── Basic System ──────────────────────────────────────────────
  networking.hostName = hostname;

  # ─── Networking ────────────────────────────────────────────────
  networking = {
    useDHCP = false;

    # Keep host-side DNS on the router even though Pi-hole serves LAN clients.
    nameservers = [ routerIPv4 ];
  };

  systemd.network = {
    enable = true;
    networks."10-lan" = {
      matchConfig.Name = "en*"; # adjust to your NIC name if needed
      address = [ "${hostIPv4}/24" ];
      gateway = [ routerIPv4 ];
    };
  };

  # ─── User Account ───────────────────────────────────────────────
  users.users.heikov = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" ];
    hashedPasswordFile = config.sops.secrets.heikov_password_hash.path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP3lk60aE5mZZPwCMEDOxcAIJjLfdUDbuPR4slUWnBuj heikov"
    ];
  };

  # ─── Persistence ───────────────────────────────────────────────
  # Bind-mount the entire home from /persist so shell history,
  # config files, and working data survive reboots.
  fileSystems."/home/heikov" = {
    device = "/persist/home/heikov";
    fsType = "none";
    options = [ "bind" ];
    depends = [ "/persist" ];
    neededForBoot = true;
  };

  # ─── Secrets ───────────────────────────────────────────────────
  sops.defaultSopsFile = ../../../secrets/hosts/mu.yaml;

  sops.secrets.heikov_password_hash = {
    neededForUsers = true;
  };

  # ─── Terminal Compatibility ─────────────────────────────────────
  environment.systemPackages = [ pkgs.kitty.terminfo ];

  system.stateVersion = "25.11";
}
