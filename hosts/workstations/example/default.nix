# Example workstation configuration.
# Copy this directory to hosts/workstations/<hostname>/ and customize.
# Replace all occurrences of "example" with your hostname/username.
{
  hostname,
  pkgs,
  config,
  ...
}:

{
  imports = [
    ../common.nix
    ./hardware-configuration.nix
  ];

  # ═══════════════════════════════════════════════════════════════════
  #  Home Manager
  # ═══════════════════════════════════════════════════════════════════
  # home-manager.users.example = {
  #   ...
  # }:
  # {
  #   imports = [ ../../../home/example/workstation.nix ];
  #
  #   user.cli.sops-menu = {
  #     enable = true;
  #     secretsFile = ../../../secrets/users/example.yaml;
  #   };
  # };

  # ═══════════════════════════════════════════════════════════════════
  #  Workstation Features
  # ═══════════════════════════════════════════════════════════════════
  # workstation.mount-nas.enable = true;
  # workstation.sunshine.enable = true;

  # ═══════════════════════════════════════════════════════════════════
  #  Basic System
  # ═══════════════════════════════════════════════════════════════════
  networking.hostName = hostname;

  # users.users.example = {
  #   isNormalUser = true;
  #   shell = pkgs.zsh;
  #   extraGroups = [ "wheel" "networkmanager" ];
  #   hashedPasswordFile = config.sops.secrets.example_password_hash.path;
  #   openssh.authorizedKeys.keys = [
  #     "ssh-ed25519 AAAA..."
  #   ];
  # };

  # sops.defaultSopsFile = ../../../secrets/hosts/example.yaml;
  # sops.secrets.example_password_hash.neededForUsers = true;

  system.stateVersion = "25.11";
}
