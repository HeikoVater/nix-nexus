{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.gui.packages;
in
{
  options.user.gui.packages = {
    enable = lib.mkEnableOption "GUI packages";
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      nautilus
    ];
  };
}
