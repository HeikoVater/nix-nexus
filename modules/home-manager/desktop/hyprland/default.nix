{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.desktop.hyprland;
in
{
  options.user.desktop.hyprland = {
    enable = lib.mkEnableOption "Hyprland desktop";
  };

  imports = [
    ./packages.nix
    ./hyprland_config.nix
    ./waybar_config.nix
    ./autostart.nix
  ];

  config = lib.mkIf cfg.enable {
    user.desktop.hyprland = {
      packages.enable = lib.mkDefault true;
      hyprlandConfig.enable = lib.mkDefault true;
      waybar.enable = lib.mkDefault true;
      autostart.enable = lib.mkDefault true;
    };

    home.packages = with pkgs; [
      font-awesome
      dejavu_fonts
      nerd-fonts.jetbrains-mono
      nerd-fonts.symbols-only
    ];

    xdg.portal = {
      enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-hyprland
      ];
    };

    services.udiskie.enable = true;
  };
}
