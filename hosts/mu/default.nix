{
  hostname,
  config,
  pkgs,
  lib,
  ...
}:

let
  hostIPv4 = "192.168.188.30";
  routerIPv4 = "192.168.188.1";
in
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
  ];

  # ═══════════════════════════════════════════════════════════════════
  #  Home Manager — heikov user
  # ═══════════════════════════════════════════════════════════════════
  #  useGlobalPkgs / useUserPackages keeps everything on the single
  #  system nixpkgs evaluation — no extra eval pass, packages land in
  #  /etc/profiles/per-user/heikov instead of ~/.nix-profile.
  # ─────────────────────────────────────────────────────────────────
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.heikov = import ../../home/heikov;
  };

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
    home-assistant.enable = false;
    mosquitto.enable = false;
    zigbee2mqtt.enable = false;
    backups.enable = false;
    auto-upgrade.enable = false;
    nh.enable = true;
    coolercontrol.enable = true;
  };

  # ─── Basic System ──────────────────────────────────────────────
  networking.hostName = hostname;
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.supportedLocales = [
    "en_US.UTF-8/UTF-8"
    "de_DE.UTF-8/UTF-8"
  ];

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

  # ─── SSH ───────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  programs.zsh.enable = true;

  users.users.heikov = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" ];
    hashedPasswordFile = config.sops.secrets.heikov_password_hash.path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP3lk60aE5mZZPwCMEDOxcAIJjLfdUDbuPR4slUWnBuj heikov"
    ];
  };

  # ─── Firewall ──────────────────────────────────────────────────
  # Base firewall — only SSH is always open. HTTP/HTTPS are opened
  # automatically when any web UI module registers a Caddy route, and
  # Pi-hole opens DNS on 53/tcp+udp when enabled.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  # ─── Persistence ───────────────────────────────────────────────
  # Persist heikov's .ssh dir (impermanence tracks it within home).
  # The full home directory is bind-mounted below.
  environment.persistence."/persist".users.heikov = {
    directories = [
      {
        directory = ".ssh";
        mode = "0700";
      }
    ];
  };

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
  sops.defaultSopsFile = ../../secrets/hosts/mu.yaml;

  sops.secrets.heikov_password_hash = {
    neededForUsers = true;
  };

  # ─── Common Tools ──────────────────────────────────────────────
  environment.systemPackages = [ pkgs.kitty.terminfo ];
  programs.git.enable = true;

  # ─── Nix Settings ──────────────────────────────────────────────
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.config.allowUnfree = false;

  system.stateVersion = "25.11";
}
