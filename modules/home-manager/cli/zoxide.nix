{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.cli.zoxide;
in
{
  options.user.cli.zoxide = {
    enable = lib.mkEnableOption "zoxide";
  };

  config = lib.mkIf cfg.enable {
    programs.zoxide.enable = true;
  };
}
