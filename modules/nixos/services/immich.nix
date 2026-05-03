{
  config,
  lib,
  ...
}:

let
  cfg = config.homelab.immich;
  immichHost = "immich.${config.homelab.domain}";
  immichPort = 2283;
in
{
  options.homelab.immich = {
    enable = lib.mkEnableOption "Immich photo and video library";

    mediaLocation = lib.mkOption {
      type = lib.types.path;
      default = "/tank/safe/immich";
      description = "Directory used to store Immich originals and generated media.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.immich = {
      enable = true;
      host = "127.0.0.1";
      port = immichPort;
      mediaLocation = cfg.mediaLocation;

      settings = {
        backup.database.enabled = false;
        server.externalDomain = "https://${immichHost}";
        storageTemplate = {
          enabled = true;
          hashVerificationEnabled = true;
          template = "{{y}}/{{y}}-{{MM}}-{{dd}}/{{filename}}";
        };
      };
    };

    services.caddy.virtualHosts."${immichHost}" = {
      extraConfig = ''
        tls internal
        reverse_proxy 127.0.0.1:${toString immichPort}
      '';
    };

    services.caddy.virtualHosts."http://${immichHost}" = {
      extraConfig = ''
        reverse_proxy 127.0.0.1:${toString immichPort}
      '';
    };
  };
}
