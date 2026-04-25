# Example Home Manager user configuration.
# Copy this directory to home/<username>/ and customize.
# Then reference it from the host config:
#   home-manager.users.<username> = import ../../home/<username>;
#
# Replace all occurrences of "example" with your username.
{
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ../../modules/home-manager
  ];

  # ═══════════════════════════════════════════════════════════════════
  #  Module Toggles
  # ═══════════════════════════════════════════════════════════════════
  user = {
    cli = {
      packages.enable = true;
      shell.enable = true;
      zsh.enable = true;
      tmux.enable = true;
      starship.enable = true;
      direnv.enable = true;
      fastfetch.enable = true;
      zoxide.enable = true;
      # sops-menu = {
      #   enable = true;
      #   secretsFile = "/etc/nixos/secrets/users/example.yaml";
      # };
      yt-dlp.enable = true;
      television.enable = true;
    };
    tui = {
      packages.enable = true;
      nvf.enable = true;
      opencode.enable = true;
      yazi.enable = true;
    };
  };

  # ═══════════════════════════════════════════════════════════════════
  #  User Identity
  # ═══════════════════════════════════════════════════════════════════
  home.username = "example";
  home.homeDirectory = "/home/example";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  # ═══════════════════════════════════════════════════════════════════
  #  Git
  # ═══════════════════════════════════════════════════════════════════
  programs.git = {
    enable = true;
    settings = {
      user.name = "Your Name";
      user.email = "you@example.com";
    };
  };

  # ═══════════════════════════════════════════════════════════════════
  #  Session
  # ═══════════════════════════════════════════════════════════════════
  home.sessionVariables = {
    EDITOR = "nvim";
    FILE_MANAGER = "yazi";
  };
}
