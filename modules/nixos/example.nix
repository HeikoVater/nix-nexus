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

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # ─── Common config (always applied when enabled) ────────────
      {
        # systemd.services.example = { ... };
        # environment.systemPackages = [ pkgs.example ];
      }

      # ─── With Caddy (bind to localhost, proxy via Caddy) ────────
      (lib.mkIf config.homelab.caddy.enable {
        # services.example.settings.host = "127.0.0.1";
        # services.caddy.virtualHosts."example.${domain}" = {
        #   extraConfig = "reverse_proxy localhost:8080";
        # };
      })

      # ─── Without Caddy (bind to 0.0.0.0, open firewall) ────────
      (lib.mkIf (!config.homelab.caddy.enable) {
        # services.example.settings.host = "0.0.0.0";
        # networking.firewall.allowedTCPPorts = [ 8080 ];
      })
    ]
  );
}
