{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homelab.backups;
  ha = config.homelab.home-assistant;
  z2m = config.homelab.zigbee2mqtt;
  pihole = config.homelab.pihole;
  coolercontrol = config.homelab.coolercontrol;
  nixarr = config.homelab.nixarr;
  paperless = config.homelab.paperless;
  immich = config.homelab.immich;
  needsPostgresDump = paperless.enable || immich.enable;
  postgresDumpDir = "/var/backup/postgresql";
  postgresPackage = config.services.postgresql.package;
  gzip = lib.getExe pkgs.gzip;
  install = lib.getExe' pkgs.coreutils "install";
  rm = lib.getExe' pkgs.coreutils "rm";
  runuser = lib.getExe' pkgs.util-linux "runuser";
  pgDump = lib.getExe' postgresPackage "pg_dump";
  pgDumpAll = lib.getExe' postgresPackage "pg_dumpall";
  nixarrServiceUnits =
    (lib.optional config.nixarr.transmission.enable "transmission.service")
    ++ (lib.optional config.nixarr.prowlarr.enable "prowlarr.service")
    ++ (lib.optional config.nixarr.sonarr.enable "sonarr.service")
    ++ (lib.optional config.nixarr.radarr.enable "radarr.service")
    ++ (lib.optional config.nixarr.lidarr.enable "lidarr.service")
    ++ (lib.optional config.nixarr.bazarr.enable "bazarr.service")
    ++ (lib.optional config.nixarr.jellyfin.enable "jellyfin.service")
    ++ (lib.optional config.nixarr.seerr.enable "seerr.service");
  nixarrStopCommands = lib.concatMapStrings (unit: "systemctl stop ${unit}\n") nixarrServiceUnits;
  nixarrStartCommands = lib.concatMapStrings (
    unit: "systemctl start ${unit} || true\n"
  ) nixarrServiceUnits;
  backupPaths =
    (lib.optional ha.enable "/var/lib/hass")
    ++ (lib.optional z2m.enable "/var/lib/zigbee2mqtt")
    ++ (lib.optional pihole.enable "/etc/pihole")
    ++ (lib.optional pihole.enable "/var/lib/pihole")
    ++ (lib.optional coolercontrol.enable "/etc/coolercontrol")
    ++ (lib.optional nixarr.enable (toString nixarr.stateDir))
    ++ (lib.optional paperless.enable (toString paperless.storageRoot))
    ++ (lib.optional paperless.enable paperless.dataDir)
    ++ (lib.optional immich.enable (toString immich.mediaLocation))
    ++ (lib.optional immich.enable "/var/lib/immich")
    ++ (lib.optional needsPostgresDump postgresDumpDir);
in
{
  options.homelab.backups = {
    enable = lib.mkEnableOption "BorgBackup to local ZFS pool";

    repo = lib.mkOption {
      type = lib.types.str;
      default = "/tank/backups/borg";
      description = "Path to the borg repository on the ZFS tank pool.";
    };
  };

  config = lib.mkIf cfg.enable {
    # ─── BorgBackup ───────────────────────────────────────────────
    # Daily backups of all enabled service state to a borg repo on
    # the local ZFS mirror pool (tank — 2x12 TB).
    #
    # Backup paths are derived automatically from which homelab
    # services are enabled — disable a service and its state is
    # no longer backed up.
    #
    # Prerequisites:
    #   1. ZFS tank pool imported and tank/backups mounted at
    #      /tank/backups (handled by disko).
    #   2. The borg repo is initialised automatically on first run.
    #
    # Inspect archives on the host:
    #   sudo borg-job-<hostname> list
    #   sudo borg-job-<hostname> list ::<hostname>-YYYY-MM-DDTHH:MM:SS
    #
    # Note: local backups protect against software failures and
    # accidental deletion, but NOT against hardware failure of the
    # whole machine. Consider periodically copying the borg repo
    # off-site (rsync to a remote server, rclone to cloud, etc.).

    services.borgbackup.jobs.${config.networking.hostName} = {
      paths = backupPaths;

      repo = cfg.repo;
      doInit = true;
      archiveBaseName = config.networking.hostName;
      readWritePaths = lib.optional needsPostgresDump postgresDumpDir;

      encryption = {
        mode = "repokey";
        passCommand = "cat ${config.sops.secrets.borg_passphrase.path}";
      };

      compression = "auto,zstd";

      # Run daily at 03:00. On hosts that enable the repo's
      # auto-upgrade module, this stays ahead of the default 04:00
      # upgrade window.
      startAt = "03:00";

      # Retention: keep 7 daily, 4 weekly, 6 monthly
      prune.keep = {
        daily = 7;
        weekly = 4;
        monthly = 6;
      };

      # Stop services during backup for data consistency.
      # Home Assistant's SQLite database and Nixarr app state can
      # be inconsistent if copied while their services are writing.
      preHook =
        (lib.optionalString ha.enable "systemctl stop home-assistant.service\n")
        + (lib.optionalString z2m.enable "systemctl stop zigbee2mqtt.service\n")
        + (lib.optionalString pihole.enable "systemctl stop pihole-ftl.service\n")
        + (lib.optionalString nixarr.enable nixarrStopCommands)
        + (lib.optionalString needsPostgresDump ''
          ${install} -d -m 0700 ${lib.escapeShellArg postgresDumpDir}
          shopt -s nullglob dotglob
          dumpEntries=(${lib.escapeShellArg postgresDumpDir}/*)
          if [ ''${#dumpEntries[@]} -gt 0 ]; then
            ${rm} -rf "''${dumpEntries[@]}"
          fi
          ${runuser} -u postgres -- ${pgDumpAll} --globals-only | ${gzip} -9 > ${lib.escapeShellArg "${postgresDumpDir}/globals.sql.gz"}
        '')
        + (lib.optionalString paperless.enable ''
          ${runuser} -u postgres -- ${pgDump} --clean --if-exists --create --dbname=paperless | ${gzip} -9 > ${lib.escapeShellArg "${postgresDumpDir}/paperless.sql.gz"}
        '')
        + (lib.optionalString immich.enable ''
          ${runuser} -u postgres -- ${pgDump} --clean --if-exists --create --dbname=${lib.escapeShellArg config.services.immich.database.name} | ${gzip} -9 > ${lib.escapeShellArg "${postgresDumpDir}/immich.sql.gz"}
        '');

      # Use || true so a failure to start one service does not
      # prevent the other from being attempted.
      postHook =
        (lib.optionalString pihole.enable "systemctl start pihole-ftl.service || true\n")
        + (lib.optionalString z2m.enable "systemctl start zigbee2mqtt.service || true\n")
        + (lib.optionalString nixarr.enable nixarrStartCommands)
        + (lib.optionalString ha.enable "systemctl start home-assistant.service || true\n");

      persistentTimer = true;
    };

    systemd.tmpfiles.rules = lib.optional needsPostgresDump "d ${postgresDumpDir} 0700 root root -";
  };
}
