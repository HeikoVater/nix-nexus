# Example NixOS module.
# Copy this to one of:
#   modules/nixos/host/<name>.nix
#   modules/nixos/services/<name>.nix
#   modules/nixos/workstation/<name>.nix
# Then add it to that directory's default.nix and adjust the option path to
# match the bucket you chose:
#   host.<name>.enable = true;
#   homelab.<name>.enable = true;
#   workstation.<name>.enable = true;
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homelab.example;
in
{
  options.homelab.example = {
    enable = lib.mkEnableOption "example service";
  };

  config = lib.mkIf cfg.enable {
    # Common config (always applied when enabled)
    # systemd.services.example = { ... };
    # environment.systemPackages = [ pkgs.example ];

    # Browser-facing services bind locally and always publish a
    # Caddy vhost. The shared caddy module enables Caddy when at
    # least one virtualHost is defined.
    # services.example.settings.host = "127.0.0.1";
    # services.caddy.virtualHosts."example.${config.homelab.domain}" = {
    #   extraConfig = ''
    #     tls internal
    #     reverse_proxy localhost:8080
    #   '';
    # };
  };
}
