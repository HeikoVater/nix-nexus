# Example CLI Home Manager module.
# Copy this to modules/home-manager/cli/<tool>.nix and add to
# modules/home-manager/cli/default.nix.
# Enable in home/<username>/default.nix with:
#   user.cli.<tool>.enable = true;
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.cli.example;
in
{
  options.user.cli.example = {
    enable = lib.mkEnableOption "example CLI tool";
  };

  config = lib.mkIf cfg.enable {
    # programs.example.enable = true;
    # home.packages = with pkgs; [ example ];
  };
}
