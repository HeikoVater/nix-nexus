{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:

let
  retroarchRootDir = "${config.home.homeDirectory}/syncthing/RetroArch";
in
{
  imports = [
    ./headless.nix
    ./workstation/librewolf.nix
    # ./workstation/pegasus.nix
  ];

  # Workstation hosts set `user.profile.kind` through host-family
  # `home-manager.sharedModules`, which re-enables the Stylix dconf targets.

  # ─── Module Toggles ─────────────────────────────────────────────
  user = {
    gui = {
      packages.enable = true;
      kitty.enable = true;
      swayimg.enable = true;
      mpv.enable = true;
      librewolf.enable = true;
      # pegasus.enable = true;
      # retroarch = {
      #   enable = true;
      #   rootDir = retroarchRootDir;
      # };
    };

    desktop = {
      hyprland = {
        enable = true;
        waybar.cryptoTrackerApiKeyFile = lib.attrByPath [
          "sops"
          "secrets"
          "crypto_tracker_api_key"
          "path"
        ] null osConfig;
      };
    };
  };

  # ─── Input / Assets ─────────────────────────────────────────────
  home = {
    keyboard = {
      layout = "us";
      variant = "altgr-intl";
      kb_options = "caps:hyper";
    };

    file = {
      "wallpapers/wp.gif".source = ./assets/wallpapers/wp.gif;
      "wallpapers/wp_l.gif".source = ./assets/wallpapers/wp_l.gif;
      "wallpapers/wp_r.gif".source = ./assets/wallpapers/wp_r.gif;
      "profile/pic.png".source = ./assets/profile/pic.png;
    };
  };

  # ─── Desktop Session Defaults ───────────────────────────────────
  home.sessionVariables = {
    TERMINAL = "kitty";
    FILE_MANAGER = lib.mkForce "kitty --app-id yazi -e yazi";
    GUI_FILE_MANAGER = "nautilus";
    CALCULATOR = "kitty --app-id libqalculate -e libqalculate";
    BROWSER = "librewolf";
    DMENU = "wofi --show drun";
    PMENU = "sops-menu-popup kitty --app-id sops-menu";
    IMAGE_VIEWER = "swayimg";
    AUDIO_VIEWER = "mpv";
    VIDEO_VIEWER = "mpv";
    IMAGE_EDITOR = "gimp";
    AUDIO_EDITOR = "audacity";
    VIDEO_EDITOR = "davinci-resolve";
  };

  # ─── Workstation Packages ───────────────────────────────────────
  home.packages = with pkgs; [
    firefox
    gimp
    davinci-resolve
    obsidian
    steam
    libreoffice
    qbittorrent
  ];

  programs.vesktop.enable = true;

  # ─── MIME Defaults ──────────────────────────────────────────────
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "video/mp4" = "mpv.desktop";
      "video/x-matroska" = "mpv.desktop";
      "video/webm" = "mpv.desktop";

      "audio/mpeg" = "mpv.desktop";
      "audio/ogg" = "mpv.desktop";
      "audio/flac" = "mpv.desktop";
      "audio/x-wav" = "mpv.desktop";

      "image/jpeg" = "swayimg.desktop";
      "image/jpg" = "swayimg.desktop";
      "image/png" = "swayimg.desktop";
      "image/gif" = "swayimg.desktop";

      "application/pdf" = "librewolf.desktop";

      "text/plain" = "vim.desktop";
      "text/x-python" = "vim.desktop";
      "text/json" = "vim.desktop";
      "text/xml" = "vim.desktop";
      "text/x-tex" = "vim.desktop";

      "application/x-bittorrent" = "qbittorrent.desktop";
    };
  };
}
