{
  config,
  lib,
  ...
}:

let
  cfg = config.host.auto-upgrade;
in
{
  options.host.auto-upgrade = {
    enable = lib.mkEnableOption "automatic NixOS upgrades from GitHub";

    flake = lib.mkOption {
      type = lib.types.str;
      default = "github:HeikoVater/nix-nexus";
      description = "Flake URI to pull updates from.";
    };
  };

  config = lib.mkIf cfg.enable {
    # ─── Automatic Updates ────────────────────────────────────────
    # Pulls the latest flake from GitHub and rebuilds daily at 4 AM.
    # Reboots are only allowed if a kernel update landed, and only
    # within the maintenance window.
    system.autoUpgrade = {
      enable = true;
      flake = cfg.flake;
      dates = "04:00";
      allowReboot = true;
      rebootWindow = {
        lower = "03:00";
        upper = "05:00";
      };
      # For a private repo, the server needs a GitHub token or SSH
      # deploy key. See:
      #   https://nixos.wiki/wiki/Automatic_system_updates
    };
  };
}
