# Example TUI Home Manager module.
# Copy this to modules/home-manager/tui/<tool>.nix and add to
# modules/home-manager/tui/default.nix.
# Enable in home/<username>/default.nix with:
#   user.tui.<tool>.enable = true;
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.tui.example;
in
{
  options.user.tui.example = {
    enable = lib.mkEnableOption "example TUI tool";
  };

  config = lib.mkIf cfg.enable {
    # programs.example.enable = true;
    # home.packages = with pkgs; [ example ];
  };
}
