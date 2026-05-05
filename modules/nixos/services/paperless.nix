{
  config,
  lib,
  pkgs,
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

  config = lib.mkIf cfg.enable (
    let
      serviceCfg = config.services.paperless;
      serviceGroup = config.users.users.${serviceCfg.user}.group;
      setupService = "paperless-storage-setup.service";
      dependentUnits = [
        "paperless-scheduler.service"
        "paperless-task-queue.service"
        "paperless-web.service"
        "paperless-consumer.service"
      ];
      dependentServices = [
        "paperless-scheduler"
        "paperless-task-queue"
        "paperless-web"
        "paperless-consumer"
      ];
      installBin = lib.getExe' pkgs.coreutils "install";
      chownBin = lib.getExe' pkgs.coreutils "chown";
      chmodBin = lib.getExe' pkgs.coreutils "chmod";
    in
    {
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

      systemd.services =
        builtins.listToAttrs (
          map (name: {
            inherit name;
            value = {
              requires = [ setupService ];
              after = [ setupService ];
            };
          }) dependentServices
        )
        // {
          # Activation can remount ZFS-backed paths after tmpfiles runs, so make
          # Paperless create and fix its writable directories only after mounts exist.
          paperless-storage-setup = {
            description = "Prepare Paperless writable directories";
            before = dependentUnits;
            requiredBy = dependentUnits;
            after = [ "local-fs.target" ];
            unitConfig.RequiresMountsFor = [
              serviceCfg.dataDir
              serviceCfg.mediaDir
              serviceCfg.consumptionDir
            ];
            serviceConfig = {
              Type = "oneshot";
            };
            script = ''
              ${installBin} -d -m 0755 ${lib.escapeShellArg serviceCfg.dataDir}
              ${installBin} -d -m 0755 ${lib.escapeShellArg serviceCfg.mediaDir}
              ${installBin} -d -m 0755 ${lib.escapeShellArg "${serviceCfg.dataDir}/log"}

              ${chownBin} ${lib.escapeShellArg "${serviceCfg.user}:${serviceGroup}"} ${lib.escapeShellArg serviceCfg.dataDir}
              ${chownBin} ${lib.escapeShellArg "${serviceCfg.user}:${serviceGroup}"} ${lib.escapeShellArg serviceCfg.mediaDir}
              ${chownBin} ${lib.escapeShellArg "${serviceCfg.user}:${serviceGroup}"} ${lib.escapeShellArg "${serviceCfg.dataDir}/log"}

              ${chmodBin} 0755 ${lib.escapeShellArg serviceCfg.dataDir}
              ${chmodBin} 0755 ${lib.escapeShellArg serviceCfg.mediaDir}
              ${chmodBin} 0755 ${lib.escapeShellArg "${serviceCfg.dataDir}/log"}

              ${installBin} -d -m 0755 ${lib.escapeShellArg serviceCfg.consumptionDir}
              ${lib.optionalString serviceCfg.consumptionDirIsPublic ''
                ${chmodBin} 0777 ${lib.escapeShellArg serviceCfg.consumptionDir}
              ''}
              ${lib.optionalString (!serviceCfg.consumptionDirIsPublic) ''
                ${chownBin} ${lib.escapeShellArg "${serviceCfg.user}:${serviceGroup}"} ${lib.escapeShellArg serviceCfg.consumptionDir}
                ${chmodBin} 0755 ${lib.escapeShellArg serviceCfg.consumptionDir}
              ''}
            '';
          };
        };

      services.caddy.virtualHosts."${paperlessHost}" = {
        extraConfig = ''
          tls internal
          reverse_proxy 127.0.0.1:${toString paperlessPort}
        '';
      };
    }
  );
}
