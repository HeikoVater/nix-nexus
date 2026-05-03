{ pkgs, ... }:

{
  imports = [
    ./base.nix
  ];

  # `user.profile.kind` is normally supplied by the host-family Home Manager
  # wiring. Standalone Home Manager falls back to the headless default from
  # `home/common.nix`.

  # ─── Module Toggles ─────────────────────────────────────────────
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

  # ─── Shared Session Defaults ────────────────────────────────────
  home.sessionVariables = {
    EDITOR = "nvim";
    FILE_MANAGER = "yazi";
  };

  # ─── Agent / Editor Helpers ─────────────────────────────────────
  services.ssh-agent = {
    enable = true;
    defaultMaximumIdentityLifetime = 3600;
  };

  # ─── Shared Packages ────────────────────────────────────────────
  home.packages = with pkgs; [
    libqalculate
    ffmpeg
    helix
  ];
}
