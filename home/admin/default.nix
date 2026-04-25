{
  pkgs,
  ...
}:

{
  imports = [
    ../../modules/home-manager
  ];

  # ═══════════════════════════════════════════════════════════════════
  #  Module Toggles
  # ═══════════════════════════════════════════════════════════════════
  #  Flip any of these to false to disable a Home Manager module.
  # ─────────────────────────────────────────────────────────────────
  user = {
    nvf.enable = true;
    zsh.enable = true;
    tmux.enable = true;
    opencode.enable = true;
  };

  home.username = "admin";
  home.homeDirectory = "/home/admin";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
}
