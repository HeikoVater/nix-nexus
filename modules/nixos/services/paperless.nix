{
  config,
  lib,
  ...
}:

let
  cfg = config.homelab.paperless;
  paperlessHost = "paperless.${config.homelab.domain}";
  paperlessPort = 28981;
in
{
  options.homelab.paperless = {
    enable = lib.mkEnableOption "Paperless document management";

    storageRoot = lib.mkOption {
      type = lib.types.path;
      default = "/tank/safe/paperless";
      description = "Root directory that stores Paperless media and the consumption inbox.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/paperless";
      description = "Directory that stores Paperless application state.";
    };

    consumptionDirIsPublic = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether the Paperless consumption inbox should be world-writable.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.paperless = {
      enable = true;
      address = "127.0.0.1";
      port = paperlessPort;
      dataDir = cfg.dataDir;
      mediaDir = "${cfg.storageRoot}/media";
      consumptionDir = "${cfg.storageRoot}/consume";
      consumptionDirIsPublic = cfg.consumptionDirIsPublic;
      database.createLocally = true;

      settings = {
        PAPERLESS_PROXY_SSL_HEADER = [
          "HTTP_X_FORWARDED_PROTO"
          "https"
        ];
        PAPERLESS_TRUSTED_PROXIES = "127.0.0.1";
        PAPERLESS_URL = "https://${paperlessHost}";
        PAPERLESS_USE_X_FORWARD_HOST = true;
        PAPERLESS_USE_X_FORWARD_PORT = true;
      };
    };

    services.caddy.virtualHosts."${paperlessHost}" = {
      extraConfig = ''
        tls internal
        reverse_proxy 127.0.0.1:${toString paperlessPort}
      '';
    };
  };
}
