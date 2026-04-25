{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:

let
  cfg = config.user.cli.yt-dlp;
in
{
  options.user.cli.yt-dlp = {
    enable = lib.mkEnableOption "yt-dlp";
  };

  config = lib.mkIf cfg.enable {
    programs.yt-dlp = {
      enable = true;
      package = pkgs-unstable.yt-dlp;
      settings = {
        output = "~/Downloads/yt-dlp/%(title)s.%(ext)s";
        format = "bestvideo[ext=mp4][height<=?1080]+bestaudio[ext=m4a]/best[ext=mp4]\\best";
      };
    };
  };
}
