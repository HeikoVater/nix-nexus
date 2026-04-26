{
  hostname,
  config,
  pkgs,
  lib,
  ...
}:

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
  #  requires Mosquitto). Caddy-awareness is built in — disabling
  #  Caddy makes services open their own firewall ports; enabling it
  #  binds them to localhost and registers reverse proxy routes.
  # ─────────────────────────────────────────────────────────────────
  homelab = {
    caddy.enable = false;
    home-assistant.enable = false;
    mosquitto.enable = false;
    zigbee2mqtt.enable = false;
    backups.enable = false;
    auto-upgrade.enable = false;
    nh.enable = false;
    coolercontrol.enable = false;
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
  networking.useDHCP = true;

  # ── Static IP (uncomment when ready, set useDHCP to false) ───
  # systemd.network = {
  #   enable = true;
  #   networks."10-lan" = {
  #     matchConfig.Name = "en*"; # adjust to your NIC name if needed
  #     address = [ "192.168.188.2/24" ];
  #     gateway = [ "192.168.188.1" ]; # Fritz!Box
  #     dns = [ "192.168.188.1" ];
  #     # ── Pi-hole DNS migration ──────────────────────────────────
  #     # When you add Pi-hole to this server:
  #     # 1. Change dns above to [ "127.0.0.1" ] so this server uses
  #     #    its own Pi-hole for resolution.
  #     # 2. Configure Pi-hole's upstream DNS to an external resolver
  #     #    (e.g. 1.1.1.1, 9.9.9.9) — NOT back to the Fritz!Box,
  #     #    or you'll create a resolution loop.
  #     # 3. In the Fritz!Box admin (Home Network > Network > Network
  #     #    Settings > IPv4 > Local DNS server), set the DNS server
  #     #    to 192.168.188.2 so all LAN clients use Pi-hole.
  #     # 4. Alternatively, set DNS per-device or via DHCP options.
  #   };
  # };

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
  # Base firewall — only SSH is always open. Service-specific ports
  # (80/443 for Caddy, or 8123/8080 when Caddy is off) are opened
  # automatically by each module.
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
