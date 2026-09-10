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

      wayland.windowManager.hyprland.settings.monitor = [
        "DP-1,1920x1080@60,0x0,1"
        "DP-2,1920x1080@60,1920x0,1"
      ];
    };

  # ═══════════════════════════════════════════════════════════════════
  #  Workstation Features
  # ═══════════════════════════════════════════════════════════════════
  workstation = {
    mount-nas.enable = true;
    sunshine = {
      enable = true;
      display = {
        connector = "HDMI-A-1";
        sunshineId = 0;
        refreshRate = 59.982;
        position = "10000x10000";
        workspace = "99";
        notificationOutput = "DP-1";
      };
    };
  };

  # ═══════════════════════════════════════════════════════════════════
  #  Desktop Services
  # ═══════════════════════════════════════════════════════════════════
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
