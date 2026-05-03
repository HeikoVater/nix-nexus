# Example Home Manager module.
# Copy this to one of:
#   modules/home-manager/cli/<tool>.nix
#   modules/home-manager/tui/<tool>.nix
#   modules/home-manager/gui/<tool>.nix
#   modules/home-manager/desktop/<tool>.nix
# Then add it to that directory's default.nix and enable it from the
# matching profile with:
#   user.<area>.<tool>.enable = true;
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
    enable = lib.mkEnableOption "example Home Manager module";
  };

  config = lib.mkIf cfg.enable {
    # programs.example.enable = true;
    # home.packages = with pkgs; [ example ];
  };
}
