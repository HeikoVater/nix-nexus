{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.cli.packages;
in
{
  options.user.cli.packages = {
    enable = lib.mkEnableOption "CLI packages";
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      git
      fzf
      bat
      eza
      ripgrep
      fd
      nh
      p7zip
      jq
      tealdeer
      duf
      dust

      age
      sops
    ];
  };
}
