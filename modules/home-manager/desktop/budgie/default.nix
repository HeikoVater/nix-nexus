{
  config,
  lib,
  ...
}:

let
  cfg = config.user.desktop.budgie;
in
{
  options.user.desktop.budgie = {
    enable = lib.mkEnableOption "Budgie desktop";
  };

  config = lib.mkIf cfg.enable { };
}
