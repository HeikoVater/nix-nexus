{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.nvf;
in
{
  options.user.nvf = {
    enable = lib.mkEnableOption "nvf (Neovim)";
  };

  config = lib.mkIf cfg.enable {
    # Add your nvf config here
  };
}
