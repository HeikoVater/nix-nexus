{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homelab.coolercontrol;
in
{
  options.homelab.coolercontrol = {
    enable = lib.mkEnableOption "CoolerControl fan management";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # ─── Base CoolerControl Configuration ─────────────────────────
    {
      programs.coolercontrol.enable = true;

      # lm_sensors CLI for debugging fan/temp readings via `sensors`
      environment.systemPackages = [ pkgs.lm_sensors ];
    }

    # ─── Behind Caddy: bind to localhost, proxy through Caddy ─────
    (lib.mkIf config.homelab.caddy.enable {
      services.caddy.virtualHosts."coolercontrol.${config.homelab.caddy.domain}" = {
        extraConfig = ''
          tls internal
          reverse_proxy localhost:11987
        '';
      };
    })

    # ─── No Caddy: expose directly on the network ────────────────
    (lib.mkIf (!config.homelab.caddy.enable) {
      networking.firewall.allowedTCPPorts = [ 11987 ];
      # Tell the daemon to bind to all interfaces via env overrides
      systemd.services.coolercontrold.environment = {
        CC_HOST_IP4 = "0.0.0.0";
        CC_HOST_IP6 = "::";
      };
    })
  ]);
}
