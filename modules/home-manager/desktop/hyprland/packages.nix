{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.desktop.hyprland.packages;
in
{
  options.user.desktop.hyprland.packages = {
    enable = lib.mkEnableOption "Hyprland packages";
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      (waybar.overrideAttrs (oldAttrs: {
        mesonFlags = oldAttrs.mesonFlags ++ [ "-Dexperimental=true" ];
      }))
      wofi
      mako
      libnotify
      wl-clipboard
      swww
      networkmanagerapplet
      pavucontrol
      hyprshot
      hyprlock
      slurp
      wf-recorder
      crypto-tracker
      foot
      brightnessctl
      playerctl
    ];
  };
}
