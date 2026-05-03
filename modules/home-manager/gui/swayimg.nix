{
  config,
  lib,
  ...
}:

let
  cfg = config.user.gui.swayimg;
in
{
  options.user.gui.swayimg = {
    enable = lib.mkEnableOption "swayimg";
  };

  config = lib.mkIf cfg.enable {
    programs.swayimg = {
      enable = true;
      settings = {
        viewer = {
          loop = "no";
          scale = "fit";
        };
        info.show = "no";
        "keys.viewer" = {
          h = "prev_file";
          l = "next_file";
          g = "first_file";
          G = "last_file";
        };
        "keys.gallery" = {
          h = "step_left";
          j = "step_down";
          k = "step_up";
          l = "step_right";
          g = "first_file";
          G = "last_file";
        };
      };
    };
  };
}
