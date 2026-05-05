{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homelab.immich;
  immichHost = "immich.${config.homelab.domain}";
  immichPort = 2283;
  mediaLocation = toString cfg.mediaLocation;
  setupService = "immich-storage-setup.service";
  installBin = lib.getExe' pkgs.coreutils "install";
  chownBin = lib.getExe' pkgs.coreutils "chown";
  chmodBin = lib.getExe' pkgs.coreutils "chmod";
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

    # Activation can remount ZFS-backed paths after tmpfiles runs, so make
    # Immich fix its writable media root only after the live mount exists.
    systemd.services.immich-server = {
      requires = [ setupService ];
      after = [ setupService ];
    };

    systemd.services.immich-storage-setup = {
      description = "Prepare Immich writable media directory";
      before = [ "immich-server.service" ];
      requiredBy = [ "immich-server.service" ];
      after = [ "local-fs.target" ];
      unitConfig.RequiresMountsFor = [ mediaLocation ];
      serviceConfig.Type = "oneshot";
      script = ''
        ${installBin} -d -m 0700 ${lib.escapeShellArg mediaLocation}
        ${chownBin} immich:immich ${lib.escapeShellArg mediaLocation}
        ${chmodBin} 0700 ${lib.escapeShellArg mediaLocation}
      '';
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
