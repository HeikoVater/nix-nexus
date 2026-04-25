{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.zsh;
in
{
  options.user.zsh = {
    enable = lib.mkEnableOption "Zsh";
  };

  config = lib.mkIf cfg.enable {
    # Add your Zsh config here
  };
}
