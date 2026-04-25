{
  config,
  lib,
  ...
}:

let
  cfg = config.homelab.caddy;
in
{
  options.homelab.caddy = {
    enable = lib.mkEnableOption "Caddy reverse proxy";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "home-server.lan";
      description = "Base domain for service subdomains (e.g. hass.<domain>).";
    };
  };

  config = lib.mkIf cfg.enable {
    # ─── Caddy Reverse Proxy ──────────────────────────────────────
    # Each service module registers its own virtualHost here when
    # both the service and caddy are enabled. This file only sets up
    # the base Caddy service and firewall rules.
    #
    # DNS: Add A records for *.${cfg.domain} → localhost's ip address
    #   - In the Fritz!Box: Home Network → Network → Network Settings
    #     → DNS Rebind Protection → add ${cfg.domain}
    #   - Or add entries to your Pi-hole local DNS once it's running.
    #   - Or use /etc/hosts on your client machines.
    #
    # TLS: Caddy uses self-signed certs via "tls internal".
    #   Accept the browser warning once per subdomain, or install
    #   Caddy's root CA on your devices:
    #     /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt

    services.caddy.enable = true;

    networking.firewall.allowedTCPPorts = [
      80 # HTTP
      443 # HTTPS
    ];
  };
}
