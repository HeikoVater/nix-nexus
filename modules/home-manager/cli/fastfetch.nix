{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.cli.fastfetch;
in
{
  options.user.cli.fastfetch = {
    enable = lib.mkEnableOption "fastfetch";
  };

  config = lib.mkIf cfg.enable {
    programs.fastfetch = {
      enable = true;
      settings = {
        logo.type = "auto";
        # modules = [
        #   "title"
        #   "os"
        #   {
        #     type = "command";
        #     key = "Tmux";
        #     command = "command -v tmux >/dev/null && tmux -V";
        #   }
        #   {
        #     type = "command";
        #     key = "nvim";
        #     command = "command -v nvim >/dev/null && nvim --version | head -n1";
        #   }
        # ];
      };
    };
  };
}
