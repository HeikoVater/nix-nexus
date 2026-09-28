{
  config,
  lib,
  pkgs-unstable,
  ...
}:

let
  cfg = config.user.tui.claude-code;
in
{
  options.user.tui.claude-code = {
    enable = lib.mkEnableOption "Claude Code AI coding agent";
  };

  config = lib.mkIf cfg.enable {
    programs.claude-code = {
      enable = true;
      package = pkgs-unstable.claude-code;
    };
  };
}
