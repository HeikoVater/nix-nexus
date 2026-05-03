{ ... }:

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
      starship.enable = true;
      direnv.enable = true;
      fastfetch.enable = true;
      zoxide.enable = true;
      # sops-menu = {
      #   enable = true;
      #   secretsFile = ../../secrets/users/example.yaml;
      # };
      yt-dlp.enable = true;
      television.enable = true;
    };

    tui = {
      packages.enable = true;
      tmux.enable = true;
      lazygit.enable = true;
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
}
