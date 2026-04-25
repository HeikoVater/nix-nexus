{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.opencode;
in
{
  options.user.opencode = {
    enable = lib.mkEnableOption "OpenCode AI coding agent";
  };

  config = lib.mkIf cfg.enable {
    # Add your OpenCode config here
  };
}
