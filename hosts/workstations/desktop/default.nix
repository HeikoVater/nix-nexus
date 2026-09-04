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
  workstation = {
    mount-nas.enable = true;
    # sunshine.enable = true;
  };

  # ═══════════════════════════════════════════════════════════════════
  #  Desktop Services
  # ═══════════════════════════════════════════════════════════════════
  programs.steam.enable = true;

  services.comfyui = {
    enable = false;
    enableManager = true;
    extraDependencies = [
      "triton"
      "sageattention"
    ];
  };

  # ─── Basic System ──────────────────────────────────────────────
  networking.hostName = hostname;

  users.users.heikov = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "networkmanager"
      "uinput"
    ];
    hashedPasswordFile = config.sops.secrets.heikov_password_hash.path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP3lk60aE5mZZPwCMEDOxcAIJjLfdUDbuPR4slUWnBuj heikov"
    ];
  };

  # ─── Secrets ───────────────────────────────────────────────────
  sops.defaultSopsFile = ../../../secrets/hosts/desktop.yaml;

  sops.secrets.heikov_password_hash = {
    neededForUsers = true;
  };

  system.stateVersion = "25.11";
}
