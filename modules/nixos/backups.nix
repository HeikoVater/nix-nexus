{
  config,
  lib,
  ...
}:

let
  cfg = config.homelab.backups;
  ha = config.homelab.home-assistant;
  z2m = config.homelab.zigbee2mqtt;
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
    # Restore a file:
    #   borg list ${cfg.repo}
    #   borg extract ${cfg.repo}::ARCHIVE_NAME path/to/file
    #
    # Note: local backups protect against software failures and
    # accidental deletion, but NOT against hardware failure of the
    # whole machine. Consider periodically copying the borg repo
    # off-site (rsync to a remote server, rclone to cloud, etc.).

    services.borgbackup.jobs.home-server = {
      paths =
        (lib.optional ha.enable "/var/lib/hass")
        ++ (lib.optional z2m.enable "/var/lib/zigbee2mqtt");

      repo = cfg.repo;
      doInit = true;

      encryption = {
        mode = "repokey";
        passCommand = "cat ${config.sops.secrets.borg_passphrase.path}";
      };

      compression = "auto,zstd";

      # Run daily at 3:00 AM (before the auto-upgrade at 4:00 AM)
      startAt = "03:00";

      # Retention: keep 7 daily, 4 weekly, 6 monthly
      prune.keep = {
        daily = 7;
        weekly = 4;
        monthly = 6;
      };

      # Stop services during backup for data consistency.
      # Home Assistant's SQLite database can corrupt if backed up
      # while HA is writing to it.
      preHook =
        (lib.optionalString ha.enable "systemctl stop home-assistant.service\n")
        + (lib.optionalString z2m.enable "systemctl stop zigbee2mqtt.service\n");

      # Use || true so a failure to start one service does not
      # prevent the other from being attempted.
      postHook =
        (lib.optionalString z2m.enable "systemctl start zigbee2mqtt.service || true\n")
        + (lib.optionalString ha.enable "systemctl start home-assistant.service || true\n");

      persistentTimer = true;
    };
  };
}
