# Example NixOS service module.
# Copy this to modules/nixos/<service>.nix, add to modules/nixos/default.nix,
# and enable in hosts/<hostname>/default.nix with:
#   homelab.<service>.enable = true;
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
