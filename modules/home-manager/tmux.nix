{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.tmux;
in
{
  options.user.tmux = {
    enable = lib.mkEnableOption "tmux";
  };

  config = lib.mkIf cfg.enable {
    # Add your tmux config here
  };
}
