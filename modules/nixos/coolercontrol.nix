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
  options.homelab.coolercontrol.enable = lib.mkEnableOption "CoolerControl fan management";

  config = lib.mkIf cfg.enable {
    programs.coolercontrol.enable = true;

    # lm_sensors CLI for debugging fan/temp readings via `sensors`
    environment.systemPackages = [ pkgs.lm_sensors ];

    services.caddy.virtualHosts."coolercontrol.${config.homelab.domain}" = {
      extraConfig = ''
        tls internal
        reverse_proxy localhost:11987
      '';
    };
  };
}
