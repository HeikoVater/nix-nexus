{
  config,
  lib,
  ...
}:

let
  cfg = config.user.gui.kitty;
in
{
  options.user.gui.kitty = {
    enable = lib.mkEnableOption "kitty";
  };

  config = lib.mkIf cfg.enable {
    programs.kitty = {
      enable = true;
      extraConfig = ''
        confirm_os_window_close 0
        cursor_trail 1

        clear_all_shortcuts yes

        map ctrl+shift+c copy_to_clipboard
        map ctrl+shift+v paste_from_clipboard
      '';
    };
  };
}
