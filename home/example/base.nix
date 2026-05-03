{
  pkgs,
  ...
}:

{
  imports = [
    ../common.nix
  ];

  # ─── Home Manager Base ──────────────────────────────────────────
  home.username = "example";
  home.homeDirectory = "/home/example";
  home.stateVersion = "25.11";

  # ─── Shared Identity ────────────────────────────────────────────
  programs.git = {
    enable = true;
    settings = {
      user.name = "Your Name";
      user.email = "you@example.com";
    };
  };

  # ─── Shared Locale ──────────────────────────────────────────────
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

  # ─── Shared Theme ───────────────────────────────────────────────
  stylix = {
    enable = true;
    polarity = "dark";
    base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
    fonts = {
      monospace = {
        name = "JetBrainsMono NF";
        package = pkgs.nerd-fonts.jetbrains-mono;
      };
      sansSerif = {
        name = "DejaVu Sans";
        package = pkgs.dejavu_fonts;
      };
      serif = {
        name = "DejaVu Serif";
        package = pkgs.dejavu_fonts;
      };
    };
    cursor = {
      name = "Bibata-Original-Ice";
      package = pkgs.bibata-cursors;
      size = 24;
    };
  };
}
