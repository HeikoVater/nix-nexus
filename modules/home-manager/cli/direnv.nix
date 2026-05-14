{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.cli.direnv;
in
{
  options.user.cli.direnv = {
    enable = lib.mkEnableOption "direnv";
  };

  config = lib.mkIf cfg.enable {
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
      config.global.hide_env_diff = true;
    };
  };
}
