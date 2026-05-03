{
  hostname,
  config,
  pkgs,
  ...
}:

{
  imports = [
    ../common.nix
    ./hardware.nix
    ./disks.nix
    ./power.nix
  ];

  # ═══════════════════════════════════════════════════════════════════
  #  Home Manager — heikov user
  # ═══════════════════════════════════════════════════════════════════
  home-manager.users.heikov =
    {
      ...
    }:
    {
      imports = [ ../../../home/heikov/workstation.nix ];

      user.cli.sops-menu = {
        enable = true;
        secretsFile = ../../../secrets/users/heikov.yaml;
      };
    };

  # ═══════════════════════════════════════════════════════════════════
  #  Workstation Features
  # ═══════════════════════════════════════════════════════════════════
  workstation.mount-nas.enable = true;

  # ─── Basic System ──────────────────────────────────────────────
  networking.hostName = hostname;

  users.users.heikov = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    hashedPasswordFile = config.sops.secrets.heikov_password_hash.path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP3lk60aE5mZZPwCMEDOxcAIJjLfdUDbuPR4slUWnBuj heikov"
    ];
  };

  # ─── Secrets ───────────────────────────────────────────────────
  sops.defaultSopsFile = ../../../secrets/hosts/laptop.yaml;

  sops.secrets.heikov_password_hash = {
    neededForUsers = true;
  };

  system.stateVersion = "25.11";
}
