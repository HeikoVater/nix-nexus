# Example host configuration.
# Copy this directory to hosts/<hostname>/ and customize.
# Then add the host to flake.nix nixosConfigurations.
#
# Replace all occurrences of "example" with your hostname/username.
{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    # ./disko.nix  # if using declarative disk layout
  ];

  # ═══════════════════════════════════════════════════════════════════
  #  Home Manager
  # ═══════════════════════════════════════════════════════════════════
  # home-manager = {
  #   useGlobalPkgs = true;
  #   useUserPackages = true;
  #   users.example = import ../../home/example;
  # };

  # ═══════════════════════════════════════════════════════════════════
  #  Service Toggles
  # ═══════════════════════════════════════════════════════════════════
  homelab = {
    # hostIPv4 = "192.168.188.2"; # set this on statically addressed hosts
    # Optional override; defaults to "<hostname>.lan".
    # domain = "example.lan";
    pihole.enable = false;
    home-assistant.enable = false;
    mosquitto.enable = false;
    zigbee2mqtt.enable = false;
    backups.enable = false;
    auto-upgrade.enable = false;
    nh.enable = false;
  };

  # ─── Basic System ──────────────────────────────────────────────
  networking.hostName = "example";
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  # ─── Networking ────────────────────────────────────────────────
  networking.useDHCP = true;

  # ─── SSH ───────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # users.users.example = {
  #   isNormalUser = true;
  #   extraGroups = [ "wheel" ];
  #   hashedPasswordFile = config.sops.secrets.example_password_hash.path;
  #   openssh.authorizedKeys.keys = [
  #     "ssh-ed25519 AAAA..."
  #   ];
  # };

  security.sudo.wheelNeedsPassword = false;

  # ─── Firewall ──────────────────────────────────────────────────
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  # ─── Common Tools ──────────────────────────────────────────────
  programs.git.enable = true;

  # ─── Nix Settings ──────────────────────────────────────────────
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.config.allowUnfree = false;

  system.stateVersion = "25.11";
}
