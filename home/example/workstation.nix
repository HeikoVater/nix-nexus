{
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./headless.nix
  ];

  # ─── Module Toggles ─────────────────────────────────────────────
  user = {
    gui = {
      packages.enable = true;
      kitty.enable = true;
      swayimg.enable = true;
      mpv.enable = true;
      librewolf.enable = true;
      # pegasus.enable = true;
      # retroarch.enable = true;
    };

    desktop.hyprland.enable = true;
  };

  # ─── Input Defaults ─────────────────────────────────────────────
  home.keyboard = {
    layout = "us";
    variant = "altgr-intl";
    kb_options = "caps:hyper";
  };

  # ─── Desktop Session Defaults ───────────────────────────────────
  home.sessionVariables = {
    TERMINAL = "kitty";
    FILE_MANAGER = lib.mkForce "kitty --app-id yazi -e yazi";
    GUI_FILE_MANAGER = "nautilus";
    CALCULATOR = "kitty --app-id libqalculate -e libqalculate";
    BROWSER = "librewolf";
    DMENU = "wofi --show drun";
    PMENU = "kitty --app-id sops-menu -e sops-menu";
    IMAGE_VIEWER = "swayimg";
    AUDIO_VIEWER = "mpv";
    VIDEO_VIEWER = "mpv";
  };

  # ─── Workstation Packages ───────────────────────────────────────
  home.packages = with pkgs; [
    firefox
    gimp
    libreoffice
    qbittorrent
  ];

  # ─── MIME Defaults ──────────────────────────────────────────────
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "video/mp4" = "mpv.desktop";
      "image/png" = "swayimg.desktop";
      "application/pdf" = "librewolf.desktop";
      "text/plain" = "vim.desktop";
    };
  };
}
