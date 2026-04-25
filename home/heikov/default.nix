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
      sops-menu = {
        enable = true;
        secretsFile = "/etc/nixos/secrets/users/heikov.yaml";
      };
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
  home.username = "heikov";
  home.homeDirectory = "/home/heikov";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  # ═══════════════════════════════════════════════════════════════════
  #  Git
  # ═══════════════════════════════════════════════════════════════════
  programs.git = {
    enable = true;
    settings = {
      user.name = "Heiko Vater";
      user.email = "125594783+HeikoVater@users.noreply.github.com";

      merge = {
        tool = "nvimdiff";
        prompt = false;
      };
      mergetool.keepBackup = false;
    };
  };

  # ═══════════════════════════════════════════════════════════════════
  #  Locale
  # ═══════════════════════════════════════════════════════════════════
  home.language = {
    base = "en_US.UTF-8";
    address = "de_DE.UTF-8";
    measurement = "de_DE.UTF-8";
    monetary = "de_DE.UTF-8";
    name = "de_DE.UTF-8";
    numeric = "de_DE.UTF-8";
    paper = "de_DE.UTF-8";
    telephone = "de_DE.UTF-8";
    time = "de_DE.UTF-8";
  };

  # ═══════════════════════════════════════════════════════════════════
  #  Session
  # ═══════════════════════════════════════════════════════════════════
  home.sessionVariables = {
    EDITOR = "nvim";
    FILE_MANAGER = "yazi";
  };

  # ═══════════════════════════════════════════════════════════════════
  #  SSH Agent
  # ═══════════════════════════════════════════════════════════════════
  services.ssh-agent = {
    enable = true;
    defaultMaximumIdentityLifetime = 3600;
  };

  # ═══════════════════════════════════════════════════════════════════
  #  Extra Packages
  # ═══════════════════════════════════════════════════════════════════
  home.packages = with pkgs; [
    libqalculate
    ffmpeg
    helix
  ];
}
