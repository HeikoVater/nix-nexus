{
  config,
  lib,
  ...
}:

let
  hasVirtualHosts = config.services.caddy.virtualHosts != { };
in
{
  options.homelab = {
    domain = lib.mkOption {
      type = lib.types.str;
      default = "${config.networking.hostName}.lan";
      description = "Base domain for service subdomains (e.g. hass.<domain>).";
    };

    hostIPv4 = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "192.168.188.2";
      description = "Static IPv4 address assigned to this host.";
    };
  };

  config = lib.mkIf hasVirtualHosts {
    # ─── Caddy Reverse Proxy ──────────────────────────────────────
    # Browser-facing service modules always register their own
    # virtualHosts here and bind locally. This file only enables the
    # base Caddy service and opens the shared HTTPS entrypoints when
    # at least one web UI is present.
    #
    # DNS: Add A records for *.${config.homelab.domain} → this server's IP address
    #   - In the Fritz!Box: Home Network → Network → Network Settings
    #     → DNS Rebind Protection → add ${config.homelab.domain}
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
