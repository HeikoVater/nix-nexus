{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.tui.packages;
in
{
  options.user.tui.packages = {
    enable = lib.mkEnableOption "TUI packages";
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      lazygit
      btop
    ];
  };
}
